# History without Node-RED (2.9.1)

Decided 2026-10-17 in one round; the user took every recommendation. Builds
on [history-2.7.md](history-2.7.md).

## Why

History needs a recorder, and until now the only recorder was a Node-RED
flow on the hub. Many Zigbee2MQTT homes have no Node-RED: the only 2.8.1
user who connected (UK, 2026-10-16) tapped Set up twice and got "no
Node-RED found". History is also part of Pro (7 and 30 days), so it should
work for everyone who can buy it.

## Decisions

1. **ZigDash records itself, on one device the user picks**, typically a
   wall tablet that stays open. It writes exactly what the Node-RED flow
   writes: the `zigdash/history/bridge/state` heartbeat (`online`,
   retained) and one retained day record per reading per day,
   `[slot, avg, min, max]` per 15-minute slot, kept 30 days. Every phone of
   the Home reads it as before. The better "no Node-RED" message stays
   (it already names SMLIGHT's Apps › Node-RED).
2. **Only the chosen device records.** "Record history on this device" is
   a per-device switch, offered on the history setup card, in the "no
   Node-RED" dialog and in the Wall display sheet. If Node-RED records too,
   both see the same broker messages and write the same records, so no
   coordination is needed.
3. **Gaps are honest.** While the recording device is off or ZigDash is
   closed, nothing is recorded and the graph shows the gap.
4. **Free and Pro unchanged:** 24 hours free, 7 and 30 days Pro; recording
   itself is free whoever records.

Technical default (not put to the user): ZigDash records only while it is
open on screen. Background recording would need a permanent Android
notification and battery exemptions; a wall tablet is open all day anyway.

## Code

- `lib/features/history/app_recorder.dart`: `HistoryFolder`, a pure port
  of the flow's "record", "restore today" and "tick" nodes (slots of count,
  sum, min, max; closed slots published each minute; a finished day
  published whole; records past 30 days cleared, a week of dates).
- `lib/features/history/app_history_recorder.dart`:
  `HistoryRecordHereSetting` (`history_record_here_<connectionId>`), and
  `AppHistoryRecorder`, mounted next to `HistorySync` on the dashboards
  screen: heartbeat, today's records restored, the readings of the retained
  config subscribed, a tick a minute.
- `history_sheet.dart`: Record on this device on the set-up card and in the
  no-Node-RED dialog; `history_setup` result `this_device`.
- `wall_display_sheet.dart`: the switch.
- Tests: `app_recorder_test.dart`, `app_history_recorder_test.dart` (an
  in-memory broker), `history_sheet_test.dart`.
