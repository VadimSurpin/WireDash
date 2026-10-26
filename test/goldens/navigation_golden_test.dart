import 'dart:async';

import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiredash/data/database/database.dart';
import 'package:wiredash/data/database/tables/connections.dart';
import 'package:wiredash/data/repositories/connection_repo.dart';
import 'package:wiredash/data/repositories/dashboard_repo.dart';
import 'package:wiredash/data/repositories/panel_repo.dart';
import 'package:wiredash/data/repositories/section_repo.dart';
import 'package:wiredash/features/devices/device_health.dart';
import 'package:wiredash/features/devices/device_registry.dart';
import 'package:wiredash/features/devices/devices_providers.dart';
import 'package:wiredash/features/devices/z2m_bridge.dart';
import 'package:wiredash/features/devices/screens/devices_screen.dart';
import 'package:wiredash/features/discovery/models/z2m_device.dart';
import 'package:wiredash/features/discovery/providers/discovery_provider.dart';
import 'package:wiredash/features/home/home_shell.dart';
import 'package:wiredash/features/panels/screens/add_tile_screen.dart';
import 'package:wiredash/features/settings/providers/settings_controller.dart';

import 'package:wiredash/mqtt/providers/mqtt_manager_provider.dart';

import 'package:wiredash/features/discovery/models/wirenboard_device.dart';
import 'package:wiredash/features/discovery/providers/wirenboard_discovery_provider.dart';
import 'package:wiredash/features/discovery/wirenboard_dashboard_importer.dart';
import 'golden_harness.dart';

// 1.12 navigation screens in the interim look: the home shell (header
// switcher, Devices dot), Add tile, and the Devices tab.

final _stamp = DateTime(2026, 9, 26);

Connection _home(String id, String name) => Connection(
  transport: ConnectionTransport.mqtt,
  id: id,
  name: name,
  host: 'h',
  port: 1883,
  protocol: MqttProtocol.tcp,
  keepAliveSeconds: 60,
  autoConnect: true,
  createdAt: _stamp,
  updatedAt: _stamp,
);

final _dashboard = Dashboard(
  id: 'd1',
  connectionId: 'c1',
  name: 'Home',
  topicPrefix: 'zigbee2mqtt',
  colorSeed: 0xFF3B82F6,
  iconCodepoint: 0xe318,
  locked: false,
  sortOrder: 0,
  createdAt: _stamp,
  updatedAt: _stamp,
);

Map<String, Object?> _feature(String type, String p) => {
  'type': type,
  'name': p,
  'property': p,
  'access': 7,
  if (type == 'binary') ...{'value_on': 'ON', 'value_off': 'OFF'},
};

final _devices = [
  Z2mDevice(
    friendlyName: '0xc4d7fdbbfeba0000',
    type: 'Router',
    vendor: 'Tuya',
    model: 'CK-BL702-AL-01',
    ieeeAddress: '0xc4d7fdbbfeba0000',
    rawExposes: [
      {
        'type': 'light',
        'features': [
          _feature('binary', 'state'),
          {
            'type': 'composite',
            'name': 'color_xy',
            'property': 'color',
            'access': 7,
          },
        ],
      },
    ],
  ),
  Z2mDevice(
    friendlyName: 'garden_relay',
    type: 'Router',
    vendor: 'SONOFF',
    model: 'MINI-ZBD',
    ieeeAddress: '0x6ce4a4fffe6d2f80',
    rawExposes: [
      {
        'type': 'switch',
        'features': [_feature('binary', 'state')],
      },
    ],
  ),
  const Z2mDevice(
    friendlyName: 'front_door',
    type: 'EndDevice',
    vendor: 'Aqara',
    model: 'MCCGQ11LM',
    ieeeAddress: '0x0001',
    rawExposes: [
      {'type': 'binary', 'name': 'contact', 'property': 'contact', 'access': 1},
    ],
  ),
];

late SharedPreferences _prefs;

