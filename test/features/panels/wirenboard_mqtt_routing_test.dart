import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart' as mc;
import 'package:typed_data/typed_data.dart' as typed;
import 'package:zigdash/data/database/database.dart';
import 'package:zigdash/data/database/tables/connections.dart';
import 'package:zigdash/data/database/tables/panels.dart';
import 'package:zigdash/features/discovery/models/wirenboard_device.dart';
import 'package:zigdash/features/discovery/models/wirenboard_panel_suggestion.dart';
import 'package:zigdash/features/panels/models/panel_config.dart';
import 'package:zigdash/features/panels/widgets/panel_tile.dart';
import 'package:zigdash/l10n/app_localizations.dart';
import 'package:zigdash/mqtt/broker_config.dart';
import 'package:zigdash/mqtt/mqtt_manager.dart';
import 'package:zigdash/mqtt/providers/mqtt_manager_provider.dart';

// Only the client boundary is replaced. Topic composition, config round trips,
// MqttManager, scalar extraction, subscriptions and feedback are production code.
class _Client extends mc.MqttClient {
  _Client() : super.withPort('unused', 'test', 1883);
  final _status = mc.MqttClientConnectionStatus();
  final _updates =
      StreamController<
        List<mc.MqttReceivedMessage<mc.MqttMessage>>
      >.broadcast();
  final subscriptions = <String>[];
  final sent = <mc.MqttPublishMessage>[];

  @override
  mc.MqttClientConnectionStatus get connectionStatus => _status;
  @override
  Stream<List<mc.MqttReceivedMessage<mc.MqttMessage>>> get updates =>
      _updates.stream;
  @override
  Future<mc.MqttClientConnectionStatus?> connect([String? u, String? p]) async {
    _status.state = mc.MqttConnectionState.connected;
    return _status;
  }

  @override
  void disconnect() => _status.state = mc.MqttConnectionState.disconnected;
  @override
  mc.Subscription? subscribe(String topic, mc.MqttQos qosLevel) {
    subscriptions.add(topic);
    return null;
  }

  @override
  int publishMessage(
    String topic,
    mc.MqttQos qualityOfService,
    typed.Uint8Buffer data, {
    bool retain = false,
  }) {
    final packet = mc.MqttPublishMessage()
        .toTopic(topic)
        .withQos(qualityOfService)
        .withMessageIdentifier(sent.length + 1)
        .publishData(data);
    packet.setRetain(state: retain);
    final bytes = mc.MqttByteBuffer(typed.Uint8Buffer());
    packet.writeTo(bytes);
    bytes.reset();
    sent.add(mc.MqttMessage.createFrom(bytes) as mc.MqttPublishMessage);
    return sent.length;
  }

  void feedback(String topic, String payload) {
    final message = mc.MqttPublishMessage();
    message.payload.message.addAll(utf8.encode(payload));
    _updates.add([mc.MqttReceivedMessage(topic, message)]);
  }
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  for (final kind in ['discovered switch', 'manual switch', 'curtain']) {
    testWidgets('$kind routes /on commands and receives scalar state', (
      tester,
    ) async {
      final curtain = kind == 'curtain';
      final manual = kind == 'manual switch';
      final device =
          (WirenBoardDiscovery()
                ..apply('/devices/relay/controls/K1/meta', '{"type":"switch"}')
                ..apply(
                  '/devices/relay/controls/Curtain 1 Open/meta',
                  '{"type":"switch"}',
                )
                ..apply(
                  '/devices/relay/controls/Curtain 1 Close/meta',
                  '{"type":"switch"}',
                ))
              .devices
              .single;
      final control = device.controls.firstWhere(
        (c) => c.id == (curtain ? 'Curtain 1 Open' : 'K1'),
      );
      final suggestion = suggestWirenBoardPanel(device, control);
      final panel = Panel(
        id: 'p1',
        dashboardId: 'd1',
        name: 'Relay',
        type: suggestion.type,
        topic: manual ? '${control.topic}/on' : suggestion.publishTopicSuffix,
        subscribeTopic: manual
            ? control.topic
            : suggestion.subscribeTopicSuffix,
        topicPrefixOverride: manual ? null : suggestion.topicPrefixOverride,
        qos: 1,
        retain: false,
        width: PanelWidth.wide,
        sortOrder: 0,
        config: suggestion.config!.encode(),
        mergeFlags: 0,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final client = _Client();
      final manager = MqttManager(
        config: const BrokerConfig(
          id: 'c1',
          host: 'unused',
          port: 1883,
          protocol: MqttProtocol.tcp,
        ),
        password: '',
        clientFactory: (_, _, {host}) => client,
      );
      await manager.connect();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mqttManagerProvider.overrideWith((ref, _) async => manager),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: PanelTile(
                connectionId: 'c1',
                dashboardId: 'd1',
                topicPrefix: '',
                panel: panel,
                locked: true,
              ),
            ),
          ),
        ),
      );
      await _pump(tester);
      expect(client.subscriptions, contains(control.topic));
      expect(client.subscriptions.any((t) => t.endsWith('/on')), isFalse);
      if (curtain) {
        expect(
          client.subscriptions,
          contains('/devices/relay/controls/Curtain 1 Close'),
        );
        // No feedback yet: an explicit direction must still be publishable.
        await tester.tap(find.byKey(const ValueKey('wb-cover-OPEN')));
      } else {
        client.feedback(control.topic, '0');
        await _pump(tester);
        await tester.tap(find.byType(Switch));
      }
      await _pump(tester);
      expect(client.sent, hasLength(1));
      final packet = client.sent.single;
      expect(packet.variableHeader!.topicName, '${control.topic}/on');
      expect(utf8.decode(packet.payload.message), '1');
      expect(packet.header!.retain, isFalse);
      if (curtain) {
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        // Publishing a command is not a state acknowledgement.
        client.feedback('${control.topic}/on', '1');
        await _pump(tester);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      }
      client.feedback(control.topic, '1');
      await _pump(tester);
      if (curtain) {
        expect(find.byType(CircularProgressIndicator), findsNothing);
        final binding = (suggestion.config! as CoverConfig).wirenBoard!;
        await tester.tap(find.byKey(const ValueKey('wb-cover-CLOSE')));
        await _pump(tester);
        expect(
          client.sent.last.variableHeader!.topicName,
          '${binding.closeTopic}/on',
        );
        expect(utf8.decode(client.sent.last.payload.message), '1');
        client.feedback(binding.closeTopic, '1');
        await _pump(tester);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      } else {
        expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
        await tester.tap(find.byType(Switch));
        await _pump(tester);
        expect(
          client.sent.last.variableHeader!.topicName,
          '${control.topic}/on',
        );
        expect(utf8.decode(client.sent.last.payload.message), '0');
      }
      await tester.pumpWidget(const SizedBox());
      await manager.dispose();
      await client._updates.close();
    });
  }
}
