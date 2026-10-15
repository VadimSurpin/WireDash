# ZigDash 2.7: history graphs and Pro (build spec, in progress)

Decided with the user on 2026-10-15 in two question rounds (ten
questions), every recommendation taken. Words follow
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
3. **Every number the dashboards show is recorded, automatically.** The
   app sends the recorder the list of numeric readings on the Home's
   dashboards, at most 50. Adding or removing a tile updates the list. No
   per-tile switch. First-run setup makes device tiles, not reading tiles,
   so "reading tile" here means both: a reading tile's value, and the
   numbers a device tile shows (a climate sensor's temperature and
   humidity, any other device's first reading, such as a plug's power).
   Clarified while building, 2026-10-15.
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
  "keepDays":30, "readings":[{"ieee":"0x…", "attr":"temperature",
  "topic":"zigbee2mqtt/<friendly name>", "path":"temperature",
  "unit":"°C"}]}`. `path` may be dotted for nested values; `attr` is the
  path with anything but letters, digits, `_` and `-` replaced by `_`. Empty payload stops recording (records stay until they
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

## Decisions (round 2, 2026-10-15, every recommendation taken)

7. **ZigDash Pro, 7.99 EUR,** Google converting per country. Just under
   IoT MQTT Panel Pro (£8.49) and Fully Kiosk PLUS (8.90 EUR).
8. **A locked view shows a blurred sample graph** (made-up data, never the
   user's), one line ("Longer history is part of ZigDash Pro, a one-time
   purchase") and an Unlock button. No watermark over real data, no lock-only
   tab.
9. **The graph:** a line of the 15-minute averages over a shaded band from
   minimum to maximum, in the Signal amber; touching it shows the time and
   value under the finger; the current value is large above it, like the
   tile.
10. **No supporter extras in 2.7.** Pro carries history only; extras (icon,
    accent) may come with wall-tablet depth in 2.8.

## Build order

1. Recorder flow: JS sources, build script, test harness, bundled JSON.
2. Installer: generalise `NodeRedInstaller` to install a named tab from a
   bundled asset; history uses it.
3. Config: the reading list from the Home's dashboards, published retained.
4. Reading side: day-record parsing, providers per view, gaps.
5. History sheet and the graph painter; tap on reading tiles; device page.
6. Pro: flavors, `proProvider`, Play Billing in `play`, the locked view.
7. Strings in 11 languages, privacy policy (the recorder sends nothing off
   the broker; Play receives the purchase), store text, goldens.

## Status (2026-10-15, end of day)

Steps 1 to 7 are built on `feat/history-2.7` with tests (826 passing) and
goldens. Added while building: usage events `feature_used` history,
`history_setup` and `pro` (privacy policy lists them); the light theme's
line is darkened toward the ink for contrast.

Left before the cut:
- A run on the real hub: install the recorder on the SMHUB, watch day
  records arrive, open the sheet on the phone. Needs the user's go to
  install the flow there.
- Pro goes live only after the Play payments profile exists and the
  product `zigdash_pro` (7.99 EUR) is created; then build with
  `ZIGDASH_PRO_LIVE=1`.
- The user's OK on the new privacy policy sections and the store text.

