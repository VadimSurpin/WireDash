import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/database.dart';
import '../../data/database/tables/panels.dart';
import '../../data/repositories/dashboard_repo.dart';
import '../../data/repositories/panel_repo.dart';
import '../history/history_config.dart' show historyShownOnDeviceTile;
import '../panels/models/panel_config.dart';
import '../panels/providers/panel_value_provider.dart';
import '../settings/providers/settings_controller.dart';

/// A number a dashboard shows, which the idle clock can show too
/// (wall-tablet-2.9.md §3): from a reading tile, or one of the values a
/// device tile shows (a climate sensor's temperature and humidity).
class WallReading {
  const WallReading({
    required this.panelId,
    required this.name,
    required this.topic,
    required this.path,
    this.unit,
    this.decimals,
  });

  final String panelId;
  final String name;

  /// The full state topic the tile listens on.
  final String topic;
  final String path;
  final String? unit;
  final int? decimals;

  /// Stable for the stored choice: the tile and the value in it.
  String get key => '$panelId/$path';
}

/// The idle clock shows at most this many readings.
const wallMaxReadings = 3;

/// Every number [tiles] show, in dashboard order, once each. [prefix] is the
/// dashboard's topic prefix, which a tile without its own override uses.
List<WallReading> wallReadingsOf(Iterable<Panel> tiles, String? prefix) {
  final out = <WallReading>[];
  final seen = <String>{};
  for (final tile in tiles) {
    final topic = composeTopic(
      tile.topicPrefixOverride ?? prefix,
      tile.subscribeTopic ?? tile.topic,
    );
    if (topic.isEmpty) continue;
    void add(String path, String? unit, [int? decimals]) {
      if (path.isEmpty || !seen.add('$topic/$path')) return;
      out.add(
        WallReading(
          panelId: tile.id,
          name: tile.name,
          topic: topic,
          path: path,
          unit: unit,
          decimals: decimals,
        ),
      );
    }

    switch (tile.type) {
      case PanelType.reading:
        final c = PanelConfig.decode(PanelType.reading, tile.config);
        if (c is ReadingConfig) add(c.jsonPath, c.unit, c.decimals);
      case PanelType.device:
        final c = PanelConfig.decode(PanelType.device, tile.config);
        if (c is DeviceTileConfig) {
          for (final f in historyShownOnDeviceTile(c.profile)) {
            add(f.property, f.unit);
          }
        }
      default:
        break;
    }
  }
  return out;
}

/// The readings chosen for one dashboard's idle clock, as [WallReading.key]s.
/// Null until the user picks: the dashboard's first [wallMaxReadings].
class WallIdleReadingsSetting extends FamilyNotifier<List<String>?, String> {
  String get _key => 'wall_idle_readings_$arg';

  @override
  List<String>? build(String arg) =>
      ref.read(sharedPreferencesProvider).getStringList(_key);

  Future<void> set(List<String> keys) async {
    state = keys.take(wallMaxReadings).toList();
    await ref.read(sharedPreferencesProvider).setStringList(_key, state!);
  }
}

final wallIdleReadingsSettingProvider =
    NotifierProvider.family<WallIdleReadingsSetting, List<String>?, String>(
      WallIdleReadingsSetting.new,
    );

/// Everything a dashboard shows, for the picker.
final wallReadingsAvailableProvider = Provider.autoDispose
    .family<List<WallReading>, String>((ref, dashboardId) {
      final dashboard = ref
          .watch(dashboardByIdProvider(dashboardId))
          .valueOrNull;
      final tiles =
          ref.watch(panelsForDashboardProvider(dashboardId)).valueOrNull ??
          const <Panel>[];
      return wallReadingsOf(tiles, dashboard?.topicPrefix);
    });

/// What the idle clock shows: the chosen readings still on the dashboard,
/// or its first [wallMaxReadings] when nothing was chosen.
final wallIdleReadingsProvider = Provider.autoDispose
    .family<List<WallReading>, String>((ref, dashboardId) {
      final all = ref.watch(wallReadingsAvailableProvider(dashboardId));
      final chosen = ref.watch(wallIdleReadingsSettingProvider(dashboardId));
      if (chosen == null) return all.take(wallMaxReadings).toList();
      return [
        for (final r in all)
          if (chosen.contains(r.key)) r,
      ].take(wallMaxReadings).toList();
    });