final _wb = WirenBoardDiscovery()
  ..apply('/devices/wb-mr6_10/meta', '{"name":"Relay module"}')
  ..apply('/devices/wb-mr6_10/controls/K1/meta', '{"type":"switch"}')
  ..apply('/devices/garden_relay/controls/state/meta', '{"type":"switch"}')
  ..apply(
    '/devices/system__cloud/controls/status/meta',
    '{"type":"text","readonly":true}',
  );

List<Override> _overrides() => [
  wirenBoardDevicesProvider.overrideWith((ref, _) => Stream.value(_wb.devices)),
  linkedWirenBoardIdsProvider.overrideWith((ref, _) => {}),
  // The home shell holds the history recorder (2.9.1), off here.
  sharedPreferencesProvider.overrideWithValue(_prefs),
  // The shell's control tracker asks for the broker (2.9.2): none here.
  mqttManagerProvider.overrideWith((ref, _) => Completer<Never>().future),
  connectionsStreamProvider.overrideWith(
    (ref) => Stream.value([_home('c1', 'My Home'), _home('c2', 'SMHUB')]),
  ),
  unassignedCountProvider.overrideWith((ref, _) => const AsyncValue.data(1)),
  dashboardByIdProvider.overrideWith((ref, _) async => _dashboard),
  dashboardsForConnectionProvider.overrideWith(
    (ref, _) => Stream.value([_dashboard]),
  ),
  bridgeDevicesStreamProvider.overrideWith((ref, _) => Stream.value(_devices)),
  discoveredDevicesProvider.overrideWith((ref, _) async => _devices),
  linkedIeeesProvider.overrideWith(
    (ref, _) => Stream.value({'0x6ce4a4fffe6d2f80'}),
  ),
  deviceHealthProvider.overrideWith(
    (ref, _) => Stream.value(
      deviceHealthFrom(
        _devices,
        states: {
          '0xc4d7fdbbfeba0000': (
            payload: '{"state":"ON","brightness":180,"linkquality":68}',
            at: DateTime(2026, 9, 26),
          ),
          'garden_relay': (
            payload: '{"state":"OFF","linkquality":76}',
            at: DateTime(2026, 9, 26),
          ),
          'front_door': (
            payload: '{"contact":true,"battery":91,"linkquality":120}',
            at: DateTime(2026, 9, 26),
          ),
        },
      ),
    ),
  ),
  availabilityConfigProvider.overrideWith(
    (ref, _) => Stream.value(AvailabilityConfig.unknown),
  ),
  batteryAlertsProvider.overrideWith((ref, _) => Stream.value(const {})),
  batteryWatchProvider.overrideWith((ref, _) {}),
  unassignedDevicesProvider.overrideWith((ref, _) => const AsyncValue.data([])),
  sectionsForDashboardProvider.overrideWith(
    (ref, _) => Stream.value(const <Section>[]),
  ),
  panelsForDashboardProvider.overrideWith(
    (ref, _) => Stream.value(const <Panel>[]),
  ),
];

Widget _shell(Widget body) => HomeShell(
  connectionId: 'c1',
  location: '/connections/c1/devices',
  child: body,
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  goldenTest(
    'devices tab in the home shell',
    fileName: 'devices_tab_phone',
    pumpBeforeTest: pumpNTimes(10, const Duration(milliseconds: 50)),
    builder: () => goldenMatrix(
      variants: phoneMatrix.take(5).toList(),
      overrides: _overrides,
      screen: () => _shell(const DevicesScreen(connectionId: 'c1')),
    ),
  );

  goldenTest(
    'add tile',
    fileName: 'add_tile_phone',
    pumpBeforeTest: pumpNTimes(10, const Duration(milliseconds: 50)),
    builder: () => goldenMatrix(
      variants: phoneMatrix.take(5).toList(),
      overrides: _overrides,
      screen: () => AddTileScreen(
        connectionId: 'c1',
        dashboardId: 'd1',
        onCustomTile: (_) {},
      ),
    ),
  );
}
