import '../../core/theme/dashboard_accent.dart';
import '../../data/database/daos/device_registry_dao.dart';
import '../../data/database/tables/panels.dart';
import '../../data/repositories/dashboard_repo.dart';
import '../../data/repositories/panel_repo.dart';
import '../../data/repositories/section_repo.dart';
import '../devices/device_tiles.dart';
import 'ha_registry.dart';

/// What an import changed.
class HaImportResult {
  const HaImportResult({
    required this.renamed,
    required this.dashboardIds,
    required this.tiles,
  });

  /// Existing tiles that took their Home Assistant name.
  final int renamed;

  /// The dashboards made from Home Assistant's floors and rooms, in order.
  final List<String> dashboardIds;
  final int tiles;
}

/// Writes an [ImportPlan] into a home (docs/design/ha-import.md, Q5):
/// tiles that still carry the device's own name take the Home Assistant
/// name, and nothing the user built is moved; when [makeDashboards] is set,
/// a dashboard per floor with a section per room is added beside the
/// home's dashboards.
class HaImportApplier {
  HaImportApplier({
    required DashboardRepo dashboards,
    required SectionRepo sections,
    required PanelRepo panels,
    required DeviceRegistryDao registry,
  }) : _dashboards = dashboards,
       _sections = sections,
       _panels = panels,
       _registry = registry;

  final DashboardRepo _dashboards;
  final SectionRepo _sections;
  final PanelRepo _panels;
  final DeviceRegistryDao _registry;

  /// [homeName] names the dashboard of rooms on no floor when the home has
  /// no floors; [otherRoomsName] names it when there are floors too, and
  /// [noRoomName] the section of devices in no room. [skipRooms] are room
  /// names the user unticked on the preview.
  Future<HaImportResult> apply({
    required String connectionId,
    required ImportPlan plan,
    required bool makeDashboards,
    required String homeName,
    required String otherRoomsName,
    required String noRoomName,
    String base = 'zigbee2mqtt',
    Set<String?> skipRooms = const {},
  }) async {
    final renamed = await _rename(connectionId, plan, base);
    if (!makeDashboards) {
      return HaImportResult(renamed: renamed, dashboardIds: const [], tiles: 0);
    }
    final ids = <String>[];
    var tiles = 0;
    final floored = plan.dashboards.any((d) => d.floor != null);
    for (final board in plan.dashboards) {
      final rooms = [
        for (final r in board.rooms)
          if (r.devices.isNotEmpty && !skipRooms.contains(r.name)) r,
      ];
      if (rooms.isEmpty) continue;
      final id = await _dashboards.create(
        connectionId: connectionId,
        name: board.floor ?? (floored ? otherRoomsName : homeName),
        topicPrefix: base,
        colorSeed: defaultDashboardSeed,
        iconCodepoint: 0xe318, // Icons.home, as setup's first dashboard
      );
      ids.add(id);
      var order = 0;
      var sectionOrder = 0;
      for (final room in rooms) {
        final sectionId = await _sections.create(
          dashboardId: id,
          name: room.name ?? noRoomName,
          sortOrder: sectionOrder++,
        );
        for (final d in room.devices) {
          await createDeviceTile(
            _panels,
            dashboardId: id,
            base: base,
            device: d.device,
            name: d.name,
            sectionId: sectionId,
            sortOrder: order++,
          );
          tiles++;
        }
      }
    }
    return HaImportResult(renamed: renamed, dashboardIds: ids, tiles: tiles);
  }

  /// Device tiles still named after their device take the Home Assistant
  /// name, by the rule that follows renames in Zigbee2MQTT: the device's
  /// name now, or the one the tile was made with (its topic still carries
  /// it), raw or readable. Reading tiles keep their own names:
  /// "Temperature" is not the device.
  Future<int> _rename(String connectionId, ImportPlan plan, String base) async {
    final named = {
      for (final b in plan.dashboards)
        for (final r in b.rooms)
          for (final d in r.devices)
            if (d.device.ieeeAddress != null)
              d.device.ieeeAddress!.toLowerCase(): d,
    };
    var renamed = 0;
    for (final (tile, _) in await _registry.tilesOfHome(connectionId)) {
      final d = named[tile.deviceIeee?.toLowerCase()];
      if (d == null || tile.type != PanelType.device) continue;
      final own = d.device;
      final prefix = tile.topicPrefixOverride;
      final made = prefix != null && prefix.startsWith('$base/')
          ? prefix.substring(base.length + 1)
          : null;
      final still = {
        own.friendlyName,
        own.displayName,
        if (made != null) made,
        if (made != null) own.displayNameOf(made),
      }.contains(tile.name);
      if (!still || tile.name == d.name) continue;
      await _registry.setName(tile.id, d.name);
      renamed++;
    }
    return renamed;
  }
}
