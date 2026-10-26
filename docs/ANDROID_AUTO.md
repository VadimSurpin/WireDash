# Android Auto preview

This branch adds a projected Android Auto **IoT** app using AndroidX Car App
Library 1.8.0-rc01. Configure WireDash on the phone; the car presents native
dashboard groups and large action buttons. On hosts supporting Car App API 8,
select a dashboard once and operate its buttons directly in a scrolling grid.

## Controls

The car shows saved dashboards containing supported controls, in dashboard
order. Supported panels are command buttons, switches, covers, and writable
switches/buttons on whole-device Wiren Board or Zigbee2MQTT panels. Complete WB
curtain pairs are grouped into Open/Close controls. Other panel types remain on
the phone. A separate dashboard named "Car" is a useful way to group gates,
garage doors and driveway lights.

Saved section names and section order follow the phone dashboard. Unsectioned
tiles appear first, followed by each group in order. Empty groups are omitted.
Command buttons retain their names and configured Material icons/colors;
switches use one tile with their saved state icons and send the opposite state
on tap. Covers show their configured action buttons together, with the control
name below each action so similarly named Open/Close buttons are distinguishable.

Cover button visibility, titles and gate/roller icons follow the phone editor.
Command-only covers send the saved command, spin for one second and return to
their initial appearance without a state subscription. State-aware controls
use current-session MQTT feedback; relay activity is not a gate-position
estimate. Every new direction tap sends a command again, including another `1`
for a WB pulse input. WB command topics retain their leading slash, append
`/on`, and are never retained. The host disallows clicking a loading grid item;
the action becomes available again when its spinner finishes.

The dashboard and dashboard chooser use `SectionedItemTemplate` on API 8 hosts.
The host fetches more items while scrolling; WireDash does not insert Next or
Previous items or truncate the grid at the older template's item limit. Scroll
position is preserved across state/spinner updates. Spinners on different
controls are independent. Android Auto still determines grid geometry, button
sizes, and scrolling affordances; the phone's Flutter layout is not mirrored.

API 6/7 hosts retain the previous list/detail screens and pagination to respect
their hard content limits. Update Android Auto for the grouped scrolling UI.
The 1.8 release candidate is used for the API 8 template and scroll preservation.
Editing, credentials, text entry and connection setup are handled on the phone.

## Connections and lifecycle

The car uses the existing headless shortcut engine, the app's read-only
database, secure credentials and configured MQTT transport, including embedded
WireGuard. It does not require the phone dashboard to be open. The native
WireGuard implementation shares its peer with phone widgets and the phone UI.

Opening a dashboard after the car app was hidden rebuilds its MQTT connection
and private route, restores active subscriptions and displays Reconnecting
until connected. Old-session data cannot confirm a new command. Closing the
car UI releases its subscriptions; it does not destroy the engine used by
widgets. Reconnecting and refreshing never replay commands. Offline or expired
taps are rejected; changing/removing a panel also invalidates its old actions.

Release builds validate the car host using AndroidX's known-host allowlist and
system renderer permission. Debug builds allow development hosts for DHU use.

## Test and install

**A normal sideloaded APK is not sufficient for Android Auto in a real car.**
Google requires apps using the Car App Library to be installed from a trusted
source, such as Google Play internal app sharing or an internal testing track.
Android Auto's **Unknown sources** option does not apply to these templated
apps. See [Android's real-vehicle testing rules](https://developer.android.com/training/cars/testing).

For development, use Google's [Desktop Head Unit (DHU)](https://developer.android.com/training/cars/testing/dhu):

1. Install the branch's APK on a phone and configure the broker/WireGuard
   connection and dashboards in WireDash.
2. Update Android Auto and enable its developer mode by tapping its version
   information ten times in Android Auto settings.
3. Enable the head-unit server from Android Auto's developer menu.
4. Connect the phone by USB, then run `adb forward tcp:5277 tcp:5277` and start
   the SDK's `extras/google/auto/desktop-head-unit`.
5. Open WireDash in the DHU launcher. Select a dashboard. On an API 8 host,
   check that the saved groups and buttons are shown directly; scroll through
   a dashboard larger than one screen without Next/Previous controls.
6. Check a scalar WB switch and a gate: command topics/payloads must match the
   phone, button titles/icons must match, and repeated gate taps must publish
   another `1`. Test a command-only cover without state messages.
   Tap two different controls and verify each spinner clears independently
   after one second, without jumping back to the top of the dashboard.
7. Hide/return to the car app and disconnect/reconnect its network route.
   Reconnecting must appear, state must recover, and no command may be replayed.

For a real vehicle, upload the signed APK through your Play Console internal
test/internal app sharing and install it from that trusted link. Google Play
production review and Android Automotive OS (apps installed directly in the
vehicle) are separate distribution steps.

## Verification

The manual `car-preview` workflow runs an Automotive OS emulator with an
isolated demo database and a loopback MQTT broker. It preserves screenshots,
UI dumps, MQTT traffic and logcat even when the host fails. Its Automotive
adapter is only a test overlay; the phone APK is unchanged.

Runtime result on 2026-10-26: the latest available Google APIs image,
`android-35-ext15;android-automotive;x86_64` revision 4, opens the session but
logs `No presenter available for template type: SectionedItemTemplate` and
displays a blank surface. This workflow currently provides a diagnostic,
not a successful preview of the new scrolling dashboard. Google introduced
full support for this template on Android Auto first; see the
[1.8 release notes](https://developer.android.com/jetpack/androidx/releases/car-app#1.8.0-alpha01).
Use a phone connected to the DHU to verify the projected Android Auto layout.
Do not present an Automotive emulator capture as a projected Android Auto test.

`flutter test test/car` exercises saved-control routing, exact WB topics,
non-retained pulses, visibility, repeat commands, one-second timing, session
freshness, missing/removed controls, offline/expired-command handling, and saved
section ordering, orphaned tiles, group renaming and configured button appearance.

`cd android && ./gradlew :app:testFossDebugUnitTest` uses Robolectric and the
Car App testing library to build real host templates, request all items beyond
the old list/grid limits, check direct button commands and independent spinner
timing, require scroll preservation, and verify that stale callbacks/spinners do
not survive hiding and resuming the car screen. The older-host pagination
fallback is also tested. CI runs these tests before uploading the APK.

Official references: [IoT apps](https://developer.android.com/training/cars/apps/iot),
[projected-app manifest](https://developer.android.com/training/cars/apps/auto),
[Car App Library releases](https://developer.android.com/jetpack/androidx/releases/car-app).
