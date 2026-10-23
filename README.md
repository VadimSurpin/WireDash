# WireDash

**An Android MQTT dashboard for Wiren Board, Zigbee2MQTT and custom MQTT devices, with embedded WireGuard.**

WireDash is a fork of [ZigDash](https://github.com/giladtamam/zigdash), created by
[Gilad Tamam](https://github.com/giladtamam). It keeps the original MIT license
and builds on its MQTT dashboards, device controls, scenes and tablet layouts.

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform: Android](https://img.shields.io/badge/Platform-Android-5CB400.svg)](https://github.com/VadimSurpin/WireDash/actions)
[![Built with Flutter](https://img.shields.io/badge/Built%20with-Flutter-02569B.svg)](https://flutter.dev)

Connect directly to your existing MQTT broker. WireDash does not require its
own server, cloud account or dashboard backend. Optional Node-RED flows on your
hub provide recording, alerts and automation when the phone is offline.

<p align="center">
  <img src="docs/screenshots/dashboard-light.png" width="220" alt="WireDash green device panels in light mode">
  <img src="docs/screenshots/dashboard-dark.png" width="220" alt="WireDash green device panels in dark mode">
  <img src="docs/screenshots/device-controls.png" width="220" alt="Light, brightness and colour controls in the green theme">
  <img src="docs/screenshots/devices.png" width="220" alt="The all-devices list in WireDash">
</p>

These are rendered views of the actual app widgets with demo devices and values.
See [screenshot sources and regeneration](docs/screenshots/README.md).

## Changes in this fork

- **[Embedded WireGuard](docs/EMBEDDED_WIREGUARD.md)** — import a peer configuration
  in the initial connection form or a home's settings. MQTT TCP, TLS, WebSocket
  and WSS can use the app's own tunnel, without a separate VPN app or system VPN
  permission. Configurations are encrypted on the device. Tunnel failures do not
  silently switch the broker connection to a direct route.
- **[Wiren Board discovery](docs/WIRENBOARD_DISCOVERY.md)** — discover devices and
  controls from retained `/devices/…` MQTT metadata. Add a whole device as one
  dashboard panel, or choose an individual property and its widget. Non-built-in
  devices are added automatically after discovery.
- **Organized device lists** — expand a device inline to browse its properties.
  Collapsible sections separate controller built-ins, added modules and WB
  mirrors of Zigbee2MQTT devices. Built-ins and WB Z2M sections start collapsed.
  Built-ins include cloud status, network connections, KNX gateway, battery and
  alarms.
- **Panel-specific controls and labels** — whole-device WB panels use the same
  style as Zigbee2MQTT panels. In the panel editor, choose visible properties and
  give them custom labels. Single properties offer a widget selector. **Allow
  commands** can explicitly enable editable widgets when metadata incorrectly
  marks a writable control read-only.
- **[Before-display JavaScript expressions](docs/DISPLAY_EXPRESSIONS.md)** — format
  each field before rendering, for example `Number(value).toFixed(2)` or
  `(Number(value) / 1000).toFixed(2)`. Test expressions in the editor. Formatting
  settings belong to each panel; commands keep their raw values.
- **[Wiren Board green theme](docs/WIRENBOARD_THEME.md)** — green device states,
  buttons and accents, matching light/dark surfaces, a new launcher icon and a
  matching startup splash. The Material You option remains available.
- **[No telemetry](docs/PRIVACY.md)** — the analytics SDK, event hooks, consent
  prompts, feature-request entry and roadmap poll are removed. Old queued usage
  records are cleared on upgrade. Manual help and problem-report actions remain
  user-initiated.
- **Localized UI** — 13 languages: English, Czech, Dutch, French, German, Hebrew,
  Italian, Norwegian Bokmål, Polish, Portuguese, Russian, Spanish and Swedish,
  including RTL layouts.

<p align="center">
  <img src="docs/screenshots/wirenboard-panel.png" width="412" alt="Wiren Board whole-device panel with a labelled relay, temperature and humidity">
</p>

## Dashboard features

WireDash also retains the original project's Zigbee2MQTT auto-discovery,
custom MQTT topics, JSON-path extraction, switches, sliders, covers, readings,
gauges, text controls, scenes, schedules and auto-close rules. It supports
multiple brokers, automatic reconnect, dashboard sections, per-panel editing
and JSON backup/restore.

For wall tablets, use fullscreen, dimming, a PIN-protected kiosk, a clock with
readings, motion wake-up and on-screen alarms. Android shortcuts include Quick
Settings tiles, Device Controls and home-screen widgets. Optional Node-RED
flows provide longer history and hub-side automation. The `foss` build exposes
all app features without Play billing.

## Install

WireDash does not currently publish its own Play Store release. Test APKs are
available from successful [check workflow runs](https://github.com/VadimSurpin/WireDash/actions/workflows/check.yml):
open a run on the combined branch and download the
`zigdash-wireguard-wirenboard-debug-arm64` artifact. The artifact retains its
original build-system name; it contains the WireDash app for ARM64 Android.

CI artifacts use the CI debug signing key. Updating an existing installation
requires an APK signed with the same key as that installation.

The default branch, `feat/wireguard-wirenboard`, combines these feature branches:

| Branch | Change |
| --- | --- |
| `feat/embedded-wireguard` | Embedded WireGuard transport and connection settings |
| `feat/wirenboard-discovery` | WB discovery, panels, display expressions and WireDash branding |
| `feat/remove-telemetry-feature-requests` | Telemetry SDK/hooks and feature-request/poll removal |
| `feat/wirenboard-green-theme` | Green light/dark theme |

## Build and test

Use the Flutter version in [.fvmrc](.fvmrc). `tool/flutter` selects it through
FVM or `ZIGDASH_FLUTTER`. Android builds also need Java 17, the Android SDK/NDK
and Go 1.26+ on `PATH`; see the [WireGuard build notes](docs/EMBEDDED_WIREGUARD.md#build-and-check).
Linux tests for display expressions additionally need CMake and a C/C++ compiler.

```bash
git clone https://github.com/VadimSurpin/WireDash.git
cd WireDash
tool/flutter pub get
tool/flutter pub run build_runner build --delete-conflicting-outputs
python3 tool/build_display_js_native.py
export JSF_LIBRARY_PATH="$PWD/.dart_tool/display-js-native/libjsf.so"
tool/flutter analyze
tool/flutter test
```

Build the ARM64 Android test APK:

```bash
tool/flutter build apk --debug --flavor foss --target-platform android-arm64
```

For release APKs:

```bash
tool/flutter build apk --release --flavor foss --split-per-abi \
  --no-tree-shake-icons --dart-define=ZIGDASH_FLAVOR=foss
```

Signing uses `android/key.properties` (gitignored). Keep your signing key stable
for updates. The Android application ID remains `com.giladtamam.zigdash` for
compatibility with the existing development APKs; renaming the GitHub fork does
not rename the package.

## Help and upstream credits

For issues specific to this fork, use the [WireDash issue tracker](https://github.com/VadimSurpin/WireDash/issues).
The in-app support email and community links are inherited from ZigDash and
still point to its upstream contacts; use this repository for WireDash changes.

The original project remains available here:

- [ZigDash source](https://github.com/giladtamam/zigdash) and [original README](https://github.com/giladtamam/zigdash#readme)
- [Original ZigDash on Google Play](https://play.google.com/store/apps/details?id=com.giladtamam.zigdash)
- [ZigDash website](https://zigdash.app) and [community](https://t.me/zigdash_app)
- [Support the original author](https://github.com/sponsors/giladtamam)

## License

[MIT](LICENSE). Original ZigDash code © 2026 Gilad Tamam.
The original license and copyright notice are preserved in this fork.
