# Setup help: a scan that says what it found (2.5)

Decided 2026-10-12 in a five-question round; the user took every
recommendation. Words follow [CONTEXT.md](../../CONTEXT.md) (**First run**,
**Platform answer**, **Hub found**, **Get help**).

## Why

Aptabase, 2026-10-11 to 12: every new install that opted in (Italy, Russia,
Brazil) ran setup, got "No connection found" after the 30-second scan, and
left within a minute, either from the help page or from the manual form.
None finished. A Polish user with an existing Home used the app for six
minutes, so the app works once a Home exists. The leak is the empty scan.

The scan only probed MQTT ports, so "no broker reachable" and "no hub on this
network" looked the same, and the result screen had to cover every setup at
once. Most Zigbee2MQTT users run Home Assistant, and the usual failure is a
broker that isn't listening on the network. Knowing what is there turns the
vaguest screen in the app into one instruction.

## Decisions

1. **The question lives on the scanning screen, skippable.** "While we
   look: where does Zigbee2MQTT run?" with four chips: Home Assistant,
   SMLIGHT hub, Raspberry Pi or Docker, Not sure. Not answering and Not sure
   both mean today's scan. If the broker turns up before the user taps, setup
   goes straight to review as before. The answer is kept for the session, so
   the empty result and Try again keep it, and the empty result shows the
   chips too for whoever skipped them.
2. **Hub probes have a budget.** Probing every port across the whole /22
   would double the scan, so the hub pass runs on the phone's /24 only, and
   only after the /24 broker pass came up empty, before the /22 broker pass.
   Home Assistant (8123) and the Zigbee2MQTT frontend (8080) are looked for
   on every scan; an SMLIGHT hub (its web UI on port 80) only when the user
   said so, because port 80 answers on too many printers and routers. A hit
   is a page that names itself ("Home Assistant", "Zigbee2MQTT", "SLZB" or
   "SMLIGHT"); an open port alone is nothing. HTTPS is tried when plain HTTP
   fails (Home Assistant with SSL on). A hub hit never counts as a broker and
   never stops the widening.
3. **The empty result says what it found.** With a hub: "Found Home
   Assistant, but no MQTT broker" and the add-on steps; "Found Zigbee2MQTT,
   but its broker can't be reached" and the Mosquitto listener fix; "Found
   your SMLIGHT hub, but MQTT is off" and Settings › MQTT › Allow External.
   The first action is "Connect to <address>", which opens manual entry with
   the host and port 1883 filled in. Home Assistant wins when several hubs
   answered (it hosts the broker), then the frontend, then SMLIGHT. Without a
   hub, the text and the one guide for the platform the user picked, or
   today's three guides for Not sure. Try again, Get help, manual entry and
   the demo stay.
4. **Progress, and a manual form that can be answered.** A determinate bar
   with "Checked 400 of 1526 addresses" replaces the bare spinner. The manual
   form starts with an empty host instead of "localhost", says what the phone's
   own address is ("Your phone is 192.168.1.37, so the hub is usually
   192.168.1.…"), tells Home Assistant users the host is the address they
   open Home Assistant with, and links Get help from the form itself, not
   only after a failed check (`manual_form`).
5. **Measured, and a release of its own.** The `scan_empty` step now carries
   the platform answer, the hub kind found (or none), the hosts tried as a
   bucket, whether the scan widened, and the shape of the phone's subnet
   (192.168, 10, 172.16, other). Kinds and buckets only; never an address.
   The platform answer also tags scan found, review and complete, so the
   install base shows up in a week. New strings in 11 languages and a visible
   change make this 2.5.0; history graphs move to 2.6 and kiosk to 2.7. The
   "no local network" case (scan failed) is untouched until the Sardinia
   user's reply says whether it is a detection bug on that phone.

## Behaviour

- Scan phases: A probes the /24 for brokers (1883, 8883). If none answered,
  B probes the /24 for hubs and C the rest of the /22 for brokers. A broker
  in A ends the scan as before, with no hub probes at all. The SMLIGHT pass
  added mid-scan runs next, ahead of what is left of C; added after the scan
  it waits for Try again.
- The progress total counts every pass up front, so the bar never moves
  backwards; a scan that ends early just stops.
- Support details' last-scan line is unchanged (hosts tried, widened,
  brokers found, interface kind).
- Login step (2.6.1): the prompt says it wants the MQTT login, not the hub's
  web password, and where that login comes from: one line for the platform
  the user named (Home Assistant user for the Mosquitto add-on, Mosquitto's
  password file on a Pi or Docker, Settings › MQTT on an SMLIGHT hub), all
  three when they didn't answer. The `needs_login` and `login_rejected`
  steps carry the platform answer like the others. Reason: a user who hit
  the prompt left it in six seconds, twice; the fix was one tap away in Get
  help, which they never opened.

