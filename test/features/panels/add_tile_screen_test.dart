import 'dart:async';
import 'package:wiredash/features/devices/device_health.dart';
import 'package:wiredash/features/devices/z2m_bridge.dart';
import 'package:wiredash/features/discovery/providers/wirenboard_discovery_provider.dart';
import 'package:wiredash/features/discovery/wirenboard_dashboard_importer.dart';
import 'package:wiredash/mqtt/providers/mqtt_manager_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/data/database/daos/dashboard_dao.dart';
import 'package:wiredash/data/database/daos/panel_dao.dart';
import 'package:wiredash/core/theme/dashboard_accent.dart';
import 'package:wiredash/features/devices/devices_providers.dart';
import 'package:wiredash/features/devices/device_profile.dart';
import 'package:wiredash/data/database/database.dart';
import 'package:wiredash/data/database/tables/connections.dart';
import 'package:wiredash/data/database/tables/panels.dart';
import 'package:wiredash/data/repositories/dashboard_repo.dart';
import 'package:wiredash/data/repositories/panel_repo.dart';
import 'package:wiredash/data/repositories/section_repo.dart';
import 'package:wiredash/features/devices/device_registry.dart';
import 'package:wiredash/features/discovery/models/z2m_device.dart';
import 'package:wiredash/features/discovery/providers/discovery_provider.dart';
import 'package:wiredash/features/panels/models/panel_config.dart';
import 'package:wiredash/features/panels/screens/add_tile_screen.dart';
import 'package:wiredash/l10n/app_localizations.dart';

class _Recording extends PanelRepo {
  _Recording(super.dao);
  final created = <Map<String, Object?>>[];

  @override
  Future<String> create({
    required String dashboardId,
    required String name,
    required PanelType type,
    required String topic,
    String? subscribeTopic,
    String? topicPrefixOverride,
    int qos = 1,
    bool retain = false,
    PanelWidth width = PanelWidth.small,
    int sortOrder = 0,
    String? sectionId,
    String? deviceIeee,
    required PanelConfig config,
  }) async {
    created.add({
      'name': name,
      'type': type,
      'prefix': topicPrefixOverride,
      'width': width,
      'sortOrder': sortOrder,
      'section': sectionId,
      'ieee': deviceIeee,
    });
    return 'new';
  }
}

final _stamp = DateTime(2026, 9, 26);
const _light = [
  {
    'type': 'light',
    'features': [
      {'type': 'binary', 'name': 'state', 'property': 'state', 'access': 7},
    ],
  },
];

Z2mDevice _dev(String name, String ieee, {String? model}) => Z2mDevice(
  friendlyName: name,
  type: 'Router',
  vendor: model == null ? null : 'Tuya',
  model: model,
  ieeeAddress: ieee,
  rawExposes: _light,
);

