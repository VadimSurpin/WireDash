# ZigDash after 2.0: roadmap, and the 2.1 build spec

The releases after 2.0, in order, decided on 2026-10-08 to 2026-10-10 in the "Post-2.0 roadmap" map and accepted by the user. Release 2.1 is specced to hand-off depth below; later releases stay at roadmap resolution and get their own spec when they start. Words follow [CONTEXT.md](../../CONTEXT.md) (Home, Device tile, Last-known value, Not responding, **Shortcut**).

**Ranking rule:** user demand first, effort second. The demand evidence is thin and mostly from rival MQTT apps' reviews, so 2.2 carries a one-time poll that may reorder 2.3–2.5.

## Releases

| Release | Scope | Why this order |
|---|---|---|
| **2.1** | Shortcuts: Quick Settings tiles, Android Device Controls, rename a device. Reconnect-immediately fix. | Live on Play since 2026-10-10. Tiles and controls are asked for second most (about 34 rival-app reviews) and are measured feasible. |
| **2.2** | Home-screen widgets (one device, scene, group). "What next?" poll. Sent to Play 2026-10-10. | Moved from 2.1 (user, 2026-10-10) so tiles and controls shipped first; same engine. Built on `release/2.2` (2026-10-10); widgets are added from the launcher's list or from a device's page (Add shortcut) and a device or scene tile's Edit-mode menu. |
| **2.3** | Alerts (leak, smoke, door opened at night, low battery) delivered into ZigDash through Google's push, end-to-end encrypted, no second app. Android 17 local-network permission. Built on `release/2.3` 2026-10-11 ([alerts-2.3.md](alerts-2.3.md)); in trial on the user's phone before Play. | Most requested (about 25 reviews plus a dedicated rival app). The permission changes setup and must land well before targetSdk 37 is required (expected August 2027). |
| **2.4** | Gauge: a reading tile shown as a half arc with colour bands ([gauge-2.4.md](gauge-2.4.md)). The one-time "Join the ZigDash community" dashboard card. A "close all" action for a dashboard's covers (from the poll). | Split from history on 2026-10-11 (user): three small finished things ship now; the gauge is asked for in rival-app reviews (IoT MQTT Panel, 2026-10-10 scrape) and needs no hub work. |
| **2.5** | Setup help: the scan asks where Zigbee2MQTT runs, looks for Home Assistant, the Zigbee2MQTT frontend or an SMLIGHT hub when no broker answers, and says what it found and what is missing, with manual entry filled in ([setup-help-2.5.md](setup-help-2.5.md)). | Moved in front of history on 2026-10-12 (user): every opted-in new install so far stalled on an empty scan; nothing else measured loses users. |
| **2.6** | Kiosk mode: Wall display grows a Kiosk lock (PIN, optional Android screen pinning), Fullscreen and Dim ([kiosk-2.6.md](kiosk-2.6.md)). | Moved in front of history on 2026-10-12 (user). Medium demand, mostly lock and fullscreen. |
| **2.7** | History graphs (24 hours free; 7 and 30 days in the one-time Pro unlock) ([history-2.7.md](history-2.7.md)). | Medium demand; needs a recorder, which Node-RED on the hub provides. |
| Later, if asked | Zigbee groups, firmware (OTA) updates, Zigbee network map. | Low demand; all possible over Zigbee2MQTT 2.x MQTT. |
| Dropped | Voice (needs Home Assistant's Assist), energy dashboard (low demand, only after history), conditional tiles (no demand). | |

**Constraint for every release:** ZigDash has no server of its own. It's a phone app speaking MQTT to the user's broker, with optional Node-RED on the hub for anything that must run while the phone is off.

## 2.3 to 2.5 at roadmap resolution

- **2.3 Push notifications.** Specced in [alerts-2.3.md](alerts-2.3.md) (2026-10-10). Node-RED on the hub is the alert engine; ZigDash configures an alerts flow over retained MQTT, the same way it configures schedules. Delivery starts with ntfy (high-priority FCM through Doze, no account, free up to 250 messages a day); UnifiedPush for native notifications is a later phase. Background MQTT on the phone is rejected (battery, `dataSync` limits, OEM killers). Node-RED republishes alerts retained at QoS 1 on `zigdash/alerts/...` so the app catches up. Research: branch `research/reliable-alerts`.
- **2.3 Local-network permission.** At targetSdk 37, LAN connections need `ACCESS_LOCAL_NETWORK`; without it, connecting to the broker times out. Setup explains the permission before asking.
- **2.4 Gauge.** Specced in [gauge-2.4.md](gauge-2.4.md) (2026-10-11). Not a new tile type: a style of the Reading tile, with a min, max and up to three colour bands drawn from the theme's state roles (Good, Attention), defaults from the device's expose or a preset per reading. Rival reviews ask for color gradients on gauges and for a plain value display; one tile with two styles covers both. No hub work.
- **2.6 Kiosk.** Specced in [kiosk-2.6.md](kiosk-2.6.md) (2026-10-12). One feature: the Wall display sheet with the Kiosk lock (in-app PIN, Android screen pinning as an extra), Fullscreen and Dim. A router redirect keeps a kiosk on its Home's dashboards.
- **2.7 History.** Zigbee2MQTT keeps no history, so a Node-RED flow on the hub records chosen readings; the app draws them. Decided 2026-10-15 ([history-2.7.md](history-2.7.md)): retained day records on the broker, kept 30 days; every reading tile is recorded; a tap on a reading tile opens its history.
- **2.7.1 Setup on a real Home Assistant home.** From a phone test on 2026-10-16: a pasted Home Assistant link works in the broker form, several brokers found are named (Home Assistant, SMLIGHT hub, Zigbee2MQTT), the platform question stays after a fast scan, unnamed devices read "Motion sensor f66f", climate sensors are preselected, and a rejected login points at the login Zigbee2MQTT uses. Names given in Home Assistant never reach MQTT, so ZigDash cannot show them.
- **2.7.2 Ask Zigbee2MQTT where its broker is.** From a Romanian user on 2026-10-16 who found Zigbee2MQTT's page but no broker: setup reads `mqtt.server` from the page's API and connects to it, or says the broker listens only on its own machine and shows the two Mosquitto lines. The broker form now reports which step failed (`setup_step manual_test`). Next: import names and rooms from Home Assistant ([ha-import.md](ha-import.md)).
- **2.8 Import from Home Assistant.** Names, rooms and floors read once from Home Assistant's registries and matched to Zigbee2MQTT devices by IEEE: tiles named, a dashboard per floor with a section per room. Sign-in on Home Assistant's own page (client_id on GitHub Pages, PKCE, revoked after), a long-lived token as the fallback. Offered once after setup when Home Assistant is seen, and in Settings › Home ([ha-import.md](ha-import.md)). Verified on the user's phone and Home Assistant 2026-10-16. Next: 2.9 wall-tablet pack with Pro.
- **2.8.1 Friendlier setup.** From sessions on 2026-10-16: the login step says the login stays on the phone and goes only to the user's broker, links the policy and offers the demo first (one user left it within seconds); an empty scan where only 1-5 hosts answered suggests a guest network or client isolation (two users); the review prompt also counts live device data and happy moments (a finished import, history set up), since sensor-only homes never sent the command it waited for (one prompt in 30 days).
- **2.8.2 A login the broker never answers.** From a Spanish Home Assistant user on 2026-10-17 who got "unknown" twice after typing a login: mqtt_client leaves `returnCode` at `noneSpecified` until a CONNACK arrives, and the connection check took that for an accepted login, then threw on the dead client. No CONNACK now fails the handshake step, and with a login setup says "The broker didn't answer the login" (Home Assistant's Mosquitto add-on checks logins with Home Assistant, slow on a Pi) and retries the same login. The unknown error screen also showed "Try again" three times (missing keys). Timeouts unchanged: if the next such user gets the new message, raise the handshake budget in both the check and the live connection together.
- **2.9 Wall tablet.** When no one touches it: dimmed, a clock or black (free); with Pro: readings under the clock, wake on a Zigbee motion sensor, a night schedule, and alarm takeover (leak, smoke, gas, CO fill the screen with the alarm tone until OK). Pro goes live on Play with this release: `zigdash_pro`, EUR 7.99 on the shelf, together with 7- and 30-day history ([wall-tablet-2.9.md](wall-tablet-2.9.md)).
- **2.9.1 History without Node-RED.** From the only 2.8.1 user who connected (UK, 2026-10-16), who got "no Node-RED found" twice: a device the user picks (a wall tablet) records while ZigDash is open, writing the same heartbeat and day records as the Node-RED flow ([history-without-node-red.md](history-without-node-red.md)). Also: the idle clock waits while a sheet is open.
- **2.9.2 Fewer dead ends.** From 2026-10-17 sessions: setup finds Zigbee2MQTT under its own base topic (it listens for `+/bridge/state`; a German user got "not Zigbee2MQTT" twice); after two failed Test & connect a "Stuck? Ask a person" card offers Telegram and Get help (6 of 53 stuck users opened the old link); Wake on motion lists sensors by tile name.
- **2.9.3 A second look.** From 2026-10-17/18 sessions: two users whose scan found nothing typed their broker and connected at once, and every Home Assistant user got "no hub found". When nothing is found, the /24's silent hosts get a second look with 1.5 s instead of 0.5 s (`late` in scan_empty/scan_found says whether it helps; unproven, the other story is a broker outside the /22). The broker test names a `.local` name (use the IP), Home Assistant without a broker on 1883 (Mosquitto add-on) and a Home Assistant login refused (results local_name, ha_no_broker, ha_login). Next: the same for an SMLIGHT hub whose broker is closed.
- **2.9.4 Not on Wi-Fi.** 2026-10-18/19: three users (Norway, Bavaria, Australia) got scan_failed (no home address) and tapped Try again up to 8 times. The screen now says why (mobile data, no network, unknown; never guesses mobile data), opens Android's Wi-Fi panel, and scans again by itself once there is an address (a quiet 2 s recheck, so scan_failed stays one per attempt). setup_step failed gains `why`. 2.9.3's first data: Greece late 6-20 (the second look reached most hosts, none had a broker), Michigan late 0. PRIVACY now lists 2.9.3's late and Test results too.
- **2.9.5 The lean-setup story.** 2026-10-19: the welcome says what ZigDash needs and what it doesn't: a small hub running Zigbee2MQTT (SMLIGHT, Raspberry Pi, any Linux box), no Home Assistant needed, works with it too. Same words on zigdash.app (live the same day) and in the Play short description. Texts only; no new analytics. Next: the Home Assistant empty scan (13 of 20 HA users left there; a French 2.9.4 user scanned twice without seeing HA on 8123) and refused port 1883 (17 manual tests).

## 2.1 build spec: shortcuts

**Branch:** `release/2.1` from `main`. **Base research:** branch `research/android-widgets` (feasibility, plugins, effort) and branch `spike/headless-command` (`docs/spike/headless-command-latency.md`, measured tap latency).

### Scope

In: widgets (one device, group), Quick Settings tiles, Device Controls, one shared headless command engine, adding shortcuts from the home screen and from inside ZigDash, the reconnect-immediately fix, a one-time poll card, analytics events for shortcuts and the poll, store listing and screenshots for shortcuts, 11 languages.

Out: a whole-dashboard widget, background refresh of shortcuts, Zigbee groups, iOS.

### 1. The command engine

One cached headless `FlutterEngine` runs a Dart entrypoint on ZigDash's own `lib/mqtt` (`MqttManager`), shared by all three shortcut kinds. No persistent foreground service, and no WorkManager for taps.

Measured on a Galaxy S24 FE (Android 16) against the user's SMHUB, tap to Zigbee2MQTT's reply: tile cold median 212 ms, warm 92–117 ms; widget path cold 280 ms, warm 185 ms. Engine start 67–151 ms cold. The Dart engine stays; no native MQTT port.

Rules the measurement set:

- **Reconnect immediately on a tap.** A connection that died while the app idled must not wait for the reconnect backoff (measured 2.2 s). A tap calls the no-backoff reconnect; if nothing has arrived for longer than the keep-alive, treat the connection as dead and reconnect at once. The same applies when the app itself returns to the foreground.
- **Each connect attempt has its own deadline,** so an attempt that hung while Android blocked the network can't wedge the next one.
- **Widget taps run as a short user-initiated foreground task** (widget `PendingIntent` → `shortService` foreground service), because Android 16 can block network for idle apps (`blocked=APP_BACKGROUND`, seen on the emulator). Tiles and Device Controls are bound by SystemUI and don't need this.
- **Tiles pre-warm the engine** when the Quick Settings panel opens (`onStartListening`).
- **Endpoints:** same order as the app: the local address, then the remote address (Tailscale or other).

### 2. How a shortcut behaves

- **Home:** each shortcut is tied to one device (or one group) in one Home, chosen when it's added. Switching Homes in the app doesn't change it. If the device or Home is deleted, the shortcut shows "Removed" and opens ZigDash when tapped.
- **After a tap:** show "working…" and change state only when the device confirms its new state. No optimistic flip. No confirmation within 5 s → show that it wasn't confirmed.
- **Hub unreachable:** try on every tap. On failure, keep the Last-known value with its age and show "Can't reach home" for about 10 s.
- **Not responding device:** send anyway; without confirmation show "Not responding".
- **Freshness:** refresh only after a tap or while the app runs. Otherwise show the Last-known value with its age ("40 min ago"). No background refresh.
- **Sensors and contacts** in a widget show their reading; tapping opens ZigDash on that device.
- **Shutters have a position, not on/off** (user, 2026-10-10). A shutter's tile, and its widget's name, open the **shutter pop-up**: live state line, a position slider (0–100%) and Open / Stop / Close. A widget also shows the position as a bar with ▲ ■ ▼ buttons (widgets can't hold sliders). Device Controls use Android's own slider. A shutter command is confirmed when its motor starts, and the engine follows it until it stops.

### 3. Widgets

Prototype: branch `prototype/shortcuts`, `docs/design/prototypes/shortcuts-prototype.html`.

- **One device:** 2×2 square or 4×1 strip. Icon, name, state line (value, "working…", age, or problem). Amber when on, Signal theme, light and dark following the system.
- **Scene button:** a one-device-sized widget that runs a scene; its state line shows "sent" then "confirmed".
- **Group:** 4×2 to 4×4, a title (the group's name), up to five devices as rows, and a row of up to three scene buttons.
- Native layouts (RemoteViews); `home_widget` may be used for data and update plumbing only, not for its WorkManager tap path.

### 4. Quick Settings tiles and Device Controls

- **Tiles:** one device per tile, toggled on and off; a shutter's tile opens the shutter pop-up instead. Label = device name, subtitle = state line. Unavailable devices (sensors) can't be tiles. Long-press opens ZigDash on the device. On a locked phone a tap asks for the unlock first (user, 2026-10-10); Device Controls follow Android's own "control from locked device" setting. Android limits how many tiles one app can offer; ZigDash declares a fixed set of tile slots that the user assigns to devices.
- **Device Controls** (Android 11+): one control per device in a "ZigDash · <Home>" structure. Lights, plugs and switches toggle; dimmable lights and covers get a slider (Android draws it); sensors are status-only. Android decides the look.

### 5. Adding shortcuts

- **From the home screen:** Widgets › ZigDash › drag a widget; ZigDash's picker opens: choose the Home, then the device, scene or group. Reconfigure by long-press (Android 12+).
- **From inside ZigDash:** "Add shortcut" on a device's page and in a tile's Edit-mode menu: choose widget, tile or control, then Android's own pin-widget or add-tile prompt confirms. Groups are created in the picker from a dashboard section or a hand-picked list.

### 6. Poll card

A one-time card on the dashboard after the user has used the app on three different days: "What should ZigDash do next?" with four choices (notifications, history graphs, kiosk mode, Zigbee groups) and "Not now". Shown once. The answer is sent as an opt-in analytics event (`poll_answer`, choice as an enum); users who haven't opted in see a line pointing to Request a feature instead.

### 7. Analytics (ADR 0006)

- `shortcut_added`: kind (widget, group_widget, scene_widget, tile, control).
- `shortcut_used`: kind, once per session per kind.
- `poll_answer`: choice.
The privacy policy lists them.

### 8. Effort

From the research: latency spike done; widgets about 1–1.5 weeks, tiles 3–5 days, Device Controls 1–2 weeks, plus the poll, analytics, store assets and translations.

### 9. Exit checks

- A cold tap under 3 s on the Galaxy S24 FE and on one slower, older phone; warm under 1 s.
- Every behaviour in section 2 checked on a real hub: confirmed, not confirmed, can't reach home (broker off), not responding (device unplugged), remote over Tailscale.
- Widgets in light and dark at each size; Hebrew right to left.
- After a month: at least 15% of opted-in active users have added a shortcut; the crash rate hasn't risen.

### Risks

- OEM skins may hide or restyle Device Controls, and few users add the Device Controls tile.
- Some launchers handle widget reconfiguration poorly; removing and re-adding stays the fallback.
- Android may tighten background network further; the foreground-task rule in section 1 is the mitigation.