- Address check (2.6.2): the empty result without a hub asks for the
  address the user already knows ("Where do you open Home Assistant?",
  or the hub's / Mosquitto machine's address by the platform answer, or
  either for Not sure) and checks that one machine: a name is resolved to
  an IPv4 address (names like `homeassistant.local` often fail on Android,
  and the message says to use the IP instead), a public address is refused
  (a Nabu Casa or DuckDNS link is not the home network), then ports 1883
  and 8883 are probed for a broker and 8123, 8080 and 80 (or the port the
  user typed) for a hub page, at the same time. A broker goes straight to
  verification and the login step; a hub page without one becomes the
  "found X, but no broker" result with its Connect to button; nothing,
  not resolved and not local are said on the field. Try again clears the
  check; the chips keep it. The typed address never leaves the phone.
  Reason: five of a week's nine new users were lost at an empty scan with
  no hub found, three of them after answering Home Assistant; the scanner
  guesses subnets, the user knows the address.
- Scan diagnostics (2.6.2): the `scan_empty` step also carries how many
  probed hosts answered at all (a TCP connect that succeeded or was
  refused; a timeout is silence) as a bucket (0, 1-5, 6-20, 21+), whether a
  VPN interface was up, and the kind of network (Wi-Fi, Ethernet, other),
  so "nothing on this /24" can be told from "an isolated or wrong network".
  The `address` step carries only its outcome (broker, hub, nothing,
  not_resolved, not_local, invalid).

- Counted once (2.6.3): a chip tap on the empty result re-emits the state
  with the answer but no longer re-sends `scan_empty`; the answer rides on
  the steps after it (scan found, needs login, review, complete) and on the
  next empty result after Try again. Reason: the first 2.6.2 session sent
  the diagnostics three times for one scan, once per chip tap.

## Code

- `lib/features/connections/discovery/hub_probe.dart`: `HubKind`,
  `hubPorts`, `hubKindOfPage`, `HubFound`, `HubProber`, the `ScanEvent`s
  (`BrokerFound`, `HubSeen`, `ScanProgress`, `ScanTriedEvent`).
- `hub_prober_io.dart` / `hub_prober_stub.dart` / `hub_prober.dart`: the
  HTTP identification and the web stub.
- `broker_scan_service.dart`: `ScanRun`, `run()` with phases A, B, C and
  `addHub`; `scan()` stays brokers-only for the manual form's sheet.
- `lib/features/onboarding/setup/setup_coordinator.dart`: `SetupPlatform`,
  `hubsForPlatform`, `setPlatform`, the richer `SetupScanning` and
  `SetupScanEmpty` (with `hub`).
- `setup_analytics.dart`: `setupStepFor(..., platform:)`, `subnetShape`;
  `analytics_events.dart`: the new `SetupStep` fields, `HelpFrom.manualForm`.
- `setup_screen.dart`: `_PlatformChips`, the progress bar, hubs seen, the
  hub-aware `_ScanEmpty`, `_SetupGuides(only:)`, `Routes.guidedConnectTo`.
- `guided_connect_screen.dart`: `initialHost`, `initialPort`, `_HostHints`.
- Strings: `setupPlatform*`, `setupScanProgress`, `setupScanHint*`,
  `setupHubSeen*`, `setupNoBroker*`, `setupConnectTo`, `setupNotFound*`,
  `guidedHostYourPhone`, `guidedHostHa`, 11 ARBs.
- Tests: `test/connections/broker_discovery_test.dart` (run, hubs, progress),
  `setup_coordinator_test.dart`, `setup_screen_test.dart`,
  `guided_connect_screen_test.dart`, `analytics_ui_test.dart`; goldens
  `first_run_scanning` and `first_run_hub_no_broker`.
- 2.6.2: `address_check.dart` (`AddressOutcome`, `AddressCheckResult`,
  `AddressChecker`, `hostFromAddressInput`), `address_checker_io.dart` /
  `_stub.dart` / `address_checker.dart` (`createAddressChecker`);
  `HostProber.probeHost` and `SocketMqttProber.isConnectionRefused`
  (alive hosts), `ScanTriedEvent.aliveHosts`, `ScanStats.aliveHosts`;
  `network_info_io.dart` `vpnActive` / `hasVpnInterface`; the
  coordinator's `checkAddress`, `AddressCheckStatus`, `NetworkFacts`,
  `SetupScanEmpty.address` / `.network`; `SetupStepKind.address` and the
  `alive`, `vpn`, `net`, `result` properties; `_AddressField` on the
  screen; strings `setupAddress*`, 11 ARBs. Tests:
  `test/connections/address_check_test.dart` plus the files above; golden
  `first_run_nothing_found` shows the field.
