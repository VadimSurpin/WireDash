# Android Auto preview

This branch adds a projected Android Auto **IoT** app using AndroidX Car App
Library 1.8.0-rc01. Configure WireDash on the phone; the car presents native
dashboard groups and large action buttons. On hosts supporting Car App API 8,
select a dashboard once and operate its controls directly in a grouped scrolling
`ListTemplate` (build 104 experiment).

## Controls

The car shows saved dashboards containing supported controls, in dashboard
order. Supported panels are command buttons, switches, covers, and writable
switches/buttons on whole-device Wiren Board or Zigbee2MQTT panels. Legacy
radio/enum shutter tiles and position selectors (radio, combo, or multi-state)
are included with their saved labels, option order, payloads, and state matches.
Endpoint-specific Zigbee shutter state properties are retained. Complete WB
curtain pairs are grouped into Open/Close controls. Other panel types remain on
the phone. A separate dashboard named "Car" is a useful way to group gates,
garage doors and driveway lights.

Saved section names and section order follow the phone dashboard. Unsectioned
tiles appear first, followed by each group in order. Empty groups are omitted.
Command buttons retain their names and configured Material icons/colors.
Switches use native toggles with their saved state icons. A cover puts its
configured Open and Close actions together beside its name in one list row.
Android Auto allows at most two inline actions per row on API 8. A configured
Stop button and additional position presets appear in further rows for the same
control, in pairs, so every configured action remains accessible. Action labels
also appear below the control name because hosts may render actions as icons.

Cover button visibility, titles and gate/roller icons follow the phone editor.
Position-aware covers also show their saved percentage presets; a slider-only
cover uses 0/25/50/75/100% buttons in Auto. Writable Zigbee cover position features
use their exact endpoint property. MQTT feedback highlights the reported
position and confirms a pending position only when its target is reported.
WB relay pairs expose direction commands, without inventing a position estimate.
Command-only covers send the saved command and retain their appearance without
a state subscription. Their duplicate-command guard lasts one second. State-aware controls
use current-session MQTT feedback; relay activity is not a gate-position
estimate. Every new direction tap sends a command again, including another `1`
for a WB pulse input. WB command topics retain their leading slash, append
`/on`, and are never retained. On the grouped scrolling dashboard, a command
shows a brief native message with the control name and localized sending text.
Starting/finishing a command does not change rows, actions or their delegates,
and does not invalidate the template. This avoids a refresh solely for progress
feedback. Controls continue to display actual device state; pending commands
still reject duplicate taps internally. Command-only guards expire after one
second independently for each control. Other cover directions (including Stop)
remain available during a direction command. Toggle delegates check the latest
state even when the host still holds an older row. Fresh MQTT state and
configuration changes still update the list; updates in the same main-loop turn
are coalesced.

Build 104 replaces the dashboard's API 8 `SectionedItemTemplate` grid with the
classic `ListTemplate`, keeping saved section headings and order. The dashboard
chooser still uses its existing template. Lists have a host-defined content
limit: ordinary dashboards scroll on one screen, while larger dashboards add
Previous/Next rows. Every saved control and action remains reachable; state
updates preserve the current page. This differs from the previous lazy grid,
which could fetch more items without paging.

Android Auto 17.9 was reported to reset the grid's position for real state
updates, including changes from the phone without an Auto tap. The list is an
experiment with a different host renderer, **not a verified fix** for that host.
It keeps row titles, row counts and group headings stable during state-only
updates, in line with the classic list's refresh rules. Reconnection uses one
localized popup per outage and retains the last-known control appearance.
Robolectric verifies client/IPC behavior, not Android Auto's renderer. See the
[scroll investigation](ANDROID_AUTO_SCROLL.md). Android Auto controls row geometry,
button sizes and scrolling affordances.

API 6/7 hosts retain the previous list/detail screens and pagination to respect
their hard content limits. API 8 is required for two inline actions per row.
Editing, credentials, text entry and connection setup are handled on the phone.

## Connections and lifecycle

