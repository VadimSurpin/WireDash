// SPDX-License-Identifier: MIT
package wgbridge

import (
	"context"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"net"
	"net/netip"
	"strconv"
	"strings"
	"time"
)

type config struct {
	addresses, dns []netip.Addr
	mtu            int
	uapi           string
}

// Validate checks a wg-quick config without starting a tunnel or resolving
// endpoints. Error messages never include configuration values or keys.
func Validate(text string) error { _, err := parseConfig(text, false); return err }

func parseConfig(text string, resolve bool) (config, error) {
	c := config{mtu: 1280}
	sections := []map[string]string{}
	var current map[string]string
	for _, original := range strings.Split(text, "\n") {
		line := strings.TrimSpace(strings.SplitN(original, "#", 2)[0])
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, "[") {
			name := strings.ToLower(line)
			if (len(sections) == 0 && name != "[interface]") || (len(sections) > 0 && name != "[peer]") {
				return c, errors.New("expected one Interface followed by Peer sections")
			}
			current = map[string]string{}
			sections = append(sections, current)
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok || current == nil {
			return c, errors.New("expected a WireGuard key=value setting")
		}
		key = strings.ToLower(strings.TrimSpace(key))
		if _, exists := current[key]; exists {
			return c, errors.New("duplicate WireGuard setting")
		}
		current[key] = strings.TrimSpace(value)
	}
	if len(sections) < 2 {
		return c, errors.New("configuration needs an Interface and at least one Peer")
	}
	var u strings.Builder
	writeKey := func(name, value string) error {
		b, err := base64.StdEncoding.DecodeString(value)
		if err != nil || len(b) != 32 {
			return errors.New("WireGuard keys must be 32 bytes encoded as base64")
		}
		fmt.Fprintf(&u, "%s=%s\n", name, hex.EncodeToString(b))
		return nil
	}
	for i, s := range sections {
		allowed := map[string]bool{"publickey": true, "presharedkey": true, "endpoint": true, "allowedips": true, "persistentkeepalive": true}
		if i == 0 {
			allowed = map[string]bool{"privatekey": true, "address": true, "dns": true, "mtu": true, "listenport": true}
		}
		for k := range s {
			if !allowed[k] {
				return c, errors.New("unsupported WireGuard setting; scripts, routing and save hooks are not supported")
			}
		}
		if i == 0 {
			if err := writeKey("private_key", s["privatekey"]); err != nil {
				return c, err
			}
			for _, part := range strings.Split(s["address"], ",") {
				p, err := netip.ParsePrefix(strings.TrimSpace(part))
				if err != nil {
					return c, errors.New("invalid Interface Address")
				}
				c.addresses = append(c.addresses, p.Addr())
			}
			if s["dns"] != "" {
				for _, part := range strings.Split(s["dns"], ",") {
					a, err := netip.ParseAddr(strings.TrimSpace(part))
					if err != nil {
						return c, errors.New("DNS must contain IP addresses, not search domains")
					}
					c.dns = append(c.dns, a)
				}
			}
			if value, ok := s["mtu"]; ok {
				n, err := strconv.Atoi(value)
				if err != nil || n < 1280 || n > 9000 {
					return c, errors.New("MTU must be between 1280 and 9000")
				}
				c.mtu = n
			}
			if value, ok := s["listenport"]; ok {
				n, err := strconv.Atoi(value)
				if err != nil || n < 0 || n > 65535 {
					return c, errors.New("invalid ListenPort")
				}
				fmt.Fprintf(&u, "listen_port=%d\n", n)
			}
			continue
		}
		if err := writeKey("public_key", s["publickey"]); err != nil {
			return c, err
		}
		if value, ok := s["presharedkey"]; ok {
			if err := writeKey("preshared_key", value); err != nil {
				return c, err
			}
		}
		for _, part := range strings.Split(s["allowedips"], ",") {
			p, err := netip.ParsePrefix(strings.TrimSpace(part))
			if err != nil {
				return c, errors.New("invalid or missing AllowedIPs")
			}
			fmt.Fprintf(&u, "allowed_ip=%s\n", p.Masked())
		}
		host, port, err := net.SplitHostPort(s["endpoint"])
		if err != nil || host == "" {
			return c, errors.New("Endpoint must be host:port (bracket IPv6 addresses)")
		}
		n, err := strconv.Atoi(port)
		if err != nil || n < 1 || n > 65535 {
			return c, errors.New("invalid Endpoint port")
		}
		if resolve {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			ips, err := net.DefaultResolver.LookupNetIP(ctx, "ip", host)
			cancel()
			if err != nil || len(ips) == 0 {
				return c, errors.New("cannot resolve WireGuard endpoint")
			}
			// Match the UDP resolver preference for IPv4 when available.
			ip := ips[0].Unmap()
			for _, candidate := range ips {
				if candidate.Unmap().Is4() {
					ip = candidate.Unmap()
					break
				}
			}
			fmt.Fprintf(&u, "endpoint=%s\n", net.JoinHostPort(ip.String(), port))
		}
		keepalive := 25
		if value, ok := s["persistentkeepalive"]; ok {
			n, err := strconv.Atoi(value)
			if err != nil || n < 0 || n > 65535 {
				return c, errors.New("invalid PersistentKeepalive")
			}
			keepalive = n
		}
		fmt.Fprintf(&u, "persistent_keepalive_interval=%d\n", keepalive)
	}
	c.uapi = u.String()
	return c, nil
}
