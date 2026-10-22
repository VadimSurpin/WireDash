# Live relay check (3.1)

Runs the built Engine against a real Mosquitto 2.1 with the dynamic-security
plugin, with a simulated phone and a second home's phone. Local only, no TLS.

1. Start a broker: `mosquitto_ctrl dynsec init <dir>/dynsec.json admin <pw>`, then
   `mosquitto -c <dir>/mosquitto.conf -d` with `listener 18883 127.0.0.1`,
   `allow_anonymous false` and the plugin pointing at that file.
2. For homes h1 and h2: a role `home-<h>` allowing publishClientSend,
   publishClientReceive, subscribePattern and unsubscribePattern on
   `homes/<h>/#`, and clients `hub-<h>` and `phone-<h>` with that role. Put each
   client's password in `<dir>/<client>.pw` (the script reads `../broker/`).
3. In a folder with `mqtt@5` installed: `node relay-live.js <repo>/hub/zigdash-engine.js`.

Verified 2026-10-22 on Mosquitto 2.1.2 and mqtt 5.16.1: all ten checks pass.
