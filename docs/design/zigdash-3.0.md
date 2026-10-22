# ZigDash 3.0: automations and remote control (hand-off spec)

Decided with the user on 2026-10-22 through the wayfinder map "ZigDash 3.0: where automation lives" (local planning branch `wayfinder/roadmap`, folder `v3/`). Each section names the ticket that holds the detail. Words follow [CONTEXT.md](../../CONTEXT.md): **Automation**, **Engine**, **Automations paused**, **Recent runs**, **Alert**, **Scene**, **Home**.

Research behind it (unpushed branches): `research/z2m-extension`, `research/fallback-hub`, `research/relay-stack`. Accepted prototype: `prototype/automations-3.0` (`prototype/automations/index.html`).

## What 3.0 is

- **Automations**: the home acts on its own. When a trigger happens and its conditions hold, an action runs.
- **One Engine on the hub** runs Automations, Alerts and the history Recorder. Node-RED is no longer needed.
- **Remote control** from away, through a relay ZigDash hosts, for Pro.
- **Still no account.** The Play listing keeps "no account".

For Zigbee2MQTT homes without Home Assistant. A Home that runs Home Assistant automates in Home Assistant, and gets remote control through the existing HA route.

## 1. Automations (tickets 06, 07)

**Triggers**
- A device changes: occupancy detected or cleared, contact opened or closed, a button action, a numeric reading above or below a value, a light or plug state.
- A time comes: a clock time, or sunrise or sunset with a shift in minutes, on chosen days.

**Conditions** (optional, all must hold): between two times; another device is in a given state.

**Actions**: run a Scene, or set one device to a state; optionally turn it off again after N minutes. No general delay or repeat in 3.0 (3.1 if users ask).

**Editor** as in the prototype: When / Only if / Then, optional name (auto-named otherwise), Enabled switch, Delete. **List**: each rule in words, enabled switch, Edit, a "ran 22:14" or "never ran" pill, **Recent runs** below, a header pill "Running on hub" or "On ZigDash server".

**Free and Pro**: three Automations per Home free, unlimited with Pro. Enforced on the phone, like every Pro gate. The fourth + opens the Pro sheet; existing rules keep running whatever the user chooses. FOSS and GitHub builds are unlimited.

**Sun times**: the user types a town; the app resolves it from a bundled offline city table (~25,000 cities, ~1 MB) and writes timezone and coordinates to the hub. No location permission, no network lookup.

## 2. The Engine (ticket 04)

**Where it runs**
- **On the hub, inside Zigbee2MQTT**, as a ZigDash extension the app installs over MQTT (`<base>/bridge/request/extension/save`). It loads at once, with no restart. This is the default and the only engine for free Homes.
- **On ZigDash's server**, only for a Pro Home whose hub cannot run the extension, fed by a Mosquitto bridge. The Home's device states then reach the server unencrypted, by explicit choice, and are kept 24 hours.
- Rules run with the internet down wherever the hub runs them. The server is a fallback, never the default.
- No wall-tablet engine; the tablet stays a history recorder fallback.

**Version floor**: Zigbee2MQTT 2.4. Read from retained `bridge/info`. Below it, the Automations, Alerts and History screens say "Your Zigbee2MQTT is version X. Automations need 2.4 or newer" with update steps for the platform. 1.x (≈1.4% of installs) gets no Engine.

**First install**: from the first Automation, the first Alert or the first history setup, one screen ("Automations run on your hub, not on your phone"; context word changes for Alerts and History), the version check, Install on hub, progress until the Engine reports in.

**Gated fresh installs**: Zigbee2MQTT ≥ 2.11 installed fresh has `advanced.enable_external_js: false`, and the save request then gets no reply. The app reads the flag from `bridge/info` and shows the consent screen: it would turn on "Allow external JavaScript" and restart Zigbee2MQTT, about 30 seconds without Zigbee. Yes: `bridge/request/options` then `bridge/request/restart`, then install. Not now: a free Home sees "No automations on this hub"; a Pro Home is also offered the server engine, whose screen states plainly what leaves the home.

**Paused**: the Engine publishes its state every 30 seconds. Older than 90 seconds = **Automations paused** (banner on the Automations screen, one chip on the dashboard; rules stay editable; Reinstall on hub). Same mechanics as Alerts paused.

**Crash safety (hard requirement)**: Zigbee2MQTT has no crash guard, so an unhandled error in the extension stops Zigbee2MQTT and the Zigbee network. Every handler and timer is wrapped; every MQTT client has an `error` listener; no un-awaited promises. After three crashes in an hour the extension disables itself (flag file) and the app says "Automations paused: the engine stopped itself" with Start again and Report a problem.

**Updates**: the app re-saves the extension silently when its bundled version is newer than the one the hub reports. If Zigbee2MQTT renamed it `*.invalid` after a breaking release, the app notices through `bridge/extensions` and re-saves.

**No secrets in the extension source**: its code is visible on `bridge/extensions` and in the Zigbee2MQTT frontend. Relay credentials and the home key live in a data-dir file or a retained topic, never in the code.

**Moving a Pro Home between engines**: one toggle on the Automations screen, make-before-break: the new engine starts and reports `running_on`, then the app disables the old one.

## 3. The rules contract (ticket 07)

All retained, QoS 1, under the Home's broker:

| Topic | Who writes | Content |
|---|---|---|
| `zigdash/automations/rules/<id>` | app | `{v: 1, id, name, enabled, trigger, conditions, action}`; cleared to delete |
| `zigdash/automations/meta` | app | schema version, IANA timezone, latitude/longitude, town name |
| `zigdash/automations/state` | engine, every 30 s | engine version, rules loaded, rules not understood, `running_on: hub\|server`, `stopped_self` |
| `zigdash/automations/recent` | engine | last 20 runs: rule id, time, what it did |

