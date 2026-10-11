import '../../data/repositories/panel_repo.dart';
import '../../data/repositories/section_repo.dart';

/// Where a tile added from outside the dashboard (the Scenes tab, a device
/// page) goes, so it doesn't land unsectioned at the top: the section of
/// the device's own tile when [deviceIeee] is on this dashboard, else the
/// dashboard's last section, else nowhere (a dashboard without sections).
/// The sort order puts it after every tile.
Future<({String? sectionId, int sortOrder})> placeAddedTile(
  PanelRepo panels,
  SectionRepo sections,
  String dashboardId, {
  String? deviceIeee,
}) async {
  final existing = await panels.getByDashboard(dashboardId);
  String? sectionId;
  if (deviceIeee != null) {
    for (final p in existing) {
      if (p.deviceIeee == deviceIeee && p.sectionId != null) {
        sectionId = p.sectionId;
        break;
      }
    }
  }
  if (sectionId == null) {
    final all = await sections.getByDashboard(dashboardId);
    if (all.isNotEmpty) {
      sectionId = (all.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
          .last
          .id;
    }
  }
  return (sectionId: sectionId, sortOrder: existing.length);
}
