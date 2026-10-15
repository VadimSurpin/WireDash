# ZigDash 2.7: history graphs and Pro (build spec, in progress)

Decided with the user on 2026-10-15, round 1 of the design round: six
questions, every recommendation taken. Words follow
[CONTEXT.md](../../CONTEXT.md); new words: **History**, **Recorder**,
**Day record**, **Pro**. Research behind Pro:
[docs/growth/monetization-2026-10.md](../growth/monetization-2026-10.md)
(branch `docs/monetization-2026-10`).

**Branch:** `feat/history-2.7` (from `feat/vpn-hint`, which is 2.6.6 plus
the VPN note). **Version:** 2.7.0 when cut.

## Why

History graphs were the next roadmap item after kiosk (medium demand, the
poll's "history graphs"). Zigbee2MQTT keeps no history, and ZigDash has no
server, so something on the hub must record. 2.7 is also where the one-time
Pro unlock starts: the research found that a paid unlock of new depth
features is the fit for a free, no-ads, open-source app, and the longer
history views are new depth.

## Decisions (round 1)

1. **The app installs the recorder.** A "ZigDash history" tab in Node-RED,
   installed with one tap through Node-RED's admin API, exactly like the
   alerts flow (`lib/alerts/node_red_installer.dart`): broker host, port
   1880, `GET /settings`, `GET /flows`, `PUT /flow/:id` or `POST /flow`.
   When Node-RED asks for a login, the same fallback: the flow JSON goes to
   the clipboard with Import, paste, Deploy steps.
2. **History lives on the broker as retained day records.** Node-RED's
   context on the hub is memory-only (alerts-2.3.md), so the recorder keeps
   nothing it can't rebuild. One retained message per reading per day
   holds that day's 15-minute buckets; Mosquitto already persists retained
   messages to disk. No files, databases or add-ons on the hub, and the
   phone records nothing.
3. **Every reading tile is recorded, automatically.** The app sends the
   recorder the list of numeric readings shown by reading tiles (and their
   gauge style) on the Home's dashboards, at most 50. Adding or removing a
   tile updates the list. No per-tile switch.
4. **Views: 24 hours, 7 days, 30 days. Kept for 30 days.** At midnight
   (the Home's time zone) the recorder clears the day that fell out of the
   window.
5. **Where history shows.** A tap on a reading tile opens its history
   sheet; the device page shows the same graph for each recorded reading.
   Kiosk guests can open the sheet: it is read-only. (Reading tiles have no
   tap action today, only long-press for Panel options, so the tap is new.)
6. **Pro, option B.** The 24-hour view is free. The 7-day and 30-day views
   are in **Pro**, a one-time in-app purchase through Google Play, about 7
   to 9 EUR. Builds outside Play (GitHub, IzzyOnDroid, F-Droid) have no
   billing library and everything unlocked. If the Google Play payments
   profile is not ready when 2.7 ships, the Pro views stay hidden and a
   2.7.x turns them on: nobody ever loses something they had for free.
   Nothing that exists in 2.6 moves behind Pro.

## Technical defaults (not yet put to the user; change on request)

### Topics and payloads

- **Config, app to recorder:** `zigdash/history/config`, retained, QoS 1,
  one per Home, last writer wins (like `zigdash/alerts/config`):
  `{"v":1, "home":"…", "base":"zigbee2mqtt", "timeZone":"Europe/Berlin",
  "keepDays":30, "readings":[{"key":"<ieee>.<attribute>",
  "topic":"zigbee2mqtt/<friendly name>", "path":"temperature",
  "unit":"°C"}]}`. Empty payload stops recording (records stay until they
  age out).
- **Day record, recorder to app:**
  `zigdash/history/<ieee>/<attribute>/<YYYY-MM-DD>`, retained, QoS 1:
  `{"v":1, "unit":"°C", "b":[[slot, avg, min, max], …]}` where `slot` is
  the 15-minute slot of the day (0 to 95). Only slots with data appear, so
  gaps stay gaps. About 3 KB a day per reading; 50 readings for 30 days is
  about 4.5 MB on the broker.
- **Heartbeat:** `zigdash/history/bridge/state`, `online` on start and every
  30 seconds, retained, Last Will `offline` (same as alerts).
- Keys use the IEEE address, not the friendly name, so a renamed device
  keeps its history.

### Recorder behaviour

- Subscribes to `<base>/#`, picks the configured readings, and folds each
  value into the current 15-minute bucket (count, sum, min, max).
- When a bucket closes it republishes that day's record. On start it reads
  today's retained record back first, so a restart loses at most the open
  bucket.
- At local midnight it starts a new day and publishes an empty retained
  payload to each configured reading's record from `keepDays` + 1 days ago.
- Built from JS sources with a test harness, like `node-red/alerts/`.

### App

- Reads only what a view needs: 1 record for 24 hours (plus yesterday for
  the part before midnight), 7 for a week, 30 for a month, by subscribing
  to those topics and unsubscribing when the sheet closes.
- Draws with a `CustomPainter`, like the gauge: no chart dependency.
- Shows "Recording since …" when there is less data than the view, and a
  setup card (install the recorder) when the heartbeat is missing.

### Pro

- Android product flavors: `play` (Play Billing through the official
  `in_app_purchase` plugin, one non-consumable product `zigdash_pro`) and
  `foss` (no billing code, Pro always on). `tool/build_release.sh github`
  builds `foss`; `bundle` builds `play`.
- One provider decides: `proProvider` (unlocked, locked, unavailable).
  Purchases restore through Play on a new device; nothing is stored by
  ZigDash beyond Play's own receipt.
- No ads, no nag: Pro is mentioned only on the locked views and in
  Settings › About.

## Open: round 2

To decide with the user next: the name and price of Pro, what a locked
view shows, the graph's look, and whether Pro gets a supporter extra.
