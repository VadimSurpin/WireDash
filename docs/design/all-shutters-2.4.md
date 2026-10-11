# All shutters: close, open or stop every shutter with one tap (2.4)

Decided 2026-10-11 in a five-question round; the user took every
recommendation. From the first poll answer (2.3.0, French): "close all my
shutters with one button". Words follow [CONTEXT.md](../../CONTEXT.md)
(**Scene**, **Built-in scene**, **Device tile**).

## Decisions

1. **Built-in scenes, resolved when they run.** Every Home has three scenes
   it never has to create: Close all shutters, Open all shutters, Stop all
   shutters. They hold no device list; when run they look up the Home's
   covers at that moment (the bridge's device list) and send each one
   `{"state":"CLOSE"}`, `OPEN` or `STOP`. A shutter added or renamed later
   is included by itself. Not a new tile type, not a section action: they
   get everything scenes already have, the scene tile, the home-screen scene
   widget, the group widget's scene buttons and "Activated …".
2. **Three built-ins, all listed** in the Scenes tab under "All shutters",
   above "Your scenes". Only Close all is placed on a dashboard by setup.
3. **Setup places a "Close all shutters" tile** in the Switches and covers
   section when two or more shutters are chosen. Existing Homes are not
   rearranged: the built-ins appear in their Scenes tab, with Add to
   dashboard, and the 2.4 release note says so.
4. **"All" means every cover the bridge reports, minus exclusions.**
   Zigbee2MQTT files garage doors and gates under the same class, so each
   built-in has "Which shutters…": a checklist of the Home's covers, all
   ticked by default. Exclusions are stored per Home by IEEE address
   (`all_shutters_excluded.<connectionId>`), so renames don't matter and a
   new shutter arrives ticked.
5. **The word is "shutters"**: Rollläden, volets, persianas, rolluiken,
   rolety, рольставни, jalusier. Nobody says "covers".

## Behaviour

- The built-ins are not database rows. `scenesForConnectionProvider` lists
  them in front of the saved scenes with stable ids `all_shutters:close`,
  `all_shutters:open`, `all_shutters:stop`, named in the app's language and
  renamed when it changes. Scene tiles, widgets and backups refer to those
  ids.
- The Scenes tab shows the "All shutters" group only while the Home is
  known to have a shutter (bridge device list). A scene tile for a built-in
  keeps working regardless; with no shutter known or included it reports
  "Not connected", the same as a saved scene offline.
- Running: the app resolves against the live device list it already holds
  (`resolveSceneActions`); the headless shortcut engine (widgets, group
  widget) subscribes to `<base>/bridge/devices`, waits up to 3 s for the
  retained list, then runs the actions like any scene and reports Sent /
  Confirmed.
- The widget picker offers the built-ins for a Home that has a shutter tile
  on any dashboard (the headless side has no device list to ask).
- A built-in cannot be edited or deleted; its menu has Which shutters… and
  Add to dashboard.

## Out of scope

- Position presets ("all shutters to 30%"): a saved scene does that.
- Zigbee groups: still "later, if asked".
- Quick Settings tiles and Device Controls don't offer scenes today, so not
  the built-ins either.

## Code

- `lib/features/scenes/all_shutters.dart`: `ShutterCommand`, ids, names,
  icons, the `Scene` rows, exclusion preferences, `shuttersOf`,
  `includedShutters`, `shutterActions`.
- `lib/features/scenes/scenes_providers.dart`: the composed
  `scenesForConnectionProvider`, `homeShuttersProvider`,
  `resolveSceneActions`, `runScene`.
- `lib/features/scenes/screens/scenes_screen.dart`: the two groups, the
  built-in rows, the Which shutters… sheet.
- `lib/features/panels/widgets/scene_panel.dart`: runs through `runScene`.
- `lib/shortcuts/shortcut_engine.dart`: `_shutterActions`, `_homeBase`.
- `lib/shortcuts/shortcut_service.dart`: `resyncScenes` offers the built-ins
  for a Home with a shutter tile.
- `lib/features/onboarding/setup/setup_creator.dart`: the Close all tile.
- Strings: `scenesAllShutters`, `sceneCloseAllShutters`,
  `sceneOpenAllShutters`, `sceneStopAllShutters`, `sceneShuttersCount`,
  `sceneWhichShutters`, `sceneWhichShuttersHint`, `scenesYours`, 11 ARBs.
- Tests: `test/scenes/all_shutters_test.dart`,
  `test/scenes/all_shutters_screen_test.dart`, cases in
  `setup_creator_test.dart` and `shortcut_service_test.dart`.
