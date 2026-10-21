// SPDX-License-Identifier: MIT
package wgbridge

import (
	"context"
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"io"
	"net"
	"net/netip"
	"strings"
	"testing"
	"time"

	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/netstack"
)

func testConfig() string {
	k := base64.StdEncoding.EncodeToString(make([]byte, 32))
	return fmt.Sprintf("[Interface]\nPrivateKey = %s\nAddress = 10.77.0.2/32\nDNS = 10.77.0.1\n[Peer]\nPublicKey = %s\nAllowedIPs = 10.77.0.0/24\nEndpoint = localhost:51820\n", k, k)
}

func TestConfig(t *testing.T) {
	c, err := parseConfig(testConfig(), false)
	if err != nil {
		t.Fatal(err)
	}
	if len(c.addresses) != 1 || len(c.dns) != 1 || c.mtu != 1280 || !strings.Contains(c.uapi, "interval=25\n") {
		t.Fatal("unexpected parsed configuration")
	}
	for _, text := range []string{"", testConfig() + "PostUp = echo secret\n", strings.ReplaceAll(testConfig(), "10.77.0.2/32", "wrong"), strings.ReplaceAll(testConfig(), "localhost:51820", "localhost:0"), strings.ReplaceAll(testConfig(), "AllowedIPs = 10.77.0.0/24", "AllowedIPs = wrong"), strings.ReplaceAll(testConfig(), "DNS = 10.77.0.1", "DNS = search.example"), strings.ReplaceAll(testConfig(), "[Peer]", "[Unknown]")} {
		if err := Validate(text); err == nil {
			t.Error("invalid configuration accepted")
		}
	}
	c, err = parseConfig(testConfig()+"PersistentKeepalive = 0\n", false)
	if err != nil || strings.Contains(c.uapi, "interval=25") {
		t.Fatal("explicit keepalive must be preserved")
	}
	// wg-quick settings need not appear in WireGuard UAPI order.
	reordered := strings.ReplaceAll(testConfig(), "PublicKey = "+strings.Repeat("A", 43)+"=\n", "") + "PublicKey = " + strings.Repeat("A", 43) + "=\n"
	if err := Validate(reordered); err != nil {
		t.Fatal(err)
	}
	secret := "not-a-real-private-key"
	err = Validate(strings.Replace(testConfig(), "PrivateKey = ", "PrivateKey = "+secret, 1))
	if err == nil || strings.Contains(err.Error(), secret) {
		t.Fatal("errors must not expose secret values")
	}
}

func TestEndpointResolution(t *testing.T) {
	for _, endpoint := range []string{"127.0.0.1:51820", "[::1]:51820"} {
		c, err := parseConfig(strings.ReplaceAll(testConfig(), "localhost:51820", endpoint), true)
		if err != nil || !strings.Contains(c.uapi, "endpoint="+endpoint+"\n") {
			t.Fatalf("literal endpoint must preserve its address family: %v", err)
		}
	}
	previous := net.DefaultResolver
	net.DefaultResolver = &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, _, _ string) (net.Conn, error) {
		<-ctx.Done()
		return nil, ctx.Err()
	}}
	defer func() { net.DefaultResolver = previous }()
	start := time.Now()
	_, err := parseConfig(strings.ReplaceAll(testConfig(), "localhost:51820", "wg-resolution-test.invalid:51820"), true)
	if err == nil || err.Error() != "cannot resolve WireGuard endpoint" {
		t.Fatalf("expected a redacted resolution failure: %v", err)
	}
	if time.Since(start) > 7*time.Second {
		t.Fatal("endpoint resolution exceeded its timeout")
	}
}

// Real encrypted UDP between two wireguard-go devices and a gVisor TCP
// server. Runs without root, a system interface or external credentials.
func TestRouteThroughWireGuard(t *testing.T) {
	sk, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	ck, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	udp, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	port := udp.LocalAddr().(*net.UDPAddr).Port
	udp.Close()
	tun, network, err := netstack.CreateNetTUN([]netip.Addr{netip.MustParseAddr("10.77.0.1")}, nil, 1280)
	if err != nil {
		t.Fatal(err)
	}
	server := device.NewDevice(tun, conn.NewDefaultBind(), device.NewLogger(device.LogLevelSilent, ""))
	t.Cleanup(server.Close)
	err = server.IpcSet(fmt.Sprintf("private_key=%s\nlisten_port=%d\npublic_key=%s\nallowed_ip=10.77.0.2/32\n", hex.EncodeToString(sk.Bytes()), port, hex.EncodeToString(ck.PublicKey().Bytes())))
	if err != nil {
		t.Fatal(err)
	}
	if err = server.Up(); err != nil {
		t.Fatal(err)
	}
	ln, err := network.ListenTCP(&net.TCPAddr{IP: net.IPv4(10, 77, 0, 1), Port: 1883})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	go func() {
		c, e := ln.Accept()
		if e != nil {
			return
		}
		defer c.Close()
		io.Copy(c, c)
	}()
	text := fmt.Sprintf("[Interface]\nPrivateKey = %s\nAddress = 10.77.0.2/32\n[Peer]\nPublicKey = %s\nEndpoint = 127.0.0.1:%d\nAllowedIPs = 10.77.0.1/32\n", base64.StdEncoding.EncodeToString(ck.Bytes()), base64.StdEncoding.EncodeToString(sk.PublicKey().Bytes()), port)
	r, err := Start(text, "10.77.0.1", 1883, 10000)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(r.Close)
	// A shortcut can borrow the same peer while the dashboard is connected.
	// Releasing that shortcut must not tear down the dashboard's tunnel.
	shortcut, err := Start(text, "10.77.0.1", 1883, 10000)
	if err != nil {
		t.Fatal(err)
	}
	if shortcut.tunnel != r.tunnel {
		t.Fatal("same peer must share its WireGuard device")
	}
	shortcut.Close()
	address := net.JoinHostPort("127.0.0.1", fmt.Sprint(r.Port()))
	bad, err := net.Dial("tcp", address)
	if err != nil {
		t.Fatal(err)
	}
	bad.Write(make([]byte, 32))
	bad.SetReadDeadline(time.Now().Add(time.Second))
	if _, err = bad.Read(make([]byte, 1)); err == nil {
		t.Fatal("unauthenticated socket accepted")
	}
	bad.Close()
	socket, err := net.Dial("tcp", address)
	if err != nil {
		t.Fatal(err)
	}
	defer socket.Close()
	socket.SetDeadline(time.Now().Add(10 * time.Second))
	token, _ := base64.StdEncoding.DecodeString(r.Token())
	socket.Write(append(token, []byte("MQTT over WireGuard")...))
	got := make([]byte, len("MQTT over WireGuard"))
	if _, err = io.ReadFull(socket, got); err != nil {
		t.Fatal(err)
	}
	if string(got) != "MQTT over WireGuard" {
		t.Fatal("unexpected echo")
	}
	r.Close()
	r.Close()
	if _, err = socket.Read(make([]byte, 1)); err == nil {
		t.Fatal("closing route must close socket")
	}
}

func TestCloseBeforeConnect(t *testing.T) {
	r, err := Start(testConfig(), "10.77.0.1", 1883, 500)
	if err != nil {
		t.Fatal(err)
	}
	address := net.JoinHostPort("127.0.0.1", fmt.Sprint(r.Port()))
	r.Close()
	if c, err := net.DialTimeout("tcp", address, time.Second); err == nil {
		c.Close()
		t.Fatal("closed route accepts connections")
	}
}
