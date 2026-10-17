import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zigdash/core/analytics/analytics.dart';
import 'package:zigdash/data/database/tables/connections.dart';
import 'package:zigdash/features/devices/control_tracker.dart';
import 'package:zigdash/features/devices/devices_providers.dart';
import 'package:zigdash/features/discovery/models/z2m_device.dart';
import 'package:zigdash/features/discovery/providers/discovery_provider.dart';
import 'package:zigdash/features/settings/providers/settings_controller.dart';
import 'package:zigdash/mqtt/broker_config.dart';
import 'package:zigdash/mqtt/mqtt_manager.dart';
import 'package:zigdash/mqtt/providers/mqtt_manager_provider.dart';

class _Sink implements AnalyticsSink {
  final sent = <Map<String, String>>[];
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  void send(String name, Map<String, String> props) =>
      sent.add({'name': name, ...props});
}

class _Manager extends MqttManager {
  _Manager()
    : super(
        config: const BrokerConfig(
          id: 'c1',
          host: 'h',
          port: 1883,
          protocol: MqttProtocol.tcp,
        ),
        password: '',
      );

  final commands = StreamController<String>.broadcast();

  @override
  Stream<String> get commandsSent => commands.stream;
}

final _devices = parseBridgeDevices(
  jsonEncode([
    {
      'friendly_name': 'Desk lamp',
      'ieee_address': '0x01',
      'type': 'Router',
      'supported': true,
      'definition': {
        'exposes': [
          {
            'type': 'light',
            'features': [
              {
                'type': 'binary',
                'name': 'state',
                'property': 'state',
                'access': 7,
                'value_on': 'ON',
                'value_off': 'OFF',
              },
            ],
          },
        ],
      },
    },
  ]),
);

void main() {
  test('which topics are commands to a device', () {
    expect(
      commandTarget('zigbee2mqtt/Desk lamp/set', 'zigbee2mqtt'),
      'Desk lamp',
    );
    expect(
      commandTarget('zigbee2mqtt/Desk lamp/set/brightness', 'zigbee2mqtt'),
      'Desk lamp',
    );
    expect(
      commandTarget('zigbee2mqtt/bridge/request/permit_join', 'zigbee2mqtt'),
      isNull,
    );
    expect(commandTarget('home/custom/topic', 'zigbee2mqtt'), isNull);
    expect(commandTarget('zigbee2mqtt/Desk lamp', 'zigbee2mqtt'), isNull);
  });

  testWidgets('the first command sends the kind of device, once', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'analytics_consent': true});
    final prefs = await SharedPreferences.getInstance();
    final sink = _Sink();
    final mgr = _Manager();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          analyticsSinkProvider.overrideWithValue(sink),
          analyticsAvailableProvider.overrideWithValue(true),
          mqttManagerProvider.overrideWith((ref, _) async => mgr),
          homeBaseTopicProvider.overrideWith((ref, _) => 'zigbee2mqtt'),
          bridgeDevicesStreamProvider.overrideWith(
            (ref, _) => Stream.value(_devices),
          ),
        ],
        child: const ControlTracker(connectionId: 'c1'),
      ),
    );
    await tester.pump();
    await tester.pump();

    mgr.commands.add('zigbee2mqtt/bridge/request/permit_join');
    await tester.pump();
    expect(sink.sent.where((e) => e['feature'] == 'control'), isEmpty);

    mgr.commands.add('zigbee2mqtt/Desk lamp/set');
    mgr.commands.add('zigbee2mqtt/Desk lamp/set');
    await tester.pump();
    expect(sink.sent.where((e) => e['feature'] == 'control').toList(), [
      {'name': 'feature_used', 'feature': 'control', 'tile': 'light'},
    ]);
  });
}
