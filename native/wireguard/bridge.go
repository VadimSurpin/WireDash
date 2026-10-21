// SPDX-License-Identifier: MIT
// Package wgbridge connects app sockets through wireguard-go and gVisor.
// It creates no system interface, route or Android VpnService. Only the
// public WireGuard endpoint uses the host network's DNS and UDP sockets.
package wgbridge

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"io"
	"net"
	"strconv"
	"sync"
	"time"

	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/netstack"
)

// Route owns a tunnel and an authenticated, single-use loopback listener.
// Dart writes Token's decoded bytes before starting MQTT/TLS. TLS stays in
// Dart, preserving the original hostname, SNI and platform trust store.
type Route struct {
	tunnel   *sharedTunnel
	listener net.Listener
	token    []byte
	ctx      context.Context
	cancel   context.CancelFunc
	mu       sync.Mutex
	closed   bool
	sockets  []net.Conn
}

// The UI and shortcut engine must share a device when they use the same
// peer key. Separate devices would make that peer roam between UDP ports,
// repeatedly interrupting the other MQTT session.
type sharedTunnel struct {
	key     [32]byte
	dev     *device.Device
	network *netstack.Net
	refs    int
}

var tunnels = struct {
	sync.Mutex
	live map[[32]byte]*sharedTunnel
}{live: make(map[[32]byte]*sharedTunnel)}

func acquireTunnel(text string) (*sharedTunnel, error) {
	key := sha256.Sum256([]byte(text))
	tunnels.Lock()
	defer tunnels.Unlock()
	if t := tunnels.live[key]; t != nil {
		t.refs++
		return t, nil
	}
	c, err := parseConfig(text, true)
	if err != nil {
		return nil, err
	}
	tun, network, err := netstack.CreateNetTUN(c.addresses, c.dns, c.mtu)
	if err != nil {
		return nil, errors.New("cannot create WireGuard network stack")
	}
	d := device.NewDevice(tun, conn.NewDefaultBind(), device.NewLogger(device.LogLevelSilent, ""))
	if err = d.IpcSet(c.uapi); err != nil {
		d.Close()
		return nil, errors.New("cannot configure WireGuard device")
	}
	if err = d.Up(); err != nil {
		d.Close()
		return nil, errors.New("cannot start WireGuard device")
	}
	t := &sharedTunnel{key: key, dev: d, network: network, refs: 1}
	tunnels.live[key] = t
	return t, nil
}

func (t *sharedTunnel) release() {
	tunnels.Lock()
	t.refs--
	last := t.refs == 0
	if last {
		delete(tunnels.live, t.key)
	}
	// Finish closing before another device with the same ListenPort starts.
	if last {
		t.dev.Close()
	}
	tunnels.Unlock()
}

// Start forwards exactly one app socket to host:port through the tunnel.
// Broker DNS uses Interface DNS inside the tunnel. No direct fallback.
func Start(text, host string, port, timeoutMs int) (*Route, error) {
	if host == "" || port < 1 || port > 65535 {
		return nil, errors.New("invalid broker address")
	}
	if timeoutMs <= 0 {
		timeoutMs = 15000
	}
	tunnel, err := acquireTunnel(text)
	if err != nil {
		return nil, err
	}
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		tunnel.release()
		return nil, errors.New("cannot open app socket")
	}
	token := make([]byte, 32)
	if _, err = rand.Read(token); err != nil {
		listener.Close()
		tunnel.release()
		return nil, err
	}
	ctx, cancel := context.WithCancel(context.Background())
	r := &Route{tunnel: tunnel, listener: listener, token: token, ctx: ctx, cancel: cancel}
	go r.serve(tunnel.network, net.JoinHostPort(host, strconv.Itoa(port)), time.Duration(timeoutMs)*time.Millisecond)
	return r, nil
}

func (r *Route) Port() int     { return r.listener.Addr().(*net.TCPAddr).Port }
func (r *Route) Token() string { return base64.StdEncoding.EncodeToString(r.token) }

func (r *Route) track(c net.Conn) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.closed {
		c.Close()
		return false
	}
	r.sockets = append(r.sockets, c)
	return true
}

func (r *Route) serve(network *netstack.Net, address string, timeout time.Duration) {
	defer r.Close()
	expiry := time.AfterFunc(timeout, r.Close)
	defer expiry.Stop()
	for {
		local, err := r.listener.Accept()
		if err != nil {
			return
		}
		if !r.track(local) {
			return
		}
		local.SetReadDeadline(time.Now().Add(2 * time.Second))
		provided := make([]byte, 32)
		_, err = io.ReadFull(local, provided)
		if err != nil || subtle.ConstantTimeCompare(provided, r.token) != 1 {
			local.Close()
			continue
		}
		local.SetReadDeadline(time.Time{})
		r.listener.Close()
		ctx, cancel := context.WithTimeout(r.ctx, timeout)
		remote, err := network.DialContext(ctx, "tcp", address)
		cancel()
		if err != nil {
			return
		}
		if !r.track(remote) {
			return
		}
		expiry.Stop()
		done := make(chan struct{}, 1)
		go func() { io.Copy(remote, local); done <- struct{}{} }()
		io.Copy(local, remote)
		r.Close()
		<-done
		return
	}
}

// Close is idempotent and interrupts pending accepts, DNS, dials and streams.
func (r *Route) Close() {
	r.mu.Lock()
	if r.closed {
		r.mu.Unlock()
		return
	}
	r.closed = true
	sockets := r.sockets
	r.sockets = nil
	r.mu.Unlock()
	r.cancel()
	r.listener.Close()
	for _, s := range sockets {
		s.Close()
	}
	r.tunnel.release()
}
