# Embedded WireGuard (Android)

Each MQTT home can connect through a private WireGuard tunnel inside ZigDash.
It needs neither a separate VPN app nor an additional dashboard server. Your
existing MQTT broker and WireGuard peer still need to be running.

## Set up

1. Create a dedicated WireGuard peer for ZigDash on your router or VPN server.
   Do not reuse a configuration currently active on another device or VPN app:
   the server would keep moving that peer's endpoint between the two clients.
2. Open the home's connection settings and expand **WireGuard settings**.
3. Enable **Use embedded WireGuard**, then import its `.conf` file or paste it.
   The eye button shows a saved configuration for editing; the hidden field
   is read-only so Android cannot flatten a pasted multi-line configuration.
4. Enter the broker's IP address inside your VPN, or a hostname resolvable by
   the `DNS` servers in the configuration. `AllowedIPs` must cover the broker
   and those DNS servers. Multicast `.local` discovery is not forwarded.
5. Use **Test connection**, then **Save**.

MQTT TCP, TLS, WebSocket and secure WebSocket use the tunnel. Both the local
and optional fallback broker address stay inside it; there is no automatic
direct connection when WireGuard fails. Disable WireGuard explicitly if you
want to connect directly again. Home Assistant API connections are separate
and do not offer this option.

Private keys and the configuration live in the existing encrypted credential
store, separately from the connection database. Dashboard exports contain no
WireGuard configuration. If Android restores the database without its keys,
the home still requires WireGuard and cannot connect until you import the
configuration again. Deleting a home deletes its stored WireGuard keys.
Editing or deleting a home also closes its cached dashboard and shortcut
connections so the next connection uses the current settings.

The tunnel lives as long as its MQTT connection and is recreated on reconnect.
The app and Android shortcuts share a native device for the same configuration.
Android may suspend the app in the background; this feature does not promise
continuous background monitoring. Other apps and Android's system VPN slot
are unaffected. Video playback is not part of this change.

## Configuration support

Supported `wg-quick` settings:

* `[Interface]`: `PrivateKey`, `Address` (IPv4 and/or IPv6 CIDRs), optional
  `DNS` (IP addresses), `MTU` (1280–9000), and `ListenPort`.
* One or more `[Peer]` sections: `PublicKey`, `Endpoint`, `AllowedIPs`, optional
  `PresharedKey` and `PersistentKeepalive`.

Absent keepalive defaults to 25 seconds; an explicit zero is respected. Only
the public WireGuard endpoint is resolved outside the tunnel. Unsupported
settings, including shell hooks, OS routing directives and DNS search domains,
are rejected instead of being silently ignored or executed.

## Implementation

The architecture follows Haven's per-app userspace approach: `wireguard-go`
plus gVisor netstack, bound to Android using `gomobile`. This bridge is a
separate MIT-licensed implementation; no Haven application code is included.
An authenticated, single-use loopback socket carries each MQTT connection to
the native stack. Its random token prevents other local apps from using it.
TLS remains in Dart, so the original broker hostname, certificate validation
and SNI are preserved for TLS and WSS. No certificate checks are disabled.

No Android `VpnService`, system routes, root privileges or VPN permission are
needed. The existing Internet and local-network permissions still apply.

## Build and check

In addition to the normal Flutter and Android prerequisites, install Go 1.26+
and an Android NDK, put Go and Java on `PATH`, and set `ANDROID_HOME` to the SDK.
The Android Gradle `preBuild` task runs:

```sh
bash tool/build_wireguard_android.sh
```

It builds pinned Go dependencies and gomobile tools from source, generating
the ignored `android/app/libs/wireguard.aar` for armv7, arm64 and x86_64.
Do not commit this AAR. The Go module, checksums and script are the source of
truth. Upstream wireguard-go is MIT; gVisor and gomobile use their respective
upstream licenses (Apache-2.0 and BSD-3-Clause).

```sh
cd native/wireguard
go test -race ./...
```

The native test creates two real WireGuard peers over loopback UDP and sends
TCP through the encrypted tunnel without root or a system interface. Dart
tests cover MQTT over TCP/TLS, certificate hostname verification, cancellation,
missing restored keys and diagnostics that do not probe outside the tunnel.
The certificates and key under `test/mqtt/fixtures/wireguard_*` are deliberately
public test fixtures and must never be used for a real broker.

Before submitting upstream, test on an Android device with your own VPN and
broker: import, Test connection, subscribe/publish, switch Wi-Fi/mobile data,
background/resume, use a shortcut while connected, and disable/re-enable the
option. Also confirm your separately installed system VPN still works.

The welcome screen also offers **Connect through WireGuard** on Android. The
initial manual connection form includes the same import/paste fields as the
connection editor. Validation messages and fields are translated in every
supported app language.
