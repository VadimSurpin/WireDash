// Generates an isolated demo database for the emulator screenshot workflow.
// Run with: flutter test tool/car_preview/create_fixture.dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/data/database/database.dart';
import 'package:wiredash/data/database/tables/connections.dart';
import 'package:wiredash/data/database/tables/panels.dart';
import 'package:wiredash/features/panels/models/panel_config.dart';

void main() {
  test('generate emulator-only dashboard fixture', () async {
    final file = File('build/car-preview/zigdash.sqlite');
    await file.parent.create(recursive: true);
    if (await file.exists()) await file.delete();
    final db = AppDatabase.test(NativeDatabase(file));
    final now = DateTime.utc(2026, 10, 26);
    await db
        .into(db.connections)
        .insert(
          ConnectionsCompanion.insert(
            id: 'preview',
            name: 'Preview home',
            host: '10.0.2.2',
            port: 18884,
            protocol: MqttProtocol.tcp,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.dashboards)
        .insert(
          DashboardsCompanion.insert(
            id: 'preview',
            connectionId: 'preview',
            name: 'My home',
            colorSeed: 0xff2196f3,
            iconCodepoint: 0xe88a,
            createdAt: now,
            updatedAt: now,
          ),
        );
    for (final section in ['Gates', 'Lighting', 'Auxiliary']) {
      await db
          .into(db.sections)
          .insert(
            SectionsCompanion.insert(
              id: section,
              dashboardId: 'preview',
              name: section,
              sortOrder: Value(
                ['Gates', 'Lighting', 'Auxiliary'].indexOf(section),
              ),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    var order = 0;
    Future<void> panel(
      String id,
      String name,
      String section,
      PanelType type,
      String topic,
      PanelConfig config, {
      String? subscribeTopic,
    }) async {
      await db
          .into(db.panels)
          .insert(
            PanelsCompanion.insert(
              id: id,
              dashboardId: 'preview',
              name: name,
              sectionId: Value(section),
              type: type,
              topic: topic,
              subscribeTopic: Value(subscribeTopic),
              config: config.encode(),
              sortOrder: Value(order++),
              width: type == PanelType.cover
                  ? PanelWidth.wide
                  : PanelWidth.small,
              createdAt: now,
              updatedAt: now,
            ),
          );
    }

    await panel(
      'gate',
      'Driveway gate',
      'Gates',
      PanelType.cover,
      '',
      const CoverConfig(
        wirenBoard: WirenBoardCoverBinding(deviceId: 'preview', number: 1),
        waitForFeedback: false,
        openButton: CoverButtonConfig(
          title: 'Enter',
          icon: CoverButtonIcon.gatePartial,
        ),
        closeButton: CoverButtonConfig(
          title: 'Exit',
          icon: CoverButtonIcon.gateClosed,
        ),
        stopButton: CoverButtonConfig(visible: false),
      ),
    );
    await panel(
      'garage',
      'Garage door',
      'Gates',
      PanelType.cover,
      '',
      const CoverConfig(
        wirenBoard: WirenBoardCoverBinding(deviceId: 'preview', number: 2),
        waitForFeedback: false,
        openButton: CoverButtonConfig(
          title: 'Open',
          icon: CoverButtonIcon.rollerOpen,
        ),
        closeButton: CoverButtonConfig(
          title: 'Close',
          icon: CoverButtonIcon.rollerClosed,
        ),
        stopButton: CoverButtonConfig(visible: false),
      ),
    );
    for (final item in [
      ('K1', 'Driveway light'),
      ('K2', 'Porch light'),
      ('K3', 'Garage light'),
      ('K4', 'Garden light'),
    ]) {
      await panel(
        item.$1,
        item.$2,
        'Lighting',
        PanelType.toggle,
        '/devices/preview/controls/${item.$1}/on',
        const ToggleConfig(
          jsonPath: null,
          onMatch: '1',
          onPayload: '1',
          offPayload: '0',
        ),
        subscribeTopic: '/devices/preview/controls/${item.$1}',
      );
    }
    for (final item in [
      'Garden pump',
      'Ventilation',
      'Doorbell',
      'Sprinklers',
      'All lights',
      'Evening',
    ]) {
      await panel(
        item,
        item,
        'Auxiliary',
        PanelType.button,
        '/preview/$item',
        const ButtonConfig(
          payload: '1',
          iconCodepoint: 0xe8b8,
          colorArgb: 0xff42a5f5,
        ),
      );
    }
    await db.close();
    expect(file.lengthSync(), greaterThan(0));
  });
}
