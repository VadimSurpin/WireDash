# ZigDash Engine

`zigdash-engine.js` runs a Home's Automations inside Zigbee2MQTT (2.4 or newer) on the hub. The ZigDash app installs it as a Zigbee2MQTT external extension; it is not meant to be copied by hand. Contract and behaviour: [docs/design/zigdash-3.0.md](../docs/design/zigdash-3.0.md).

Tests (Node 20+, no dependencies):

    node --test hub/test/engine.test.js

Verified live on 2026-10-22 against Zigbee2MQTT 2.8.0: installed over the frontend WebSocket with no restart, loaded rules from retained `zigdash/automations/rules/<id>`, reported an unknown rule, fired a clock rule on its minute in Asia/Jerusalem, removed cleanly.