void main() {
  late AppDatabase db;
  late _Recording repo;
  setUp(() {
    db = AppDatabase.test(NativeDatabase.memory());
    repo = _Recording(PanelDao(db));
  });
  tearDown(() => db.close());

  Widget app(
    List<Z2mDevice> devices, {
    Set<String> linked = const {},
    String? prefix = 'zigbee2mqtt',
  }) => ProviderScope(
    overrides: [
      panelRepoProvider.overrideWithValue(repo),
      mqttManagerProvider.overrideWith((ref, _) => Completer<Never>().future),
      deviceHealthProvider.overrideWith(
        (ref, args) => Stream.value(deviceHealthFrom(devices)),
      ),
      availabilityConfigProvider.overrideWith(
        (ref, _) => Stream.value(AvailabilityConfig.unknown),
      ),
      baseTopicOverrideProvider.overrideWith((ref, _) => null),
      wirenBoardDevicesProvider.overrideWith(
        (ref, _) => Stream.value(const []),
      ),
      linkedWirenBoardIdsProvider.overrideWith((ref, _) => {}),
      unassignedDevicesProvider.overrideWith(
        (ref, _) => AsyncValue.data(
          devices.where((d) => !linked.contains(d.ieeeAddress)).toList(),
        ),
      ),
      dashboardByIdProvider.overrideWith(
        (ref, _) async => Dashboard(
          id: 'd1',
          connectionId: 'c1',
          name: 'Home',
          topicPrefix: prefix,
          colorSeed: 0,
          iconCodepoint: 0,
          locked: false,
          sortOrder: 0,
          createdAt: _stamp,
          updatedAt: _stamp,
        ),
      ),
      dashboardsForConnectionProvider.overrideWith(
        (ref, _) => Stream.value([
          Dashboard(
            id: 'd1',
            connectionId: 'c1',
            name: 'Home',
            topicPrefix: prefix,
            colorSeed: 0,
            iconCodepoint: 0,
            locked: false,
            sortOrder: 0,
            createdAt: _stamp,
            updatedAt: _stamp,
          ),
        ]),
      ),
      bridgeDevicesStreamProvider.overrideWith(
        (ref, args) => Stream.value(args.base == 'zigbee2mqtt' ? devices : []),
      ),
      linkedIeeesProvider.overrideWith((ref, _) => Stream.value(linked)),
      sectionsForDashboardProvider.overrideWith(
        (ref, _) => Stream.value([
          Section(
            id: 's1',
            dashboardId: 'd1',
            name: 'Lights',
            sortOrder: 0,
            createdAt: _stamp,
            updatedAt: _stamp,
          ),
        ]),
      ),
      panelsForDashboardProvider.overrideWith(
        (ref, _) => Stream.value(const <Panel>[]),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AddTileScreen(
        connectionId: 'c1',
        dashboardId: 'd1',
        onCustomTile: (_) {},
      ),
    ),
  );

  testWidgets('full device category starts collapsed; custom stays below', (
    tester,
  ) async {
    await tester.pumpWidget(
      app([_dev('desk_lamp', '0x1'), _dev('hall', '0x2')], linked: {'0x1'}),
    );
    await tester.pumpAndSettle();
    expect(find.text('hall'), findsNothing);
    expect(find.text('desk_lamp'), findsNothing);
    expect(find.text('Wiren Board'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('devices-section:z2m')));
    await tester.pumpAndSettle();
    expect(find.text('hall'), findsOneWidget);
    expect(find.text('desk_lamp'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Custom MQTT tile'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Custom MQTT tile'), findsOneWidget);
  });

  testWidgets(
    'a dashboard with no topic prefix still lists Zigbee2MQTT devices',
    (tester) async {
      await tester.pumpWidget(app([_dev('hall', '0x2')], prefix: null));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('devices-section:z2m')));
      await tester.pumpAndSettle();
      expect(find.text('hall'), findsWidgets);
    },
  );

  testWidgets('adding a device creates its tile in the matching section', (
    tester,
  ) async {
    await tester.pumpWidget(
      app([
        _dev(
          '0xc4d7fdbbfeba0000',
          '0xc4d7fdbbfeba0000',
          model: 'CK-BL702-AL-01',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('devices-section:z2m')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('0xc4d7fdbbfeba0000').first);
    await tester.pumpAndSettle();
    // An IEEE address is not offered as the name.
    expect(find.text('e.g. Tuya CK-BL702-AL-01'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Desk lamp');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(repo.created.single, {
      'name': 'Desk lamp',
      'type': PanelType.device,
      'prefix': 'zigbee2mqtt/0xc4d7fdbbfeba0000',
      'width': PanelWidth.small,
      'sortOrder': 0,
      'section': 's1',
      'ieee': '0xc4d7fdbbfeba0000',
    });
  });

  testWidgets(
    'adding to a home with no dashboard creates one instead of a dead end',
    (tester) async {
      await db
          .into(db.connections)
          .insert(
            ConnectionsCompanion.insert(
              id: 'c1',
              name: 'localhost',
              host: 'localhost',
              port: 1883,
              protocol: MqttProtocol.tcp,
              createdAt: _stamp,
              updatedAt: _stamp,
            ),
          );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            panelRepoProvider.overrideWithValue(repo),
            dashboardRepoProvider.overrideWithValue(
              DashboardRepo(DashboardDao(db)),
            ),
            dashboardsForConnectionProvider.overrideWith(
              (ref, _) => Stream.value(const <Dashboard>[]),
            ),
            baseTopicOverrideProvider.overrideWith((ref, _) => null),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: AddDeviceSheet(
                connectionId: 'c1',
                device: _dev('living_light', '0x1'),
                deviceClass: DeviceClass.light,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final add = find.widgetWithText(FilledButton, 'Add');
      expect(tester.widget<FilledButton>(add).onPressed, isNotNull);
      await tester.tap(add);
      await tester.pumpAndSettle();

      final dash = await db.select(db.dashboards).getSingle();
      expect(
        (dash.connectionId, dash.name, dash.colorSeed),
        ('c1', 'Home', defaultDashboardSeed),
      );
      expect(repo.created.single['prefix'], 'zigbee2mqtt/living_light');
    },
  );
}
