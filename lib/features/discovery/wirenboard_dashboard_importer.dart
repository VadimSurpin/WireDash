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
import 'models/wirenboard_panel_suggestion.dart';
import 'wirenboard_device_groups.dart';

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
  final _sectionGroups = wirenBoardSectionGroups();

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

  /// A deliberate whole-device add asks for a label.
  Future<void> addDevice(WirenBoardDevice device, {required String label}) {
    final operation = _pending.then((_) async {
      await _import([device], true, labels: {device.id: label});
    });
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  /// Adds one property as a standard dashboard control, using WB scalar topics.
  Future<void> addControl(
    WirenBoardDevice device,
    WirenBoardControl control, {
    required String label,
    PanelType? widgetType,
  }) {
    final operation = _pending.then((_) async {
      if (control.deviceId != device.id ||
          !device.controls.any((c) => c.id == control.id)) {
        throw ArgumentError('Control does not belong to device');
      }
      final suggestion = suggestWirenBoardPanel(
        device,
        control,
        language: _l10n.localeName.split('_').first,
        widgetType: widgetType,
      );
      final tiles = await _panels.getByDashboard(_dashboardId);
      await _panels.create(
        dashboardId: _dashboardId,
        name: label,
        type: suggestion.type,
        topic: suggestion.publishTopicSuffix,
        subscribeTopic: suggestion.subscribeTopicSuffix,
        topicPrefixOverride: suggestion.topicPrefixOverride,
        width: suggestion.type == PanelType.slider
            ? PanelWidth.wide
            : PanelWidth.small,
        sortOrder: tiles.fold<int>(
          0,
          (n, p) => p.sortOrder >= n ? p.sortOrder + 1 : n,
        ),
        sectionId: await _sectionFor(device.group),
        config: suggestion.config!,
      );
    });
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<String> _sectionFor(WirenBoardDeviceGroup group) async {
    final sections = await _sections.getByDashboard(_dashboardId);
    final existing = sections
        .where((s) => _sectionGroups[s.name] == group)
        .firstOrNull;
    if (existing != null) return existing.id;
    return _sections.create(
      dashboardId: _dashboardId,
      name: wirenBoardGroupLabel(group, _l10n),
      sortOrder: sections.fold<int>(
        0,
        (n, s) => s.sortOrder >= n ? s.sortOrder + 1 : n,
      ),
    );
  }

  Future<int> _import(
    List<WirenBoardDevice> devices,
    bool includeBuiltins, {
    Map<String, String> labels = const {},
  }) async {
    final tiles = await _panels.getByDashboard(_dashboardId);
    final existing =
        <String, List<({Panel tile, WirenBoardDeviceConfig config})>>{};
    for (final tile in tiles) {
      if (tile.type != PanelType.device) continue;
      final config = PanelConfig.decode(tile.type, tile.config);
      if (config is WirenBoardDeviceConfig) {
        (existing[config.device.id] ??= []).add((tile: tile, config: config));
      }
    }
    final sections = await _sections.getByDashboard(_dashboardId);
    final managedIds = {
      for (final s in sections)
        if (_sectionGroups.containsKey(s.name)) s.id,
    };
    final sectionIds = {
      for (final s in sections)
        if (_sectionGroups[s.name] case final group?) group: s.id,
    };
    var nextSection = sections.fold<int>(
      0,
      (n, s) => s.sortOrder >= n ? s.sortOrder + 1 : n,
    );
    var nextTile = tiles.fold<int>(
      0,
      (n, p) => p.sortOrder >= n ? p.sortOrder + 1 : n,
    );
    Future<String> sectionFor(WirenBoardDeviceGroup group) async {
      if (sectionIds[group] case final id?) return id;
      final id = await _sections.create(
        dashboardId: _dashboardId,
        name: wirenBoardGroupLabel(group, _l10n),
        sortOrder: nextSection++,
      );
      sectionIds[group] = id;
      managedIds.add(id);
      return id;
    }

    var added = 0;
    final unique = {for (final device in devices) device.id: device};
    for (final device in unique.values) {
      final previous = existing[device.id] ?? const [];
      final whole = previous
          .where((p) => p.config.controlIds == null)
          .firstOrNull;
      final create =
          whole == null && (!device.isControllerBuiltin || includeBuiltins);
      if (previous.isEmpty && !create) continue;
      final needsSection =
          create ||
          previous.any(
            (p) =>
                p.tile.sectionId == null ||
                managedIds.contains(p.tile.sectionId),
          );
      final sectionId = needsSection ? await sectionFor(device.group) : null;
      for (final entry in previous) {
        final tile = entry.tile;
        final config = WirenBoardDeviceConfig(
          device: device,
          controlIds: entry.config.controlIds,
          display: entry.config.display,
        );
        final name = tile.id == whole?.tile.id
            ? labels[device.id] ?? tile.name
            : tile.name;
        if (tile.config != config.encode() || tile.name != name) {
          await _panels.update(
            id: tile.id,
            name: name,
            topic: tile.topic,
            subscribeTopic: tile.subscribeTopic,
            topicPrefixOverride: tile.topicPrefixOverride,
            qos: tile.qos,
            retain: tile.retain,
            width: tile.width,
            config: config,
          );
        }
        // Only automatic or ungrouped panels move; a user's custom section stays.
        if ((tile.sectionId == null || managedIds.contains(tile.sectionId)) &&
            tile.sectionId != sectionId) {
          await _panels.setSection(tile.id, sectionId);
        }
      }
      if (!create) continue;
      await _panels.create(
        dashboardId: _dashboardId,
        name:
            labels[device.id] ??
            device.title(_l10n.localeName.split('_').first),
        type: PanelType.device,
        topic: '',
        subscribeTopic: '',
        topicPrefixOverride: '/devices/${device.id}',
        width: PanelWidth.wide,
        sortOrder: nextTile++,
        sectionId: sectionId,
        config: WirenBoardDeviceConfig(device: device),
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
