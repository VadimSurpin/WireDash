# Play Store listing copy (ZigDash)

Per wayfinder ticket 06 (ASO overhaul, 2026-07-26): title exact-matches the
uncontested "zigbee2mqtt" keyword; first 3 lines of the full description carry
the hook + primary keywords (the fold is what Play's NLP indexes hardest).

## App name (max 30)
ZigDash: Zigbee2MQTT Dashboard

## Short description (max 80)
Needs Zigbee2MQTT. Dashboard that builds itself. Phone, wall tablet, kiosk mode.

(2026-10-14: leads with the Zigbee2MQTT requirement since Oct 6 to cut installs that never open; 'wall tablet' and 'kiosk mode' added for Play Explore and search. Translations in fastlane/metadata/android/*/short_description.txt.)

## Full description (max 4000)

ZigDash is the MQTT dashboard built for Zigbee2MQTT — it discovers your Zigbee devices automatically, so your smart home dashboard builds itself. No cloud, no ads, no account: free and open source. Control lights, shutters, switches and sensors from your phone or a wall-mounted tablet — and automate on your hub, even when your phone is off.

━━━━━━━━━━━━━━━━━━━━━━

AUTO-DISCOVERY FOR ZIGBEE2MQTT
• Scan your Zigbee2MQTT bridge and create a panel for every device with a single tap — no manual topic wiring.
• JSON path extraction on every panel, so ZigDash understands real Zigbee2MQTT messages out of the box.
• Per-panel custom topics, QoS, and retain when you want full control.

━━━━━━━━━━━━━━━━━━━━━━

CONNECT TO ANY BROKER
• Any MQTT broker — TCP, SSL/TLS, WebSocket, WSS (Mosquitto, EMQX, HiveMQ, SMLIGHT).
• Broker discovery auto-scans your local network.
• Username/password in hardware-backed secure storage — never plain text.
• Live status with automatic exponential-backoff reconnect.
• Tailscale support: remote access over your WireGuard mesh, no port forwarding.
• Multiple brokers with instant switching.

━━━━━━━━━━━━━━━━━━━━━━

16 PANEL TYPES — CONTROL EVERYTHING
Toggle, Button, Slider, Cover (open/stop/close with presets), Multi-State, Combo, Radio, LED Indicator, Node Status, Progress, Text Input, Text Log, Scene, Schedule, Auto-Close Rule, and Zigbee2MQTT Device Discovery. From lights and shutters to sensors and scenes — one zigbee dashboard for every device.

━━━━━━━━━━━━━━━━━━━━━━

SHORTCUTS — WITHOUT OPENING THE APP
• Quick Settings tiles: switch a light or plug in one tap, or set a shutter with a slider, right from the notification shade.
• Android Device Controls: every device on your dashboards as a card, with sliders for brightness and shutter position.
• Home-screen widgets: one device, a scene, or a group of up to five devices with scene buttons.

━━━━━━━━━━━━━━━━━━━━━━

ALERTS — EVEN WHEN THE APP IS CLOSED
• A leak, smoke, a door opened at night or a low battery: Node-RED on your hub watches, ZigDash sets it up in one tap, and the notification reaches your phone through Google's push, encrypted end to end. No account, no extra app, no battery drain.
• Share a Home's alerts with the household, or get them with the ntfy app on a phone without Google services.

AUTOMATION — RUNS WHEN YOUR PHONE IS OFF
• Schedule panels: daily open/close timers saved as retained MQTT config.
• Auto-Close Rules: turn a device off N seconds after it turns on — perfect for fans, pumps, and timed lights.
• Both run on your always-on hub (Node-RED on SMLIGHT, Raspberry Pi, or any MQTT-aware device). Bundled Node-RED flows included.

━━━━━━━━━━━━━━━━━━━━━━

POLISHED — PHONE & TABLET
• Material 3 with light, dark, and system themes; Android 12+ Material You dynamic color.
• Phone and tablet, portrait and landscape — ideal as a wall-mounted home automation dashboard.
• Eight languages — English, French, German, Spanish, Dutch, Swedish, Norwegian and Hebrew (עברית) — with automatic RTL.
• Responsive panel grid, dashboard lock, backup/restore as portable JSON, scenes.

━━━━━━━━━━━━━━━━━━━━━━

100% PRIVATE. NO CLOUD.
• No ads. No account. Anonymous usage data only if you opt in.
• Your data lives on your device and your MQTT broker — nowhere else.
• Open source (MIT). The code is public and auditable.

━━━━━━━━━━━━━━━━━━━━━━

WHO IS THIS FOR?
You run Zigbee2MQTT with your own broker (Mosquitto on a Raspberry Pi, SMLIGHT SMHUB…) — maybe alongside Home Assistant — and want fast control from your phone or a wall tablet without opening the Zigbee2MQTT web UI. Tired of cloud-dependent apps, vendor lock-in, and data collection? ZigDash is for you.

━━━━━━━━━━━━━━━━━━━━━━

WHAT YOU NEED
• A Zigbee2MQTT setup with an MQTT broker on your local network.
• Tailscale (optional) for remote access from outside your home.
• Node-RED (optional) for hub-side automation.

## Category
House & Home

## Tags / keywords
Keyword priority (ticket 06): zigbee2mqtt → mqtt dashboard → smart home →
long-description rotation: mqtt client, zigbee dashboard, home automation,
Node-RED, zigbee2mqtt dashboard.

zigbee, zigbee2mqtt, mqtt, smart home, home automation, dashboard, iot,
smarthome, homecontrol, iotdashboard, z2m, mosquitto, cover, shutter,
lighting, sensor, node-red, zigbee2mqtt dashboard, mqtt dashboard, mqtt client,
mqtt control, mqtt panel, smart home dashboard, home automation dashboard,
zigbee controller, zigbee control, zigbee dashboard, zigbee panel, tasmota,
esp32, esp8266, sonoff, shelly, local, privacy, offline, no cloud, open source,
material you, material 3, hebrew, עברית

## Screenshots (captioned, 2026-10-15)

Five phone shots per locale, 1080x1920, composed by `tool/store/captions.py`
from the raw emulator captures in `store/captures/<locale>/` (made by
`tool/store/capture.sh`). Each is a headline, a sub-line and the capture in
a device frame, in the app's fonts; the headline is what survives at search
card size. The first four are what a Play search card shows.

1. `01-dashboard` (light) — "Your Zigbee devices, zero setup" / needs Zigbee2MQTT and an MQTT broker.
2. `02-wall-tablet` (dark, the 10-inch capture) — "Made for the wall tablet" / kiosk mode.
3. `03-no-cloud` (dark) — "No cloud. No account. No ads." / free and open source.
4. `04-controls` (light, device sheet) — "Every control, one tap away".
5. `05-home-assistant` (light, devices list) — "Works beside Home Assistant".

The two raw tablet captures go to the 10-inch slots unchanged. Translations
of the captions live in the script (11 locales). An alerts shot would need a
new capture (the integration test has none); the README's alerts image is
English only.

Why: on 2026-10-15 the Play search card for "zigbee2mqtt dashboard" showed
four near-identical raw light-theme captures with unreadable text and no
rating row (too few ratings), so nothing on the card said what the app needs
or does. Captions put the requirement and the wall-tablet use on the card.

## Contact email
giladtamam1@gmail.com

## Privacy policy URL
https://github.com/giladtamam/zigdash/blob/main/store/PRIVACY.md (the app and Play Console link here from 2.0.1).
2.0.0 (build 29) still links https://gitlab.com/tamamg/zigdash/-/blob/main/store/PRIVACY.md, so keep that copy in sync until 2.0.1 is out.