On the `feat/video-widget-plugin` branch, Video panels are also listed in their
saved groups. Camera entries remain browsable when MQTT is offline and send no
MQTT commands. They explain that video, zoom/pan and recording/event playback
must currently be opened on the phone while parked: the IoT template cannot
embed the player. Developer mode does not unlock a video surface. The
[current parked-app guide](https://developer.android.com/training/cars/parked/auto)
lists only games for projected Android Auto. See the
[video plugin guide](../packages/wiredash_video/README.md#android-auto).

The car uses the existing headless shortcut engine, the app's read-only
database, secure credentials and configured MQTT transport, including embedded
WireGuard. It does not require the phone dashboard to be open. Flutter's cold
initialization waits in the background, and the headless engine initializes
SQLite independently of the phone UI. Timed-out requests are removed from the
startup queue. Transient engine errors retain the current dashboard with
Reconnecting feedback rather than replacing it with another template. The native
WireGuard implementation shares its peer with phone widgets and the phone UI.

The headless engine registers only paths, preferences, secure storage, SQLite and
WireGuard plugins. It does not load the phone's video or activity plugins.
Startup has a 20-second watchdog; a startup that never signals ready can be
discarded and retried. A timed-out catalog/dashboard read also invalidates a
stalled engine, so later polls can recover. Outstanding requests fail once and
commands are never replayed. Late startup callbacks cannot revive an old engine.

Opening a dashboard after the car app was hidden rebuilds its MQTT connection
and private route and restores active subscriptions. A brief localized
Reconnecting popup announces each outage without replacing every control's
caption or last-known icon. Resuming while still offline or tapping an offline
control shows the reminder again; offline taps send no commands. The reconnect
action shows its popup immediately, before the connection request finishes.
Camera-only dashboards do not warn about an unused MQTT connection.
Old-session data cannot confirm a new command. Closing the
car UI releases its subscriptions; it does not destroy the engine used by
widgets. Reconnecting and refreshing never replay commands. Offline or expired
taps are rejected; changing/removing a panel also invalidates its old actions.

Release builds validate the car host using AndroidX's known-host allowlist and
system renderer permission. Debug builds allow development hosts for DHU use.

## Test and install

**For the current test APK, enable Android Auto developer mode and turn on
Unknown sources in its developer settings.** This is the setup used for the
tested development installation.

Google Play internal app sharing or an internal testing track provides another
installation route. See [Android's testing guide](https://developer.android.com/training/cars/testing).

For development, use Google's [Desktop Head Unit (DHU)](https://developer.android.com/training/cars/testing/dhu):

1. Install the branch's APK on a phone and configure the broker/WireGuard
   connection and dashboards in WireDash.
2. Update Android Auto and enable its developer mode by tapping its version
   information ten times in Android Auto settings. Open the developer settings
   and enable **Unknown sources**.
3. Enable the head-unit server from Android Auto's developer menu.
4. Connect the phone by USB, then run `adb forward tcp:5277 tcp:5277` and start
   the SDK's `extras/google/auto/desktop-head-unit`.
5. Open WireDash in the DHU launcher. Select a dashboard. On an API 8 host,
   check that the saved groups and buttons are shown directly; scroll through
   the list and check that a shutter has Open/Close in one row. Larger dashboards
   may have Previous/Next rows at the host content limit.
6. Check a scalar WB switch and a gate: command topics/payloads must match the
   phone, button titles/icons must match, and repeated gate taps must publish
   another `1`. Test a command-only cover without state messages.
   Tap two different controls and verify sending messages appear without a
   list redraw or jump to the top. Each control becomes repeatable after its
   independent one-second command guard expires.
7. Hide/return to the car app and disconnect/reconnect its network route.
   A Reconnecting popup must appear once per outage without changing control
   captions. Offline taps must show a reminder without sending; state must
   recover, and no command may be replayed.
8. Scroll down and change a switch from the phone without tapping Auto. Check
   whether the host preserves the position. Capture `WireDashAuto` logcat as
   described in the [investigation](ANDROID_AUTO_SCROLL.md) if it resets.

For distribution through Google Play, upload the signed APK through your Play
Console internal test/internal app sharing and install it from that link. Google Play
production review and Android Automotive OS (apps installed directly in the
vehicle) are separate distribution steps.

## Verification

The manual `car-preview` workflow runs an Automotive OS emulator with an
isolated demo database and a loopback MQTT broker. It preserves screenshots,
UI dumps, MQTT traffic and logcat even when the host fails. Its Automotive
adapter is only a test overlay; the phone APK is unchanged.

Historical grid runtime result on 2026-10-26: the latest available Google APIs image,
`android-35-ext15;android-automotive;x86_64` revision 4, opens the session but
logs `No presenter available for template type: SectionedItemTemplate` and
displays a blank surface. That run provides a diagnostic,
not a successful preview of the new list experiment. Google introduced
full support for this template on Android Auto first; see the
[1.8 release notes](https://developer.android.com/jetpack/androidx/releases/car-app#1.8.0-alpha01).
Use a phone connected to the DHU to verify the projected Android Auto layout.
Do not present an Automotive emulator capture as a projected Android Auto test.

`flutter test test/car` exercises saved-control routing, exact WB topics,
non-retained pulses, visibility, repeat commands, one-second timing, session
freshness, missing/removed controls, offline/expired-command handling, and saved
section ordering, orphaned tiles, group renaming and configured button appearance.

`cd android && ./gradlew :app:testFossDebugUnitTest` uses Robolectric and the
Car App testing library builds real host templates and verifies grouped rows,
native toggles, paired cover actions and every preset
beyond the host limit. They check direct commands, independent guards, sending
messages, zero progress-only template submissions and stable delegates.
The previous grid remains covered for comparison, including its scroll policy.
Tests also verify that stale callbacks/pending indicators do not survive hiding
and resuming the car screen. The older-host pagination
fallback is also tested. CI runs these tests before uploading the APK.

Returning from a dashboard keeps the chooser's last snapshot while it refreshes.
This preserves its rows and template type, as required for
[Android Auto Back navigation](https://developer.android.com/reference/androidx/car/app/Screen).
Regression tests cover repeated returns with delayed and stale responses on
both modern and legacy hosts, position-button routing and feedback, and paging
through all presets on hosts with smaller grid limits.

The `video-preview` workflow additionally runs
`tool/car_preview/headless_smoke.py` on its isolated Android emulator. This
clears only that emulator's test data, installs the demo database and drives the
real native/Dart Auto bridge with a loopback MQTT broker. It checks first-engine
startup without opening the phone, removes the phone task through the same OS
operation as Recents, and checks restart after force-stopping the whole process.
Each phase verifies actual commands and MQTT state feedback. This checks the
headless lifecycle, not Android Auto's template renderer or a particular phone's
battery-management behavior. Logs and a summary are saved with the runtime
artifacts. The debug-only receiver used by this harness is absent from release
builds.

Official references: [IoT apps](https://developer.android.com/training/cars/apps/iot),
[projected-app manifest](https://developer.android.com/training/cars/apps/auto),
[Car App Library releases](https://developer.android.com/jetpack/androidx/releases/car-app).
