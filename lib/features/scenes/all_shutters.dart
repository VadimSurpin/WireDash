import 'package:flutter/material.dart' show Icons;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/tokens.dart';
import '../../data/database/database.dart';
import '../../l10n/app_localizations.dart';
import '../devices/device_profile.dart';
import '../discovery/models/z2m_device.dart';
import 'models/scene.dart';

/// The built-in "All shutters" scenes (docs/design/all-shutters-2.4.md).
///
/// Every Home has three scenes it never has to create: Close all shutters,
/// Open all shutters and Stop all shutters. They hold no device list; when
/// run they look up the Home's covers at that moment and command each one,
/// so a shutter added or renamed later is included by itself. They are not
/// database rows: [scenesForConnectionProvider] adds them in front of the
/// saved scenes, with ids from [allShuttersSceneId], and every place that
/// runs a scene resolves them through [shutterActions].
enum ShutterCommand {
  close('CLOSE'),
  open('OPEN'),
  stop('STOP');

  const ShutterCommand(this.state);

  /// The Zigbee2MQTT cover `state` to send.
  final String state;

  /// The command's full payload for a cover's `/set`.
  String get payload => '{"state":"$state"}';
}

const _idPrefix = 'all_shutters:';

/// How long a built-in waits for the bridge's device list before giving up.
const shutterListTimeout = Duration(seconds: 3);

/// The scene id of a built-in: stable, so scene tiles, home-screen widgets
/// and backups can refer to it.
String allShuttersSceneId(ShutterCommand c) => '$_idPrefix${c.name}';

/// The command a built-in scene id stands for, or null for a saved scene.
ShutterCommand? allShuttersCommand(String sceneId) {
  if (!sceneId.startsWith(_idPrefix)) return null;
  final name = sceneId.substring(_idPrefix.length);
  for (final c in ShutterCommand.values) {
    if (c.name == name) return c;
  }
  return null;
}

/// The built-in's name in the app's language.
String allShuttersName(ShutterCommand c, AppLocalizations l10n) => switch (c) {
      ShutterCommand.close => l10n.sceneCloseAllShutters,
      ShutterCommand.open => l10n.sceneOpenAllShutters,
      ShutterCommand.stop => l10n.sceneStopAllShutters,
    };

/// The built-in's icon, stored like a saved scene's (a Material code point,
/// drawn through `materialIcon`).
int allShuttersIcon(ShutterCommand c) => switch (c) {
      ShutterCommand.close => Icons.blinds_closed.codePoint,
      ShutterCommand.open => Icons.blinds.codePoint,
      ShutterCommand.stop => Icons.stop_circle_outlined.codePoint,
    };

/// A built-in as a [Scene] row for the lists and tiles. [name] is already
/// localised ([allShuttersName]); the actions column is empty because the
/// actions are resolved when the scene runs.
Scene allShuttersScene(ShutterCommand c, String connectionId, String name) {
  final stamp = DateTime.fromMillisecondsSinceEpoch(0);
  return Scene(
    id: allShuttersSceneId(c),
    connectionId: connectionId,
    name: name,
    iconCodepoint: allShuttersIcon(c),
    colorSeed: SignalPalette.amberLight.toARGB32(),
    actions: '[]',
    sortOrder: c.index - ShutterCommand.values.length,
    createdAt: stamp,
    updatedAt: stamp,
  );
}

/// The three built-ins for [connectionId], in order.
List<Scene> allShuttersScenes(String connectionId, AppLocalizations l10n) => [
      for (final c in ShutterCommand.values)
        allShuttersScene(c, connectionId, allShuttersName(c, l10n)),
    ];

/// Whether [device] is a cover (shutter, blind, curtain, also a garage
/// door, which is why [excludedShutters] exists).
bool isShutter(Z2mDevice device) =>
    classifyExposes(device.rawExposes).deviceClass == DeviceClass.cover;

/// The covers among [devices].
List<Z2mDevice> shuttersOf(Iterable<Z2mDevice> devices) =>
    [for (final d in devices) if (isShutter(d)) d];

/// How a shutter is remembered in the exclusion list: by IEEE address, so a
/// rename changes nothing; by name only for a device without one.
String shutterKey(Z2mDevice d) => d.ieeeAddress ?? d.friendlyName;

/// Preferences key of the Home's excluded shutters (a string list of
/// [shutterKey]s). Shutters are included unless listed here, so a new
/// shutter joins by itself.
String allShuttersExcludedKey(String connectionId) =>
    'all_shutters_excluded.$connectionId';

Set<String> excludedShutters(SharedPreferences prefs, String connectionId) =>
    (prefs.getStringList(allShuttersExcludedKey(connectionId)) ?? const [])
        .toSet();

Future<void> setShutterExcluded(
  SharedPreferences prefs,
  String connectionId, {
  required String key,
  required bool excluded,
}) async {
  final set = excludedShutters(prefs, connectionId);
  if (excluded) {
    set.add(key);
  } else {
    set.remove(key);
  }
  await prefs.setStringList(allShuttersExcludedKey(connectionId), set.toList());
}

/// The shutters a built-in acts on: every cover among [devices] that is not
/// excluded.
List<Z2mDevice> includedShutters(
  Iterable<Z2mDevice> devices,
  Set<String> excluded,
) =>
    [for (final d in shuttersOf(devices)) if (!excluded.contains(shutterKey(d))) d];

/// The actions a built-in runs right now: [command] to every included
/// shutter's `<base>/<name>/set`.
List<SceneAction> shutterActions(
  ShutterCommand command,
  String base,
  Iterable<Z2mDevice> devices,
  Set<String> excluded,
) =>
    [
      for (final d in includedShutters(devices, excluded))
        SceneAction(
          setTopic: '$base/${d.friendlyName}/set',
          payload: command.payload,
        ),
    ];
