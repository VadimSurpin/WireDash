import 'dart:async';
import 'package:zigdash/features/discovery/models/wirenboard_device.dart';
import 'package:zigdash/mqtt/providers/mqtt_manager_provider.dart';
import 'package:zigdash/features/discovery/providers/wirenboard_discovery_provider.dart';
import 'package:zigdash/features/discovery/wirenboard_dashboard_importer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/data/database/database.dart';
import 'package:zigdash/data/database/tables/panels.dart';
import 'package:zigdash/data/repositories/connection_repo.dart';
import 'package:zigdash/data/repositories/dashboard_repo.dart';
import 'package:zigdash/data/repositories/panel_repo.dart';
import 'package:zigdash/data/repositories/section_repo.dart';
import 'package:zigdash/features/devices/device_health.dart';
import 'package:zigdash/features/devices/device_registry.dart';
import 'package:zigdash/features/devices/devices_providers.dart';
import 'package:zigdash/features/devices/screens/devices_screen.dart';
import 'package:zigdash/features/discovery/models/z2m_device.dart';
import 'package:zigdash/features/devices/z2m_bridge.dart';
import 'package:zigdash/features/discovery/providers/discovery_provider.dart';
import 'package:zigdash/l10n/app_localizations.dart';

final _stamp = DateTime(2026, 9, 26);
const _light = [
  {
    'type': 'light',
    'features': [
      {'type': 'binary', 'name': 'state', 'property': 'state', 'access': 7},
    ],
  },
];

const _door = [
  {'type': 'binary', 'name': 'contact', 'property': 'contact', 'access': 1},
  {'type': 'numeric', 'name': 'battery', 'property': 'battery', 'access': 1},
];

const _deskDevice = Z2mDevice(
  friendlyName: 'desk',
  type: 'Router',
  ieeeAddress: '0x1',
  rawExposes: _light,
);
const _hallDevice = Z2mDevice(
  friendlyName: 'hall',
  type: 'Router',
  vendor: 'Tuya',
  model: 'CK-BL702-AL-01',
  ieeeAddress: '0x2',
  rawExposes: _light,
);
const _doorDevice = Z2mDevice(
  friendlyName: 'back door',
  type: 'EndDevice',
  ieeeAddress: '0x3',
  rawExposes: _door,
);

class _RecordingWbImporter implements WirenBoardDashboardImporter {
  final calls = <({String label, List<String>? ids})>[];
  final widgetTypes = <PanelType?>[];
  final commandOverrides = <bool>[];
  final valueExpressions = <String?>[];
  @override
  Future<void> addDevice(
    WirenBoardDevice device, {
    required String label,
  }) async {
    calls.add((label: label, ids: null));
  }

