# ZigDash — Privacy Policy

**Effective date:** the day ZigDash 2.6 is published (replaces the policy published with ZigDash 2.5)

ZigDash ("the app") is a client for controlling [Zigbee2MQTT](https://www.zigbee2mqtt.io/)
devices through MQTT brokers that **you** configure. This policy explains what
the app does and does not do with your data.

## Summary

ZigDash does **not** collect or share personal data. Your broker settings,
passwords, devices, topics and their values stay on your device. There is no
advertising and no user account, and the developer runs no server of their own.

Unless you **opt out**, ZigDash sends a short list of **anonymous usage
events** (which setup steps fail, which features get used) to Aptabase, an
analytics service hosted in the EU. New installs see the choice on the first
setup screen before anything is sent, and you can turn it off at any time. See
[Anonymous usage data](#anonymous-usage-data).

## Data stored on your device

All data stays on your device:

- **Connection settings** — the MQTT broker host, port, protocol, and optional
  username you enter.
- **Passwords** — any broker password you enter is stored in the operating
  system's secure storage (Android Keystore / iOS Keychain), not in plain text.
- **Dashboards and panels** — your dashboard layouts and panel configuration are
  stored in a local on-device database.
- **App preferences** — theme, Material You setting, and language.
- **Support details** — the kind of the last connection error and what the
  last hub scan tried (how many addresses, how many brokers found, Wi-Fi or
  Ethernet), kept only until the next successful connection. No addresses or
  names. They leave your device only if you send or copy them yourself from
  Get help or Report a problem. They are not included in Android backups.

- **Alerts** — your alerts for each Home, the push keys and this phone's
  push address, kept in the app's own storage and, as described under
  Alerts below, as a retained message on your own broker. Not in Android
  backups.
- **Shortcuts** — which device each Quick Settings tile controls, which
  device, scene or group each home-screen widget shows, the devices and
  scenes offered to Android's Device Controls and to the widget pickers, and
  the last state each shortcut showed, kept in the app's own storage so the
  tiles, widgets and controls can show them. Android's Quick Settings, home
  screen and Device Controls display these names and states on your phone
  (including, if you allow it in Android's settings, on the lock screen);
  they are not sent anywhere.

This data is never uploaded to the developer. You can remove it at any time by
deleting a connection (which removes its dashboards, panels, and saved password)
or by uninstalling the app.

## Network communication

ZigDash communicates **only** with the MQTT broker(s) you configure, using the
address and credentials you provide. MQTT messages flow directly between your
device and your broker. The developer neither operates an intermediary server
nor receives any of this traffic.

The app requests the **INTERNET** permission to connect to your broker and,
unless you opt out, to send the anonymous usage events described below. On
Android 17 it also asks for the **local network** permission, which Android
requires for talking to a hub on your home network.

## Alerts

Alerts are off until you set them up for a Home (Settings › Home › Alerts).
When you do:

- **Your hub does the watching.** ZigDash writes your alerts (which devices,
  which conditions, the hours) as a retained message on your own broker, and
  installs a small flow in Node-RED on your hub, which watches the devices.
  ZigDash itself never watches in the background and runs no server.
- **Notifications reach your phone through Google's push service.** Each one
  is encrypted end to end on your hub (Web Push, RFC 8291) with keys that
  exist only on your phone and your broker, so Google carries the message but
  cannot read it. Google does see that a push was sent to your phone, and
  when. Your phone's push address and the encryption keys are stored in the
  same retained message on your broker, so every phone of the household can
  receive the Home's alerts.
- **Sharing alerts (optional)** sends the alert text (the kind, the device's
  name and the Home's name) to the ntfy server you choose (ntfy.sh unless you
  pick your own) **unencrypted**, for people who follow the Home's link in the
  ntfy app. **Pushover (optional)** sends the same text to Pushover, with the
  Pushover keys you enter, which are kept in the retained message on your
  broker. "Hide device names" leaves the names out on both paths.
- **Recent alerts** (the last 20) are kept retained on your broker by the hub,
  not by any server of ours.

## Anonymous usage data

**On unless you opt out.** New installs see the choice once, as a ticked box
on the first setup screen; untick it to say no. Nothing is sent before you move
past that screen. People who installed an earlier version are asked once, on
their dashboard, and nothing is sent until they answer. You can change your
answer in **Settings › About › Share anonymous usage data**. Turning it off
deletes any events not yet sent and stops sending immediately. Builds without
an analytics key (for example F-Droid builds, or one you build yourself) send
nothing at all.

**Where it goes.** [Aptabase](https://aptabase.com/legal/privacy), EU region.
Data stays in the EU and is kept for up to 5 years.

**What is sent with every event:** the operating system name and version, your
phone's language setting, the ZigDash version and build number, whether it is a
debug build, and a random session ID that changes after an hour of inactivity.
No device ID, advertising ID, account, or install ID is sent. Aptabase's
server sees your IP address in order to receive the event; according to
Aptabase it does not store it, and only uses it with a salt that changes daily,
so visits cannot be linked across days.

**The events.** Every value is chosen from a fixed list in the app's code,
never from anything you typed or anything your broker sent.

| Event | When | Values |
|---|---|---|
| `app_started` | Once each time the app starts | phone or tablet; theme (system, light, dark); Material You on or off; number of homes (0, 1, 2+); number of tiles (0, 1–10, 11–30, 31+); demo or not |
| `setup_step` | Each step of first-run setup | the step (started, scan found, scan empty, needs login, login rejected, failed, review, complete, manual, demo); the type of setup error, if any; number of devices found (0, 1–5, 6–20, 21+); from 2.5, your answer to where Zigbee2MQTT runs, if you gave one (Home Assistant, SMLIGHT hub, Raspberry Pi or Docker, not sure); and for an empty scan, the kind of hub it saw instead (Home Assistant, Zigbee2MQTT frontend, SMLIGHT hub, or none), how many addresses it tried (0, 1–253, 254–1020, 1021+), whether it widened to the surrounding network, and which private range your phone is in (192.168, 10, 172.16, other); from 2.6.2, also how many addresses answered at all (0, 1–5, 6–20, 21+), whether a VPN was on, and the kind of network (Wi-Fi, Ethernet, other); and for the address check (the address you type on the empty result), only its outcome: a broker found, a hub page found, nothing answered, the name could not be looked up, not a home address, or nothing typed |
| `feature_used` | The first use of a feature in a session | Devices tab, device page, Scenes, Edit mode, Wall display, tile added (with the kind of tile, such as "light" or "toggle"), or kiosk (with whether a PIN is set, whether Android screen pinning is on, and the dim delay as one of off, 1, 5 or 15 minutes) |
| `help_opened` | Get help was opened | where from: no connection found, a setup error, manual connect, home can't be reached, device list missing, Settings, or the demo |
| `support_contact` | A support request was started from Get help | where from (as above); email or copy |
| `community_opened` | The Telegram community link was opened | where from: Settings, the one-time dashboard card, or the place Get help was opened from (as above) |
| `shortcut_added` | A Quick Settings tile was given a device, a home-screen widget was added, or ZigDash's Device Controls were first shown | tile, control, widget, scene widget or group widget |
| `shortcut_used` | A tile, widget or Device Control was used (sent at most once per kind when the app next starts) | tile, control, widget, scene widget or group widget |
| `poll_answer` | The one-time "What should ZigDash do next?" card was answered | notifications, history graphs, kiosk mode or Zigbee groups |
| `alerts_setup` | A step of setting alerts up | the step (flow installed, flow installed by hand, no Node-RED, phone registered, no Google services, test sent, test failed); the channel (push, ntfy, Pushover) |
| `alert_added` | An alert was added | its kind: leak, smoke, door or window opened, or battery low |
| `review_prompt` | From 2.6.5: the app asked Google Play to show its "rate this app" dialog (after a device you control has answered on two different days) | whether the dialog was requested, or could not be because the Play review flow is not available on the device. Nothing about whether you rated, or what |

**Never sent:** broker addresses, ports, usernames or passwords; the address you type into setup; MQTT topics or
messages; device names or addresses; home or dashboard names; device states or
values; error messages.

Because nothing identifies you, the developer cannot find or delete "your"
events on request. To stop sending, turn the switch off.

## Support emails

If you contact support, your email (and the Support details you choose to
include) is used only to help you, is never shared, and is deleted within 6
months after the issue is closed.

## Optional automation

If you create a "schedule" panel, ZigDash publishes the automation configuration
as a retained MQTT message to your own broker, where a flow you run (e.g. on
Node-RED) executes it. This data also stays within your own infrastructure.

## Children

ZigDash is a utility app and is not directed at children.

## Changes to this policy

If this policy changes, the updated version will be published at this URL with a
new effective date.

## Contact

Questions about this policy: **giladtamam1@gmail.com**
