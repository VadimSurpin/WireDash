import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart' as mc;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zigdash/data/database/tables/connections.dart';
import 'package:zigdash/features/history/app_history_recorder.dart';
import 'package:zigdash/features/history/history_config.dart';
import 'package:zigdash/features/history/history_service.dart';
import 'package:zigdash/features/settings/providers/settings_controller.dart';
import 'package:zigdash/mqtt/broker_config.dart';
import 'package:zigdash/mqtt/mqtt_manager.dart';
import 'package:zigdash/mqtt/providers/mqtt_manager_provider.dart';

/// A broker in memory: subscriptions by exact topic or `+` pattern.
class _Broker extends MqttManager {
  _Broker()
    : super(
        config: const BrokerConfig(
          id: 'c1',
          host: 'localhost',
          port: 1883,
          protocol: MqttProtocol.tcp,
        ),
        password: '',
      );

  final published = <String, String>{};
  final _streams = <String, StreamController<MqttRxMessage>>{};

  @override
  bool get isConnected => true;

  @override
  Stream<MqttRxMessage> subscribe(String pattern) =>
      (_streams[pattern] ??= StreamController<MqttRxMessage>.broadcast())
          .stream;

  @override
  void unsubscribe(String pattern) {}

  @override
  void publish(
    String topic,
    String template,
    Object value, {
    mc.MqttQos qos = mc.MqttQos.atLeastOnce,
    bool retain = false,
  }) => published[topic] = template;

  void send(String topic, String payload) {
    for (final e in _streams.entries) {
      final p = e.key.split('/'), t = topic.split('/');
      final match =
          p.length == t.length &&
          [
            for (var i = 0; i < p.length; i++) p[i] == '+' || p[i] == t[i],
          ].every((x) => x);
      if (match) {
        e.value.add(
          MqttRxMessage(
            topic: topic,
            payload: payload,
            receivedAt: DateTime(2026),
            connectionGeneration: 0,
          ),
        );
      }
    }
  }
}

void main() {
  late _Broker broker;
  late DateTime now;

  final config = encodeHistoryConfig(
    home: 'Home',
    base: 'zigbee2mqtt',
    timeZone: 'UTC',
    readings: const [
      HistoryReading(
        ieee: '0xa1',
        path: 'temperature',
        topic: 'zigbee2mqtt/Living room',
        unit: '°C',
      ),
    ],
  );

  Future<void> pump(WidgetTester tester, {required bool on}) async {
    SharedPreferences.setMockInitialValues({
      if (on) 'history_record_here_c1': true,
    });
    final prefs = await SharedPreferences.getInstance();
    broker = _Broker();
    now = DateTime(2026, 10, 17, 10, 1);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mqttManagerProvider.overrideWith((ref, _) async => broker),
          historyRetainedConfigProvider.overrideWith(
            (ref, _) => Stream.value(config),
          ),
          historyRecorderNowProvider.overrideWithValue(() => now),
        ],
        child: const AppHistoryRecorder(connectionId: 'c1'),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('off: records nothing and says nothing', (tester) async {
    await pump(tester, on: false);
    broker.send('zigbee2mqtt/Living room', '{"temperature": 21}');
    await tester.pump(const Duration(minutes: 20));
    expect(broker.published, isEmpty);
  });

  testWidgets('on: the heartbeat, then day records as slots close', (
    tester,
  ) async {
    await pump(tester, on: true);
    expect(broker.published[historyBridgeTopic], 'online');

    broker.send('zigbee2mqtt/Living room', '{"temperature": 21}');
    now = DateTime(2026, 10, 17, 10, 7);
    broker.send('zigbee2mqtt/Living room', '{"temperature": 22}');
    await tester.pump();

    now = DateTime(2026, 10, 17, 10, 16);
    await tester.pump(const Duration(minutes: 1));
    final record =
        broker.published['zigdash/history/0xa1/temperature/2026-10-17'];
    expect(record, isNotNull);
    expect((jsonDecode(record!) as Map)['b'], [
      [40, 21.5, 21.0, 22.0],
    ]);
    await tester.pumpWidget(const SizedBox());
  });
}