  @override
  Future<void> addControl(
    WirenBoardDevice device,
    WirenBoardControl control, {
    required String label,
    PanelType? widgetType,
    bool allowCommands = false,
    String? valueExpression,
  }) async {
    calls.add((label: label, ids: [control.id]));
    widgetTypes.add(widgetType);
    commandOverrides.add(allowCommands);
    valueExpressions.add(valueExpression);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Dashboards implements DashboardRepo {
  @override
  Future<List<Dashboard>> getByConnection(String id) async => [
    Dashboard(
      id: 'd1',
      connectionId: 'c1',
      name: 'Home',
      topicPrefix: null,
      colorSeed: 0,
      iconCodepoint: 0,
      locked: false,
      sortOrder: 0,
      createdAt: _stamp,
      updatedAt: _stamp,
    ),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app({
  AvailabilityConfig availability = AvailabilityConfig.unknown,
  ValueChanged<String>? onSelect,
  List<WirenBoardDevice> wbDevices = const [],
  bool emptyZ2m = false,
  List<Override> overrides = const [],
}) {
  final rows = deviceHealthFrom(
    [_deskDevice, _hallDevice, _doorDevice],
    states: {
      'desk': (payload: '{"state":"ON","linkquality":80}', at: _stamp),
      'hall': (payload: '{"state":"OFF","linkquality":60}', at: _stamp),
      'back door': (
        payload: '{"contact":true,"battery":8,"linkquality":90}',
        at: _stamp,
      ),
    },
  );
  return ProviderScope(
    overrides: [
      ...overrides,
      mqttManagerProvider.overrideWith((ref, _) => Completer<Never>().future),
      wirenBoardDevicesProvider.overrideWith(
        (ref, _) => Stream.value(wbDevices),
      ),
      linkedWirenBoardIdsProvider.overrideWith((ref, _) => {}),
      connectionsStreamProvider.overrideWith((ref) => Stream.value(const [])),
      dashboardsForConnectionProvider.overrideWith(
        (ref, _) => Stream.value([
          Dashboard(
            id: 'd1',
            connectionId: 'c1',
            name: 'Home',
            topicPrefix: 'zigbee2mqtt',
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
        (ref, _) => Stream.value([_deskDevice, _hallDevice, _doorDevice]),
      ),
      deviceHealthProvider.overrideWith(
        (ref, _) => emptyZ2m ? const Stream.empty() : Stream.value(rows),
      ),
      availabilityConfigProvider.overrideWith(
        (ref, _) => Stream.value(availability),
      ),
      linkedIeeesProvider.overrideWith(
        (ref, _) => Stream.value({'0x1', '0x3'}),
      ),
      unassignedDevicesProvider.overrideWith(
        (ref, _) => const AsyncValue.data([_hallDevice]),
      ),
      sectionsForDashboardProvider.overrideWith(
        (ref, _) => Stream.value(const <Section>[]),
      ),
      panelsForDashboardProvider.overrideWith(
        (ref, _) => Stream.value(const <Panel>[]),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DevicesScreen(connectionId: 'c1', onSelect: onSelect),
    ),
  );
}

/// The Devices tab for a home with no devices; [missing] says whether
/// Zigbee2MQTT's device list never arrived.
Widget _emptyApp({required bool missing}) => ProviderScope(
  overrides: [
    wirenBoardDevicesProvider.overrideWith((ref, _) => Stream.value([])),
    linkedWirenBoardIdsProvider.overrideWith((ref, _) => {}),
    connectionsStreamProvider.overrideWith((ref) => Stream.value(const [])),
    bridgeDevicesMissingProvider.overrideWith((ref, _) async => missing),
    deviceHealthProvider.overrideWith(
      (ref, _) => Stream.value(const <DeviceHealth>[]),
    ),
    availabilityConfigProvider.overrideWith(
      (ref, _) => Stream.value(AvailabilityConfig.unknown),
    ),
    linkedIeeesProvider.overrideWith(
      (ref, _) => Stream.value(const <String>{}),
    ),
    unassignedDevicesProvider.overrideWith(
      (ref, _) => const AsyncValue.data(<Z2mDevice>[]),
    ),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const DevicesScreen(connectionId: 'c1'),
  ),
);

void main() {
  testWidgets(
    'WB native mirrors and controller services have separate sections',
    (tester) async {
      final discovery = WirenBoardDiscovery()
        ..apply('/devices/desk/controls/state/meta', '{"type":"switch"}')
        ..apply('/devices/wb-mr6_10/controls/Relay/meta', '{"type":"switch"}')
        ..apply(
          '/devices/system__cloud/controls/status/meta',
          '{"type":"text","readonly":true}',
        );
      await tester.pumpWidget(
        _app(wbDevices: discovery.devices, emptyZ2m: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('Added modules'), findsOneWidget);
      expect(find.text('Wirenboard Z2M devices'), findsOneWidget);
      expect(find.text('Controller built-ins'), findsOneWidget);
      expect(find.byKey(const ValueKey('wb-device:desk')), findsNothing);
      expect(
        find.byKey(const ValueKey('wb-device:system__cloud')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('wb-device:wb-mr6_10')), findsOneWidget);
      await tester.tap(find.text('Wirenboard Z2M devices'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wb-device:desk')), findsOneWidget);
      await tester.tap(find.text('Controller built-ins'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('wb-device:system__cloud')),
        findsOneWidget,
      );
      await tester.tap(find.text('Added modules'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wb-device:wb-mr6_10')), findsNothing);
      expect(find.byKey(const ValueKey('wb-device:desk')), findsOneWidget);
    },
  );

  testWidgets(
    'single property add asks for a label and never offers subset selection',
    (tester) async {
      final device =
          (WirenBoardDiscovery()
                ..apply('/devices/room/meta/name', 'Room sensor')
                ..apply(
                  '/devices/room/controls/Temperature/meta',
                  '{"type":"temperature","readonly":true}',
                )
                ..apply(
                  '/devices/room/controls/Humidity/meta',
                  '{"type":"rel_humidity","readonly":true}',
                ))
              .devices
              .single;
      final importer = _RecordingWbImporter();
      await tester.pumpWidget(
        _app(
          wbDevices: [device],
          emptyZ2m: true,
          overrides: [
            dashboardRepoProvider.overrideWithValue(_Dashboards()),
            wirenBoardDashboardImporterProvider.overrideWith(
              (ref, _) => importer,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.tap(find.text('Room sensor'));
      await tester.pumpAndSettle();
      final temperature = find.byKey(
        const ValueKey('wb-property:room/Temperature'),
      );
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text('Add selected properties'), findsNothing);
      await tester.tap(
        find.descendant(of: temperature, matching: find.byIcon(Icons.add)),
      );
      await tester.pumpAndSettle();
      final label = find.widgetWithText(TextFormField, 'Name');
      await tester.enterText(label, '');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsOneWidget);
      expect(importer.calls, isEmpty);
      await tester.enterText(label, 'Hall weather');
      await tester.tap(find.byType(DropdownButtonFormField<PanelType>));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .text(lookupAppLocalizations(const Locale('en')).panelTypeProgress)
            .last,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(importer.calls, hasLength(1));
      expect(importer.calls.single.label, 'Hall weather');
      expect(importer.calls.single.ids, ['Temperature']);
      expect(importer.widgetTypes.single, PanelType.progress);
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(find.byTooltip('Add whole device'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'Whole room',
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(importer.calls, hasLength(2));
      expect(importer.calls.last, (label: 'Whole room', ids: null));
    },
  );

  for (final (id, controlId, type, selected, override) in [
    ('light', 'Color', 'rgb', PanelType.textInput, false),
    ('wb-mr6c_12', 'K1', 'switch', PanelType.toggle, false),
    ('wb-mr6c_99', 'K1', 'switch', PanelType.toggle, true),
  ]) {
    testWidgets(
      '$id/$controlId can switch from display back to editable input',
      (tester) async {
        final device =
            (WirenBoardDiscovery()
                  ..apply('/devices/$id/controls/$controlId/meta/readonly', '1')
                  ..apply(
                    '/devices/$id/controls/$controlId/meta',
                    '{"type":"$type","readonly":$override}',
                  ))
                .devices
                .single;
        final importer = _RecordingWbImporter();
        await tester.pumpWidget(
          _app(
            wbDevices: [device],
            emptyZ2m: true,
            overrides: [
              dashboardRepoProvider.overrideWithValue(_Dashboards()),
              wirenBoardDashboardImporterProvider.overrideWith(
                (ref, _) => importer,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(id));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byKey(ValueKey('wb-property:$id/$controlId')),
            matching: find.byIcon(Icons.add),
          ),
        );
        await tester.pumpAndSettle();
        final strings = lookupAppLocalizations(const Locale('en'));
        if (override) {
          expect(find.text(strings.panelTypeToggle), findsNothing);
          await tester.tap(find.text(strings.panelAllowCommands));
          await tester.pumpAndSettle();
        }
        for (final choice in [
          strings.panelTypeTextLog,
          selected == PanelType.toggle
              ? strings.panelTypeToggle
              : strings.panelTypeTextInput,
        ]) {
          await tester.tap(find.byType(DropdownButtonFormField<PanelType>));
          await tester.pumpAndSettle();
          await tester.tap(find.text(choice).last);
          await tester.pumpAndSettle();
        }
        if (override) {
          await tester.tap(find.text('Before display (JavaScript)'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('display-expression')),
            'Number(value) ? "Running" : "Stopped"',
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Add'));
        }
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Name'),
          'Custom label',
        );
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Add'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();
        expect(importer.calls.single.label, 'Custom label');
        expect(importer.calls.single.ids, [controlId]);
        expect(importer.widgetTypes.single, selected);
        expect(importer.commandOverrides.single, override);
        expect(
          importer.valueExpressions.single,
          override ? 'Number(value) ? "Running" : "Stopped"' : '',
        );
      },
    );
  }

  testWidgets(
    'All devices shows WB modules and built-ins while the Z2M list is missing',
    (tester) async {
      final devices =
          (WirenBoardDiscovery()
                ..apply('/devices/wb-mr6_10/meta/name', 'Relay module')
                ..apply(
                  '/devices/wb-mr6_10/controls/Relay 1/meta',
                  '{"type":"switch"}',
                )
                ..apply('/devices/hwmon/meta/name', 'Hardware monitor')
                ..apply(
                  '/devices/hwmon/controls/CPU/meta',
                  '{"type":"temperature","readonly":true}',
                ))
              .devices;
      await tester.pumpWidget(_app(wbDevices: devices, emptyZ2m: true));
      await tester.pumpAndSettle();
      expect(find.text('Relay module'), findsOneWidget);
      expect(find.text('Hardware monitor'), findsNothing);
      await tester.tap(find.text('Controller built-ins'));
      await tester.pumpAndSettle();
      expect(find.text('Hardware monitor'), findsOneWidget);
      expect(find.text('Added modules'), findsOneWidget);
      expect(find.text('Controller built-ins'), findsOneWidget);
      await tester.tap(find.text('Relay module'));
      await tester.pumpAndSettle();
      expect(find.text('Relay 1'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.tap(find.byTooltip('Open controls').first);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('native device section collapses and expands', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('desk'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('devices-section:z2m')));
    await tester.pumpAndSettle();
    expect(find.text('desk'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('devices-section:z2m')));
    await tester.pumpAndSettle();
    expect(find.text('desk'), findsOneWidget);
  });

  testWidgets(
    'search reveals collapsed built-ins and restores collapse when cleared',
    (tester) async {
      final discovery = WirenBoardDiscovery();
      for (var i = 0; i < 8; i++) {
        discovery.apply(
          '/devices/hwmon/controls/CPU $i/meta',
          '{"type":"temperature","readonly":true}',
        );
      }
      await tester.pumpWidget(
        _app(wbDevices: discovery.devices, emptyZ2m: true),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wb-device:hwmon')), findsNothing);
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'CPU 7');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('wb-property:hwmon/CPU 7')),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wb-device:hwmon')), findsNothing);
    },
  );

  testWidgets('no devices: says so plainly when the list arrived empty', (
    tester,
  ) async {
    await tester.pumpWidget(_emptyApp(missing: false));
    await tester.pumpAndSettle();
    expect(find.text('No devices found.'), findsOneWidget);
    expect(find.text('Restart Zigbee2MQTT'), findsNothing);
  });

  testWidgets('device list never arrived: explains it and offers a restart', (
    tester,
  ) async {
    await tester.pumpWidget(_emptyApp(missing: true));
    await tester.pumpAndSettle();
    expect(find.textContaining("hasn't sent its device list"), findsOneWidget);
    expect(find.text('Restart Zigbee2MQTT'), findsOneWidget);
    expect(find.text('No devices found.'), findsNothing);
  });

  testWidgets('attention first, with filter counts; unassigned marked', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Not on a dashboard'), findsOneWidget);
    expect(find.text('Needs attention · 1'), findsOneWidget);
    expect(find.text('Not on a dashboard · 1'), findsOneWidget);
    final names = tester
        .widgetList<DeviceHealthRow>(find.byType(DeviceHealthRow))
        .map((r) => r.health.friendlyName);
    expect(names, ['back door', 'desk', 'hall']);
    expect(find.byIcon(Icons.battery_alert), findsOneWidget);
  });

  testWidgets('availability off: no online/offline claims, one footnote', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.cloud_off), findsNothing);
    expect(find.text('How to turn it on'), findsOneWidget);
  });

  testWidgets('availability on: the footnote goes away', (tester) async {
    await tester.pumpWidget(
      _app(availability: const AvailabilityConfig(enabled: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('How to turn it on'), findsNothing);
  });

  testWidgets('filtering to Needs attention shows only those', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Needs attention · 1'));
    await tester.pumpAndSettle();
    expect(find.byType(DeviceHealthRow), findsOneWidget);
    expect(find.text('back door'), findsOneWidget);
  });

  testWidgets('tapping a device opens it', (tester) async {
    String? opened;
    await tester.pumpWidget(_app(onSelect: (ieee) => opened = ieee));
    await tester.pumpAndSettle();
    await tester.tap(find.text('hall'));
    expect(opened, '0x2');
  });

  testWidgets('long-press offers Add to a dashboard, and Dismiss when new', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.longPress(find.text('hall'));
    await tester.pumpAndSettle();
    expect(find.text('Add to a dashboard'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
  });
}
