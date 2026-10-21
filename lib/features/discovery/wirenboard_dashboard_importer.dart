import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_l10n.dart';
import '../../data/database/database.dart';
import '../../data/database/tables/panels.dart';
import '../../data/repositories/dashboard_repo.dart';
import '../../data/repositories/panel_repo.dart';
import '../../data/repositories/section_repo.dart';
import '../../l10n/app_localizations.dart';
import '../panels/models/panel_config.dart';
import '../settings/providers/settings_controller.dart';
import 'models/wirenboard_device.dart';

/// Serializes imports and recognizes existing whole-device tiles by MQTT ID.
/// Replayed retained batches update cached metadata without duplicating tiles.
class WirenBoardDashboardImporter {
  WirenBoardDashboardImporter({
    required String dashboardId,
    required PanelRepo panels,
    required SectionRepo sections,
    required AppLocalizations l10n,
  }) : _dashboardId = dashboardId,
       _panels = panels,
       _sections = sections,
       _l10n = l10n;

  final String _dashboardId;
  final PanelRepo _panels;
  final SectionRepo _sections;
  final AppLocalizations _l10n;
  Future<void> _pending = Future.value();

  Future<int> importDevices(
    List<WirenBoardDevice> devices, {
    bool includeBuiltins = false,
  }) {
    final operation = _pending.then((_) => _import(devices, includeBuiltins));
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<int> _import(
    List<WirenBoardDevice> devices,
    bool includeBuiltins,
  ) async {
    final tiles = await _panels.getByDashboard(_dashboardId);
    final existing = <String, Panel>{};
    for (final tile in tiles) {
      if (tile.type != PanelType.device) continue;
      final config = PanelConfig.decode(tile.type, tile.config);
      if (config is WirenBoardDeviceConfig) existing[config.device.id] = tile;
    }
    final sections = await _sections.getByDashboard(_dashboardId);
    final sectionIds = {
      for (final section in sections) section.name: section.id,
    };
    var nextSection = sections.fold<int>(
      0,
      (n, s) => s.sortOrder >= n ? s.sortOrder + 1 : n,
    );
    var nextTile = tiles.fold<int>(
      0,
      (n, p) => p.sortOrder >= n ? p.sortOrder + 1 : n,
    );
    var added = 0;
    final unique = {for (final device in devices) device.id: device};
    for (final device in unique.values) {
      if (device.isControllerBuiltin && !includeBuiltins) continue;
      final config = WirenBoardDeviceConfig(device: device);
      final tile = existing[device.id];
      if (tile != null) {
        if (tile.config != config.encode()) {
          await _panels.update(
            id: tile.id,
            name: tile.name,
            topic: tile.topic,
            subscribeTopic: tile.subscribeTopic,
            topicPrefixOverride: tile.topicPrefixOverride,
            qos: tile.qos,
            retain: tile.retain,
            width: tile.width,
            config: config,
          );
        }
        continue;
      }
      final group = device.isControllerBuiltin
          ? _l10n.wbControllerBuiltins
          : _l10n.wbAddedModules;
      final section = sectionIds[group] ??= await _sections.create(
        dashboardId: _dashboardId,
        name: group,
        sortOrder: nextSection++,
      );
      await _panels.create(
        dashboardId: _dashboardId,
        name: device.title(_l10n.localeName.split('_').first),
        type: PanelType.device,
        topic: '',
        subscribeTopic: '',
        topicPrefixOverride: '/devices/${device.id}',
        width: PanelWidth.wide,
        sortOrder: nextTile++,
        sectionId: section,
        config: config,
      );
      added++;
    }
    return added;
  }
}

final wirenBoardDashboardImporterProvider =
    Provider.family<WirenBoardDashboardImporter, String>(
      (ref, id) => WirenBoardDashboardImporter(
        dashboardId: id,
        panels: ref.watch(panelRepoProvider),
        sections: ref.watch(sectionRepoProvider),
        l10n: appL10n(ref.read(settingsControllerProvider).locale),
      ),
    );

Set<String> _deviceIds(List<Panel> panels) => {
  for (final panel in panels)
    if (panel.type == PanelType.device)
      if (PanelConfig.decode(panel.type, panel.config)
          case WirenBoardDeviceConfig(:final device))
        device.id,
};

final wirenBoardDashboardIdsProvider = Provider.autoDispose
    .family<Set<String>, String>(
      (ref, id) => _deviceIds(
        ref.watch(panelsForDashboardProvider(id)).valueOrNull ?? const [],
      ),
    );

final linkedWirenBoardIdsProvider = Provider.autoDispose
    .family<Set<String>, String>(
      (ref, connectionId) => {
        for (final dashboard
            in ref
                    .watch(dashboardsForConnectionProvider(connectionId))
                    .valueOrNull ??
                const <Dashboard>[])
          ...ref.watch(wirenBoardDashboardIdsProvider(dashboard.id)),
      },
    );
