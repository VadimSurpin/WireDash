import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/data/database/daos/panel_dao.dart';
import 'package:wiredash/data/database/daos/section_dao.dart';
import 'package:wiredash/data/database/database.dart';
import 'package:wiredash/data/database/tables/connections.dart';
import 'package:wiredash/data/database/tables/panels.dart';
import 'package:wiredash/data/repositories/panel_repo.dart';
import 'package:wiredash/data/repositories/section_repo.dart';
import 'package:wiredash/features/dashboards/section_placement.dart';
import 'package:wiredash/features/panels/models/panel_config.dart';

// A tile added from the Scenes tab or a device page lands in a section
// (2.4.1), not unsectioned at the top of the dashboard.

void main() {
  late AppDatabase db;
  late PanelRepo panels;
  late SectionRepo sections;
  final t = DateTime(2026, 10, 11);

  setUp(() async {
    db = AppDatabase.test(NativeDatabase.memory());
    panels = PanelRepo(PanelDao(db));
    sections = SectionRepo(SectionDao(db));
    await db.into(db.connections).insert(ConnectionsCompanion.insert(
        id: 'c1', name: 'Home', host: 'h', port: 1883,
        protocol: MqttProtocol.tcp, createdAt: t, updatedAt: t));
    await db.into(db.dashboards).insert(DashboardsCompanion.insert(
        id: 'd1', connectionId: 'c1', name: 'Home', colorSeed: 0,
        iconCodepoint: 0, createdAt: t, updatedAt: t));
  });
  tearDown(() => db.close());

  Future<void> section(String id, String name, int sort) =>
      db.into(db.sections).insert(SectionsCompanion.insert(
          id: id, dashboardId: 'd1', name: name, sortOrder: Value(sort),
          createdAt: t, updatedAt: t));

  Future<void> tile(String id, {String? sectionId, String? ieee}) =>
      db.into(db.panels).insert(PanelsCompanion.insert(
          id: id, dashboardId: 'd1', name: id, type: PanelType.device,
          topic: 'set', width: PanelWidth.small,
          config: const ToggleConfig().encode(),
          sectionId: Value(sectionId), deviceIeee: Value(ieee),
          createdAt: t, updatedAt: t));

  test('a dashboard without sections: nowhere, after every tile', () async {
    await tile('a');
    await tile('b');
    final place = await placeAddedTile(panels, sections, 'd1');
    expect(place.sectionId, isNull);
    expect(place.sortOrder, 2);
  });

  test('the last section by order, not by creation', () async {
    await section('s2', 'Sensors', 1);
    await section('s1', 'Lights', 0);
    final place = await placeAddedTile(panels, sections, 'd1');
    expect(place.sectionId, 's2');
    expect(place.sortOrder, 0);
  });

  test("the device's own section wins when its tile is on the dashboard",
      () async {
    await section('s1', 'Lights', 0);
    await section('s2', 'Sensors', 1);
    await tile('bulb', sectionId: 's1', ieee: '0x01');
    await tile('door', sectionId: 's2', ieee: '0x02');
    final place =
        await placeAddedTile(panels, sections, 'd1', deviceIeee: '0x01');
    expect(place.sectionId, 's1');
    expect(place.sortOrder, 2);
    final other =
        await placeAddedTile(panels, sections, 'd1', deviceIeee: '0x99');
    expect(other.sectionId, 's2', reason: 'unknown device: last section');
  });
}
