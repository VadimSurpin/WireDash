// The device read's connect budget: the retained-message window for a
// broker, the longer Home Assistant budget for a home connected through
// Home Assistant (a token exchange, TLS, the sign-in and a probe).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart' as mc;
import 'package:wiredash/data/database/tables/connections.dart';
import 'package:wiredash/features/onboarding/setup/z2m_probe.dart';
import 'package:wiredash/mqtt/broker_config.dart';
import 'package:wiredash/mqtt/endpoint.dart';

/// Connects after [delay], then says nothing.
class _SlowClient extends mc.MqttClient {
  _SlowClient(this.delay) : super('x', 'x');
  final Duration delay;
  final _status = mc.MqttClientConnectionStatus();
  final _updates =
      StreamController<List<mc.MqttReceivedMessage<mc.MqttMessage>>>();
  int? budgetSeen;

  @override
  mc.MqttClientConnectionStatus? get connectionStatus => _status;

  @override
  Stream<List<mc.MqttReceivedMessage<mc.MqttMessage>>>? get updates =>
      _updates.stream;

  @override
  void logging({required bool on, bool logPayloads = true}) {}

  @override
  Future<mc.MqttClientConnectionStatus?> connect([
    String? username,
    String? password,
  ]) async {
    budgetSeen = connectTimeoutPeriod;
    await Future<void>.delayed(delay);
    _status.state = mc.MqttConnectionState.connected;
    return _status;
  }

  @override
  mc.Subscription? subscribe(String topic, mc.MqttQos qosLevel) => null;

  @override
  void disconnect() => _status.state = mc.MqttConnectionState.disconnected;
}

void main() {
  BrokerConfig config(ConnectionTransport transport) => BrokerConfig(
    id: 'c',
    host: 'h',
    port: 1,
    protocol: MqttProtocol.tcp,
    transport: transport,
  );

  test('a broker connect is bounded by the window', () async {
    late _SlowClient client;
    final fetcher = Z2mProbeFetcher(
      window: const Duration(milliseconds: 1200),
      clientFactory: (c, id, {host}) =>
          client = _SlowClient(const Duration(milliseconds: 1500)),
    );
    final result = await fetcher.fetch(
      config(ConnectionTransport.mqtt),
      '',
      'z',
    );
    expect(result.detected, isFalse);
    // mqtt_client clamps periods under a second, hence a window over it.
    expect(client.budgetSeen, 1200);
  });

  test(
    'through Home Assistant the connect gets its own, longer budget',
    () async {
      late _SlowClient client;
      final fetcher = Z2mProbeFetcher(
        window: const Duration(milliseconds: 1200),
        clientFactory: (c, id, {host}) =>
            client = _SlowClient(const Duration(milliseconds: 1500)),
      );
      final result = await fetcher.fetch(
        config(ConnectionTransport.homeAssistant),
        'refresh:x',
        'z',
      );
      // Connected (after 1.5 s, within 12 s), then the window passed with
      // nothing retained: not detected, but not a connect failure.
      expect(client.budgetSeen, homeAssistantConnectTimeoutMs);
      expect(
        client.connectionStatus?.state,
        mc.MqttConnectionState.disconnected,
      );
      expect(result.detected, isFalse);
    },
  );
}
