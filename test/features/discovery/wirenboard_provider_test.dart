import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/data/database/tables/connections.dart';
import 'package:zigdash/features/discovery/providers/wirenboard_discovery_provider.dart';
import 'package:zigdash/mqtt/broker_config.dart';
import 'package:zigdash/mqtt/mqtt_manager.dart';
import 'package:zigdash/mqtt/providers/mqtt_manager_provider.dart';
import 'package:zigdash/mqtt/topic_matcher.dart';

class _Manager extends MqttManager {
  _Manager()
    : super(
        config: const BrokerConfig(
          id: 'c1',
          host: 'unused',
          port: 1883,
          protocol: MqttProtocol.tcp,
        ),
        password: '',
      );
  final incoming = StreamController<MqttRxMessage>.broadcast();
  final subscribed = <String>[];
  final released = <String>[];
  final cached = <MqttRxMessage>[];

  @override
  Stream<MqttRxMessage> subscribe(String pattern) {
    subscribed.add(pattern);
    return incoming.stream.where((m) => topicMatches(pattern, m.topic));
  }

  @override
  void unsubscribe(String pattern) => released.add(pattern);

  @override
  List<MqttRxMessage> latestUnder(String prefix) =>
      cached.where((m) => m.topic.startsWith(prefix)).toList();
}

MqttRxMessage message(String topic, String payload) => MqttRxMessage(
  topic: topic,
  payload: payload,
  receivedAt: DateTime(2026),
  connectionGeneration: 1,
);

void main() {
  testWidgets(
    'replays cached wildcard metadata, follows updates and releases subscriptions',
    (tester) async {
      const root = '/devices/relay/controls/Relay 1';
      final mgr = _Manager()
        ..cached.addAll([
          message('/devices/relay/meta/name', 'Relays'),
          message('$root/meta/type', 'switch'),
          message(
            '/devices/sensor/controls/Temperature/meta',
            '{"type":"value","units":"°C","readonly":true}',
          ),
        ]);
      final container = ProviderContainer(
        overrides: [mqttManagerProvider.overrideWith((ref, _) async => mgr)],
      );
      final provider = wirenBoardDevicesProvider('c1');
      final subscription = container.listen(provider, (_, __) {});
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(container.read(provider).requireValue.map((d) => d.id), [
        'relay',
        'sensor',
      ]);
      expect(mgr.subscribed, [
        '/devices/+/meta/#',
        '/devices/+/controls/+/meta/#',
      ]);

      mgr.incoming.add(message('$root/meta/type', ''));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(provider).requireValue.single.id, 'sensor');
      mgr.incoming.add(
        message(
          '/devices/sensor/controls/Humidity/meta',
          '{"type":"rel_humidity","readonly":true}',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        container.read(provider).requireValue.single.controls,
        hasLength(2),
      );

      subscription.close();
      await tester.pump(const Duration(milliseconds: 1));
      container.dispose();
      await tester.pump();
      expect(mgr.released, mgr.subscribed);
      expect(mgr.incoming.hasListener, isFalse);
      await mgr.incoming.close();
      await mgr.dispose();
    },
  );
}
