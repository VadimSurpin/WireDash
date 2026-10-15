# ZigDash history recorder (2.7)

The "ZigDash history" Node-RED tab. ZigDash installs it on the hub through
Node-RED's admin API, like the alerts flow; see
[docs/design/history-2.7.md](../../docs/design/history-2.7.md).

- `ingest.js` reads the retained `zigdash/history/config` (the readings to record).
- `record.js` folds device values into today's 15-minute slots.
- `tick.js` (every minute) publishes each reading's retained day record when
  a slot closes, the full day after midnight, and clears records past
  `keepDays`.
- `restore.js` reads today's records back after a restart (the hub's
  Node-RED context is memory-only).

Build the flow JSON and run the checks:

```
node node-red/history/build.mjs
node node-red/history/test/harness.mjs
```
