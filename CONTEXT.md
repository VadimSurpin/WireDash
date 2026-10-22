# ZigDash — domain glossary

**Broker** — the user's MQTT server (e.g. Mosquitto on a Pi or SMLIGHT hub). ZigDash stores one **Connection** per broker: address, protocol, credentials.

**Home** — what users call a connection in everyday UI. The app shows one home at a time and switches between homes in the header. The word "broker" appears only in setup and connection settings; code says `Connection`.

**Zigbee2MQTT bridge** — the Zigbee2MQTT instance publishing under a base topic (default `zigbee2mqtt`) on a broker. A broker can be reachable while no bridge publishes on it.

**Device** — a Zigbee device the bridge reports in `bridge/devices`. Devices exist independently of dashboards.

**Dashboard** — a named, user-arranged screen of tiles belonging to one home; the primary object users work with. Rooms are not a concept: a user who wants rooms names dashboards after them. The app opens on the last-used dashboard.

**Panel** — one control or readout on a dashboard, bound to MQTT topics (code term). Users see it as a **tile**; "panel" does not appear in UI copy.

**Device tile** — one tile representing a whole device of a known class (color light, light, switch/plug, cover, climate sensor, contact, motion, leak/smoke), stored as one panel of type `device` bound to the device's IEEE address. Tap the icon for the quick action, the body for full controls, long-press to edit. Unknown classes get a generic device tile.

**Reading tile** — a tile showing one numeric value with its unit (temperature, humidity, power), shown as a **value** (large number) or as a **gauge** (a half arc from a min to a max, with up to three **colour bands**: Normal, Good or Attention). "Gauge" is a style of the Reading tile, not a tile type.

**Custom MQTT tile** — any of the raw panel types (toggle, slider, multi-state, text log…) configured by topic and payload rather than from a device. The expert path.

**Unassigned device** — a device reported by the bridge that is on no dashboard in its home. Surfaced as a prompt, never added automatically.

**Tile size** — how much of a dashboard row a tile takes: **Small** (one grid column), **Wide** (two columns) or **Full** (the whole row). Columns are 2 on phones, 3 on medium windows, 4 on tablets, so a Small tile stays small on a tablet. Code: `PanelWidth` small/wide/full from 1.12 (before that full/half/third; half and third migrate to Small).

**Scene** — a saved set of device commands the app sends with one tap (lights, plugs, shutter positions). ZigDash's own: captured in the app, stored on the phone. Runs from the Scenes tab, a **scene tile**, a home-screen scene widget or a group widget.

**Built-in scene** — a scene every Home has without creating it: **Close all shutters**, **Open all shutters**, **Stop all shutters**. Holds no device list; when run it commands every **shutter** (Zigbee2MQTT cover) the bridge reports, minus the ones unticked under **Which shutters…** (stored per Home by address). Listed first in the Scenes tab under "All shutters"; cannot be edited or deleted. Code: `all_shutters.dart`, ids `all_shutters:<close|open|stop>`.

**Section** — a titled group of tiles inside a dashboard (e.g. Lights, Sensors). Generated dashboards are sectioned by device type. Tiles with no section render first, without a header; dashboards from before 1.12 start that way.

**Device link** — the IEEE address a tile carries (`panels.deviceIeee`): always on device and reading tiles, optional on custom MQTT tiles. It decides whether a device is on a dashboard.

**Not responding** — a device tile's state when the device ignored its state request (`/get`) for 15 seconds after connecting. Zigbee2MQTT availability is off by default, so this is often the only sign a device has dropped off the Zigbee network. The tile still sends commands.

**Device page** — the page for one device, reached from the Devices tab, a device tile's sheet or Edit mode: full controls, readings, health, and the dashboards it is on. Routed by IEEE address, so it follows renames. From 1.13.

**Needs attention** — a device whose battery is low, which availability reports offline (only when the bridge has availability turned on), which is not responding, or whose interview failed or is unsupported. Weak link quality is shown but does not count.

**Last heard** — when the app last received a state message from a device, taken from the last-known store. Used instead of Zigbee2MQTT's `last_seen`, which is off by default.

**Edit mode** — the one mode in which a dashboard is rearranged: tiles show a grip and an edit badge, controls are inert, and changes save as they happen.

**Edit lock** — a dashboard's own switch (in its form) that hides Edit for it: no edit button, no long-press on tiles. Protects a finished dashboard from stray edits; not a guest lock. Code: `dashboards.locked`.

**Wall display** — a dashboard's settings for a tablet on the wall, in its ⋮ menu: keep the screen on and hide the bars (they return with a touch and hide again after 10 seconds), **Fullscreen** (Android's bars hide too), **Dim after** a chosen number of minutes without a touch, and the Kiosk lock. Stored on this device per dashboard. From 2.0; the lock, Fullscreen and Dim from 2.6.

