import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart' as mc;
import 'package:typed_data/typed_data.dart' as typed;
import 'package:wiredash/core/lifecycle/app_lifecycle_reconnector.dart';
import 'package:wiredash/data/database/database.dart';
import 'package:wiredash/data/database/tables/connections.dart';
import 'package:wiredash/data/database/tables/panels.dart';
import 'package:wiredash/features/discovery/models/wirenboard_device.dart';
import 'package:wiredash/features/discovery/models/wirenboard_panel_suggestion.dart';
import 'package:wiredash/features/dashboards/widgets/connection_status_banner.dart';
import 'package:wiredash/features/panels/models/panel_config.dart';
import 'package:wiredash/features/panels/widgets/panel_tile.dart';
import 'package:wiredash/l10n/app_localizations.dart';
import 'package:wiredash/mqtt/broker_config.dart';
import 'package:wiredash/mqtt/mqtt_manager.dart';
import 'package:wiredash/mqtt/mqtt_status.dart';
import 'package:wiredash/mqtt/providers/mqtt_manager_provider.dart';

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
  Completer<void>? connectGate;

  @override
  mc.MqttClientConnectionStatus get connectionStatus => _status;
  @override
  Stream<List<mc.MqttReceivedMessage<mc.MqttMessage>>> get updates =>
      _updates.stream;
  @override
  Future<mc.MqttClientConnectionStatus?> connect([String? u, String? p]) async {
    _status.state = mc.MqttConnectionState.connecting;
    if (connectGate != null) await connectGate!.future;
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
  testWidgets(
    'switch state and cover feedback recover after repeated backgrounds',
    (tester) async {
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
      Panel panelFor(String id) {
        final suggestion = suggestWirenBoardPanel(
          device,
          device.controls.firstWhere((c) => c.id == id),
        );
        final config = suggestion.config!;
        return Panel(
          id: id,
          dashboardId: 'd1',
          name: id,
          type: suggestion.type,
          topic: suggestion.publishTopicSuffix,
          subscribeTopic: suggestion.subscribeTopicSuffix,
          topicPrefixOverride: suggestion.topicPrefixOverride,
          qos: 1,
          retain: false,
          width: PanelWidth.wide,
          sortOrder: 0,
          config:
              (config is CoverConfig
                      ? config.copyWith(waitForFeedback: true)
                      : config)
                  .encode(),
          mergeFlags: 0,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
      }

      const stateTopic = '/devices/relay/controls/K1';
      const openTopic = '/devices/relay/controls/Curtain 1 Open';
      const closeTopic = '/devices/relay/controls/Curtain 1 Close';
      final clients = <_Client>[];
      var now = DateTime.now();
      final manager = MqttManager(
        config: const BrokerConfig(
          id: 'c1',
          host: 'unused',
          port: 1883,
          protocol: MqttProtocol.tcp,
        ),
        password: '',
        // The previous activity is still recent: resume must restore subscriptions
        // even when the old connection continues to report connected.
        now: () => now,
        clientFactory: (_, _, {host}) {
          final client = _Client();
          if (clients.isNotEmpty) client.connectGate = Completer<void>();
          clients.add(client);
          return client;
        },
      );
      final registry = MqttManagerRegistry()..register(manager);
      var cleanedUp = false;
      Future<void> cleanUp() async {
        if (cleanedUp) return;
        cleanedUp = true;
        registry.unregister(manager);
        await manager.dispose();
        for (final client in clients) {
          await client._updates.close();
        }
      }
      addTearDown(cleanUp);
      await manager.connect();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mqttManagerProvider.overrideWith((ref, _) async => manager),
            mqttManagerRegistryProvider.overrideWithValue(registry),
          ],
          child: AppLifecycleReconnector(
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Column(
                  children: [
                    Consumer(
                      builder: (context, ref, _) => ConnectionStatusBanner(
                        status:
                            ref
                                .watch(connectionStatusProvider('c1'))
                                .valueOrNull ??
                            MqttStatus.connecting,
                        onReconnect: manager.reconnectNow,
                      ),
                    ),
                    for (final id in ['K1', 'Curtain 1 Open'])
                      PanelTile(
                        connectionId: 'c1',
                        dashboardId: 'd1',
                        topicPrefix: '',
                        panel: panelFor(id),
                        locked: true,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await _pump(tester);
      clients.single.feedback(stateTopic, '0');
      await _pump(tester);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      Future<void> lifecycle(AppLifecycleState state) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/lifecycle',
          const StringCodec().encodeMessage(state.toString()),
          (_) {},
        );
        await _pump(tester);
      }

      for (var cycle = 0; cycle < 3; cycle++) {
        final previous = clients.last;
        await lifecycle(AppLifecycleState.inactive);
        await lifecycle(AppLifecycleState.paused);
        await lifecycle(AppLifecycleState.inactive);
        await lifecycle(AppLifecycleState.resumed);
        expect(
          clients,
          hasLength(cycle + 2),
          reason: 'resume restores the receiving session',
        );
        final current = clients.last;
        expect(manager.status, MqttStatus.reconnecting);
        expect(
          find.bySemanticsIdentifier('connection-status-banner'),
          findsOneWidget,
        );
        expect(current.sent, isEmpty, reason: 'resume never replays a command');
        current.connectGate!.complete();
        await _pump(tester);
        expect(
          find.bySemanticsIdentifier('connection-status-banner'),
          findsNothing,
        );
        expect(manager.status, MqttStatus.connected);
        expect(
          previous.connectionStatus.state,
          mc.MqttConnectionState.disconnected,
        );
        expect(
          current.subscriptions,
          containsAll([stateTopic, openTopic, closeTopic]),
        );

        for (final value in ['1', '0', '1', '0']) {
          await tester.tap(find.byType(Switch));
          await _pump(tester);
          expect(current.sent.last.variableHeader!.topicName, '$stateTopic/on');
          expect(utf8.decode(current.sent.last.payload.message), value);
          current.feedback(stateTopic, value);
          await _pump(tester);
          expect(
            tester.widget<Switch>(find.byType(Switch)).value,
            value == '1',
          );
        }
        await tester.tap(find.byKey(const ValueKey('wb-cover-OPEN')));
        await _pump(tester);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        previous.feedback(openTopic, '0');
        await _pump(tester);
        expect(
          find.byType(CircularProgressIndicator),
          findsOneWidget,
          reason: 'an old session cannot confirm a new command',
        );
        now = DateTime.now().add(const Duration(seconds: 1));
        current.feedback(openTopic, '0');
        await _pump(tester);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      await cleanUp();
    },
  );

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
        config: curtain
            ? (suggestion.config! as CoverConfig)
                  .copyWith(waitForFeedback: true)
                  .encode()
            : suggestion.config!.encode(),
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
        await tester.tap(find.byKey(const ValueKey('wb-cover-OPEN')));
        await _pump(tester);
        expect(client.sent, hasLength(2));
        expect(
          client.sent.last.variableHeader!.topicName,
          '${control.topic}/on',
        );
        expect(utf8.decode(client.sent.last.payload.message), '1');
        expect(client.sent.last.header!.retain, isFalse);
        // Publishing a command is not a state acknowledgement.
        client.feedback('${control.topic}/on', '1');
        await _pump(tester);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      }
      client.feedback(control.topic, curtain ? '0' : '1');
      await _pump(tester);
      if (curtain) {
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.tap(find.byKey(const ValueKey('wb-cover-OPEN')));
        await _pump(tester);
        expect(client.sent, hasLength(3));
        expect(
          client.sent.last.variableHeader!.topicName,
          '${control.topic}/on',
        );
        expect(utf8.decode(client.sent.last.payload.message), '1');
        client.feedback(control.topic, '1');
        await _pump(tester);
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
