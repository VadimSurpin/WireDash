import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart' as mc;
import 'package:zigdash/data/database/database.dart';
import 'package:zigdash/data/database/tables/connections.dart';
import 'package:zigdash/data/database/tables/panels.dart';
import 'package:zigdash/features/discovery/models/wirenboard_device.dart';
import 'package:zigdash/features/discovery/models/wirenboard_panel_suggestion.dart';
import 'package:zigdash/features/discovery/providers/wirenboard_discovery_provider.dart';
import 'package:zigdash/features/panels/models/panel_config.dart';
import 'package:zigdash/features/panels/providers/panel_value_provider.dart';
import 'package:zigdash/features/panels/widgets/panel_reliability_frame.dart';
import 'package:zigdash/features/panels/widgets/panel_tile.dart';
import 'package:zigdash/l10n/app_localizations.dart';
import 'package:zigdash/mqtt/broker_config.dart';
import 'package:zigdash/mqtt/mqtt_manager.dart';
import 'package:zigdash/mqtt/mqtt_status.dart';
import 'package:zigdash/mqtt/providers/mqtt_manager_provider.dart';

class _Recorder extends MqttManager {
  _Recorder({this.connected = true})
    : super(
        config: const BrokerConfig(
          id: 'c1',
          host: 'unused',
          port: 1883,
          protocol: MqttProtocol.tcp,
        ),
        password: '',
      );
  final bool connected;
  final sent = <(String, String, bool)>[];
  @override
  bool get isConnected => connected;
  @override
  void publish(
    String topic,
    String template,
    Object value, {
    mc.MqttQos qos = mc.MqttQos.atLeastOnce,
    bool retain = false,
  }) => sent.add((topic, template.replaceAll('{value}', '$value'), retain));
}

WirenBoardDevice _device() =>
    (WirenBoardDiscovery()
          ..apply('/devices/wb-mr6c_12/meta/name', 'Relay module')
          ..apply(
            '/devices/wb-mr6c_12/controls/Relay 1/meta',
            '{"type":"switch","order":1}',
          )
          ..apply(
            '/devices/wb-mr6c_12/controls/Input/meta',
            '{"type":"switch","readonly":true,"order":2}',
          )
          ..apply(
            '/devices/wb-mr6c_12/controls/Temperature/meta',
            '{"type":"temperature","readonly":true,"order":3}',
          )
          ..apply(
            '/devices/wb-mr6c_12/controls/Reset/meta',
            '{"type":"pushbutton","order":4}',
          ))
        .devices
        .single;

Panel _panel(WirenBoardDevice device) => Panel(
  id: 'p1',
  dashboardId: 'd1',
  name: 'Relay module',
  type: PanelType.device,
  topic: '',
  subscribeTopic: '',
  topicPrefixOverride: '/devices/${device.id}',
  qos: 1,
  retain: false,
  width: PanelWidth.wide,
  sortOrder: 0,
  config: WirenBoardDeviceConfig(device: device).encode(),
  mergeFlags: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Widget _app(_Recorder mgr, {bool metadataAvailable = true}) {
  final device = _device();
  String value(String topic) => topic.endsWith('/Temperature') ? '23.5' : '0';
  return ProviderScope(
    overrides: [
      mqttManagerProvider.overrideWith((ref, _) async => mgr),
      connectionStatusProvider.overrideWith(
        (ref, _) => Stream.value(
          mgr.connected ? MqttStatus.connected : MqttStatus.disconnected,
        ),
      ),
      wirenBoardDevicesProvider.overrideWith(
        (ref, _) =>
            metadataAvailable ? Stream.value([device]) : const Stream.empty(),
      ),
      panelValueProvider.overrideWith(
        (ref, key) => Stream.value(value(key.topic)),
      ),
      panelValueSnapshotProvider.overrideWith(
        (ref, key) => Stream.value(
          PanelValueSnapshot(
            value: value(key.topic),
            receivedAt: DateTime(2026),
            connectionGeneration: 1,
            freshness: mgr.connected
                ? PanelFreshness.fresh
                : PanelFreshness.stale,
          ),
        ),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 380,
          child: PanelTile(
            connectionId: 'c1',
            dashboardId: 'd1',
            topicPrefix: 'unrelated',
            panel: _panel(device),
            locked: true,
          ),
        ),
      ),
    ),
  );
}

void main() {
  test(
    'whole-device config round-trips metadata and preserves the device panel type',
    () {
      final device = _device();
      final suggestion = suggestWirenBoardDevicePanel(device);
      expect(suggestion.type, PanelType.device);
      final saved =
          PanelConfig.decode(PanelType.device, suggestion.config!.encode())
              as WirenBoardDeviceConfig;
      expect(saved.device.toJson(), device.toJson());
      expect(saved.device.controls[1].readOnly, isTrue);
      expect(saved.device.controls[2].unit, '°C');
    },
  );

  test('controller IDs are matched exactly, including legacy built-ins', () {
    for (final id in ['hwmon', 'wb-gpio', 'wb-adc', 'power_status', 'wb-w1']) {
      expect(
        WirenBoardDevice(
          id: id,
          metadata: const {},
          controls: const [],
        ).isControllerBuiltin,
        isTrue,
      );
    }
    for (final id in [
      'wb-mr6c_12',
      'wb-msw-v3_52',
      'virtual_room',
      'wb-gpio_1',
    ]) {
      expect(
        WirenBoardDevice(
          id: id,
          metadata: const {},
          controls: const [],
        ).isControllerBuiltin,
        isFalse,
      );
    }
  });

  testWidgets(
    'one tile opens scalar controls and sends commands to the right /on topics',
    (tester) async {
      final mgr = _Recorder();
      await tester.pumpWidget(_app(mgr));
      await tester.pumpAndSettle();
      expect(find.text('4 controls'), findsOneWidget);
      expect(find.text('Temperature: 23.5 °C'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      await tester.tap(find.text('Relay module'));
      await tester.pumpAndSettle();
      expect(
        find.byType(Switch),
        findsOneWidget,
        reason: 'The input is read-only',
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(mgr.sent, [
        ('/devices/wb-mr6c_12/controls/Relay 1/on', '1', false),
      ]);
      final reset = find.text('Reset');
      await tester.scrollUntilVisible(
        reset,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(mgr.sent.last, (
        '/devices/wb-mr6c_12/controls/Reset/on',
        '1',
        false,
      ));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await mgr.dispose();
    },
  );

  testWidgets(
    'cached controls remain readable offline and interactive controls are blocked',
    (tester) async {
      final mgr = _Recorder(connected: false);
      await tester.pumpWidget(_app(mgr, metadataAvailable: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Relay module'));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsOneWidget);
      final switchFrame = tester.widgetList<PanelReliabilityFrame>(
        find.ancestor(
          of: find.byType(Switch),
          matching: find.byType(PanelReliabilityFrame),
        ),
      );
      expect(switchFrame.any((f) => !f.controlsEnabled), isTrue);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.textContaining('23.5°C'),
        ),
        findsOneWidget,
      );
      expect(mgr.sent, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await mgr.dispose();
    },
  );
}