- The hub's retained topics are the source of truth; two phones edit different rules without overwriting each other.
- The engine uses the hub's clock and computes sunrise and sunset locally. If the hub clock differs from the phone's by more than five minutes, the Automations screen says so.
- An engine that meets a rule type it doesn't know skips it and lists it in state; the app says "update the helper on your hub".
- The server engine reads and writes the same topics, mirrored under `homes/<id>/zigdash/automations/…`. The app tells the executors apart only by `running_on`.

## 4. Alerts and the Recorder move onto the Engine (ticket 09)

- Node-RED is retired in 3.0. The app stops offering the Node-RED flows; `node-red/` stays one release, then goes.
- The alert and history topic contracts do not change (`zigdash/alerts/…`, `zigdash/history/…`), nor do the Alerts and History screens. Push goes out through Google's push with end-to-end encryption using Node's built-in `fetch` and `crypto`; ntfy and Pushover fallbacks unchanged.
- A Home already running the Node-RED flows: the extension stays passive for a contract while that contract's Node-RED `bridge/state` is online, and the app shows a one-time card asking the user to remove the two ZigDash flows from Node-RED, with steps. When the heartbeat goes offline the extension takes over. Nothing is removed from Node-RED automatically.
- The wall tablet recorder defers to the extension when both record.

## 5. Remote control through the relay (tickets 02, 05, 10)

**Pro only.** Not for FOSS or GitHub builds in 3.0 (a published self-host Compose file later). Not for Home Assistant homes.

**Hosting**: a separate Compose project `zigdash-relay` on `grocery-vps` (Debian 13, Docker, Caddy on 80/443): Mosquitto 2.1 with the dynamic-security plugin and a small verifier service. Hubs connect on 8883 directly (opened in ufw; Let's Encrypt certificate shared from Caddy). Phones connect over WebSocket through Caddy at `relay.zigdash.app` (DNS record at GoDaddy, set by the user). EMQX is ruled out on its licence. Pin MQTT 5 and verify "No Local", or every bridged `/set` runs twice.

**Pairing**
1. The first phone generates a home ID and a home key and sends its Play purchase token with the home ID to the verifier.
2. The verifier checks the purchase with Google (`purchases.productsv2`, product `zigdash_pro`, state purchased), binds one token to one Home, creates a dynsec role for `homes/<id>/#` and one client per device, and returns credentials. Refunds arrive by Play's real-time notifications plus a daily voided-purchases check, and revoke the Home.
3. The phone hands the hub's credentials and the home key to the extension over the LAN.
4. More phones and the wall tablet join by scanning a QR code shown by a paired phone, at home. "Phones with remote access" lists them; removing one deletes its relay client and rotates credentials.
5. A new phone away from home restores from an encrypted remote-key backup file the user saved to Google Drive.

**What the relay sees**: two modes only.
- Relay-only Homes: the extension encrypts every payload with the home key and replaces topic names with opaque ids. The server sees ciphertext, sizes and timing. It forwards only the device topics the app needs, never `bridge/definitions` (each Home carries ≥ 250 KB of retained bridge JSON).
- Server-engine Homes: plaintext by explicit choice, kept 24 hours.

**Path choice**: the app tries the home broker for 2 seconds, then the relay. A top-bar pill says "At home" or "Away via ZigDash". At home the relay is never used. Relay unreachable while away: last known values with their age and "Remote unavailable", the existing lost-connection treatment.

**Limits**: per Home 50 messages a second and 5 phones; over the limit, disconnected for a minute. The verifier accepts 10 pairing attempts an hour per IP address. Tunable after launch.

**The Pro promise**: Pro stays a one-time 7.99 EUR. The Pro screen and the policy add that remote access is included while the service operates, for fair use (one Home, up to five phones, normal household traffic), and may change or end with notice. If the relay's cost ever outgrows Pro sales, the answer is a recurring tier for new buyers only, never for existing ones. The cost now is a share of a server already paid for.

**Pro screen**: adds "Automations without a limit" and "Remote control from anywhere" to What you get. "Free forever" keeps setup, dashboards, controls, widgets, tiles, alerts, history today, the wall tablet and three automations per Home.

## 6. Account (ticket 08)

No sign-in account in 3.x. Reopen only for a feature that needs identity across devices without a shared Home, such as a multi-home installer dashboard.

## 7. Before the relay goes live (ticket 11, open)

Operating the relay makes the developer a GDPR controller. Before `relay.zigdash.app` admits a real Home:
- PRIVACY.md and README rewritten: "the developer runs no server" goes; the two relay modes, 14-day connection logs and the purchase check are described.
- The Play Data Safety form declares device IDs and purchase history; payloads qualify for the end-to-end exemption.
- A data-processing agreement with the hoster, an Art. 30 processing record, and an EU representative (the only item with a cost; price it first).

The Engine, Automations, Alerts and History on the Engine do not need any of this, since free Homes never connect to the server. They can ship before the relay.

## Suggested release split (for the roadmap)

- **3.0**: the Engine (install, consent, paused, crash safety, updates), Automations with the three-free ceiling, Alerts and History moved off Node-RED.
- **3.1**: remote control through the relay and the server engine, after ticket 11.

## Analytics to add (ADR 0006 buckets, nothing personal)

`engine_setup` with result (installed, gated_consented, gated_refused, too_old, failed) and Zigbee2MQTT minor version; `automation_saved` with trigger kind, condition count bucket and action kind; `engine_paused` with reason (silent, stopped_self). At the Oct 27 review, start recording Zigbee2MQTT version and `enable_external_js` from `bridge/info` to size the gated share.