**Kiosk lock** — the Wall display option that pins one dashboard's Home on screen for guests: only that Home's dashboards and their tiles and device sheets stay reachable, every other address goes back, and the system back does nothing. Left by a long-press on the title, which asks for the **kiosk PIN** when one is set (four digits, one per device, no bypass: a forgotten PIN means clearing the app's data). **Android screen pinning** is an optional extra that also blocks Home and recent apps; it is not the lock, because a tablet without a lock screen unpins with a gesture. Code: `KioskState`, `kioskRedirect`.

**Generated dashboard** — a dashboard created from discovered devices during setup, then editable like any other.

**First run** — from install until the user has a home or has chosen the demo. During first run the app shows only setup (and its manual entry and help). It ends when setup, manual entry or the connection form saves a real home, or when the user tries the demo. Code: `needsOnboarding` / `FirstRun`.

**Platform answer** — what the user says when setup asks where Zigbee2MQTT runs: Home Assistant, an SMLIGHT hub, a Raspberry Pi or Docker, or not sure. Asked while the scan runs and on its empty result, never required. It shapes what the scan looks for and what the empty result says, and is kept for the setup session only.

**Hub found** — a machine the scan recognised by its web page while looking for a broker: Home Assistant, the Zigbee2MQTT frontend, or an SMLIGHT hub. Not a broker: the empty result names it and says what is missing on it.

**Address check** — on an empty result, the address the user types for their hub (an IP, a name, or the link from their browser), which setup checks for a broker and a hub page on that one machine. Offered whenever no hub was found, worded by the platform answer. The address stays on the phone; only the outcome is counted.

**Demo mode** — a sample connection and dashboard with no real broker, marked as demo on screen and removed when real setup completes.

**Last-known value** — a tile's most recent received value, kept on the phone across restarts, shown when the value is not fresh (broker unreachable, or not yet reported since connecting) and marked stale with its age. Never leaves the device, not even in Android backups.

**Successful session** — a calendar day on which the user sent a command and received a confirming state update. Counted locally for the rating prompt; nothing leaves the device.

**Support request** — a user asking the developer for help, in writing (email or GitHub), in English or Hebrew. A call is offered only by the developer when writing hasn't solved it; users can't book one unprompted. Not a chat: there is no live channel.

**Support details** — the snapshot added to a Support request or a Report a problem: app version, phone model, where Get help was opened from, the kind of connection, the Zigbee2MQTT version and device count, the kind of the last connection error and what the last hub scan tried. Always in English. Never passwords, addresses, usernames, home names or device names. The user sees it before sending, and it leaves the phone only when they send or paste it themselves.

**Get help** — the one screen every help link opens. It knows where the user came from (a setup failure, an unreachable home, a missing device list, Settings, the demo) and shows the tips for that place first, then a way to send a Support request. Different from **Report a problem**, which reports a bug to fix.

**Shortcut** — a way to control one device from outside the app: a home-screen **widget**, a Quick Settings **tile**, or an Android Device **control**. Each is tied to one device in one Home, chosen when it is added, and keeps working when another Home is open in the app. After a tap it shows "working…" until the device confirms its new state (or, after 5 seconds, that it wasn't confirmed). Between taps it shows the Last-known value with its age; it never refreshes in the background.

**Automation** — a rule the user sets so the home acts on its own: when a **trigger** happens (a device changes: motion, a door, a button, a reading past a value; or a time comes: a clock time, sunrise or sunset, on chosen days) and its **conditions** hold (within set hours; another device in a given state), an **action** runs: a **Scene**, one device command, or the same turned off again after a set number of minutes. Acts; never tells: telling is an **Alert**. For Zigbee2MQTT homes without Home Assistant; a home with Home Assistant automates there. Three per Home free, unlimited with Pro. From 3.0.

**Engine** — what runs a Home's Automations, Alerts and Recorder while phones are away. Normally on the hub, inside Zigbee2MQTT, installed by the app; for a Pro Home whose hub cannot run it, on ZigDash's server, with the Home's device states sent there in the clear by choice. A free Home never uses the server. Rules run with the internet down wherever the hub runs them. From 3.0.

**Automations paused** — the state when the Engine has not reported in for over a minute, or stopped itself after repeated crashes: no Automation can run, rules stay editable, and the app says so on the Automations screen and the dashboard. Same pattern as **Alerts paused**. From 3.0.

**Alert** — something the user asked to be told about when it happens at home: a leak, smoke, a door or window opening (optionally only within set hours), or a low battery, for chosen devices in one Home. The hub's Node-RED watches for it; the phone does not. Not a schedule: alerts tell, schedules act. Code: `AlertRule` in the config sent to the hub; UI only says "alert".

**Notification** — what reaches the phone when an alert fires: a ZigDash notification, delivered through Google's push service (encrypted end to end) so it arrives with ZigDash closed; or an ntfy notification for phones without Google services and for people sharing a Home's alerts without ZigDash. Leak and smoke also notify when they clear.

**Recent alerts** — the last 20 alerts that fired, kept on the hub, shown at the top of the Alerts screen so a missed notification is still seen.

**Alerts paused** — the state when the hub's alert flow has not reported in for over a minute (Node-RED stopped or not installed): no alert can fire, and the app says so on the Alerts screen and the dashboard.

**History** — the recorded values of a reading tile over time, drawn as a graph in its history sheet and on the device page. Views: 24 hours (free), 7 and 30 days (Pro). From 2.7.

**Recorder** — the "ZigDash history" Node-RED flow on the hub that records every reading tile's values into day records. Installed by the app like the alerts flow. From 2.7.

**Day record** — one retained MQTT message per reading per day on the user's broker, holding that day's 15-minute averages, minimums and maximums. Kept 30 days.

**Pro** — the one-time in-app purchase on Google Play that unlocks depth features, starting with the 7- and 30-day history views. Builds outside Play have everything unlocked. Nothing that was free moves into Pro.
