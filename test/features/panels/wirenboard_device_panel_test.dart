import 'dart:async';
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
import 'package:zigdash/features/panels/widgets/device_tile_panel.dart';
import 'package:zigdash/features/panels/widgets/wirenboard_control_row.dart';
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

Widget _app(
  _Recorder mgr, {
  bool metadataAvailable = true,
  DevicePanelDisplay display = const DevicePanelDisplay(),
  double cardWidth = 380,
  double textScale = 1,
  Locale locale = const Locale('en'),
  String temperatureValue = '23.5',
  WirenBoardDevice? initialDevice,
  Stream<List<WirenBoardDevice>>? updates,
}) {
  final device = initialDevice ?? _device();
  String value(String topic) =>
      topic.endsWith('/Temperature') ? temperatureValue : '0';
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
            updates ??
            (metadataAvailable ? Stream.value([device]) : const Stream.empty()),
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
      locale: locale,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: cardWidth,
            child: PanelTile(
              connectionId: 'c1',
              dashboardId: 'd1',
              topicPrefix: 'unrelated',
              panel: _panel(device).copyWith(
                config: WirenBoardDeviceConfig(
                  device: device,
                  display: display,
                ).encode(),
              ),
              locked: true,
            ),
          ),
        ),
      ),
    ),
  );
}

Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

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
    'panel-specific expressions format WB values in the card and full sheet',
    (tester) async {
      final manager = _Recorder();
      await tester.pumpWidget(
        _app(
          manager,
          temperatureValue: '1230',
          display: const DevicePanelDisplay(
            expressions: {'Temperature': '(Number(value) / 100).toFixed(2)'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('12.30 °C'), findsOneWidget);
      await tester.tap(find.text('Relay module'));
      await tester.pumpAndSettle();
      expect(_inSheet(find.text('12.30')), findsOneWidget);
      expect(manager.sent, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await manager.dispose();
    },
  );

  testWidgets(
    'many compact properties scroll to the end of a small phone sheet',
    (tester) async {
      tester.view.physicalSize = const Size(390, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final discovery = WirenBoardDiscovery();
      for (var i = 0; i < 35; i++) {
        discovery.apply(
          '/devices/many/controls/Value $i/meta',
          '{"type":"temperature","readonly":true,"order":$i}',
        );
      }
      final manager = _Recorder();
      await tester.pumpWidget(
        _app(manager, initialDevice: discovery.devices.single),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Relay module'));
      await tester.pumpAndSettle();
      final first = _inSheet(find.byType(WirenBoardControlRow)).first;
      expect(tester.getSize(first).height, lessThan(80));
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Card),
        ),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        _inSheet(find.text('Value 34')),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      expect(_inSheet(find.text('Value 34')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await manager.dispose();
    },
  );

  test(
    'selected-property panels keep their subset across serialization and live metadata',
    () {
      final device = _device();
      final config = WirenBoardDeviceConfig(
        device: device,
        controlIds: ['Temperature'],
      );
      final decoded =
          PanelConfig.decode(PanelType.device, config.encode())
              as WirenBoardDeviceConfig;
      expect(decoded.controlIds, ['Temperature']);
      expect(decoded.visibleDevice(device).controls.map((c) => c.id), [
        'Temperature',
      ]);
    },
  );

  testWidgets(
    'WB uses the same summary card as Z2M, with scalar quick actions and a controls sheet',
    (tester) async {
      final mgr = _Recorder();
      await tester.pumpWidget(_app(mgr));
      await tester.pumpAndSettle();
      expect(find.byType(DeviceSummaryCard), findsOneWidget);
      expect(find.byType(WirenBoardControlRow), findsNothing);
      expect(find.byType(Card), findsOneWidget);
      await tester.tap(find.byTooltip('Turn on or off'));
      await tester.pumpAndSettle();
      expect(mgr.sent, [
        ('/devices/wb-mr6c_12/controls/Relay 1/on', '1', false),
      ]);
      await tester.tap(find.text('Relay module'));
      await tester.pumpAndSettle();
      expect(_inSheet(find.byType(WirenBoardControlRow)), findsNWidgets(4));
      expect(_inSheet(find.text('23.5')), findsOneWidget);
      final writableSwitch = _inSheet(
        find.byWidgetPredicate((w) => w is Switch && w.onChanged != null),
      );
      expect(writableSwitch, findsOneWidget);
      await tester.tap(_inSheet(find.text('Reset')));
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
    'panel-specific switch labels and visibility do not change full controls or metadata',
    (tester) async {
      final manager = _Recorder();
      const display = DevicePanelDisplay(
        properties: ['Relay 1'],
        labels: {'Relay 1': 'Kitchen lights', 'Temperature': 'Air temperature'},
      );
      await tester.pumpWidget(_app(manager, display: display));
      await tester.pumpAndSettle();
      expect(find.text('Kitchen lights'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('summary-property:Temperature')),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Turn on or off'));
      await tester.pumpAndSettle();
      expect(manager.sent.single.$1, '/devices/wb-mr6c_12/controls/Relay 1/on');
      await tester.tap(find.text('Relay module'));
      await tester.pumpAndSettle();
      expect(_inSheet(find.text('Air temperature')), findsOneWidget);
      expect(_inSheet(find.byType(WirenBoardControlRow)), findsNWidgets(4));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(_app(manager));
      await tester.pumpAndSettle();
      expect(find.text('Relay 1'), findsOneWidget);
      expect(find.text('Kitchen lights'), findsNothing);
      expect(_device().controls.first.title('en'), 'Relay 1');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await manager.dispose();
    },
  );

  testWidgets(
    'all labeled switches wrap on narrow cards with RTL and large text',
    (tester) async {
      final discovery = WirenBoardDiscovery();
      for (var i = 1; i <= 6; i++) {
        discovery.apply('/devices/wb-mr6c_12/controls/K$i/meta/readonly', '1');
        discovery.apply(
          '/devices/wb-mr6c_12/controls/K$i/meta',
          '{"type":"switch","order":$i}',
        );
      }
      final manager = _Recorder();
      await tester.pumpWidget(
        _app(
          manager,
          initialDevice: discovery.devices.single,
          cardWidth: 160,
          textScale: 2,
          locale: const Locale('he'),
          display: DevicePanelDisplay(
            labels: {for (var i = 1; i <= 6; i++) 'K$i': 'תאורה בחדר $i'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 1; i <= 6; i++) {
        expect(find.text('תאורה בחדר $i'), findsOneWidget);
      }
      expect(
        find.byTooltip(lookupAppLocalizations(const Locale('he')).deviceToggle),
        findsNWidgets(6),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await manager.dispose();
    },
  );

  testWidgets('non-finite scalar readings do not crash the summary card', (
    tester,
  ) async {
    final manager = _Recorder();
    for (final value in ['NaN', 'Infinity', '-Infinity']) {
      await tester.pumpWidget(_app(manager, temperatureValue: value));
      await tester.pumpAndSettle();
      expect(find.byType(DeviceSummaryCard), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
    await manager.dispose();
  });

  testWidgets(
    'inline enum and range controls publish scalar commands on their own topics',
    (tester) async {
      final discovery = WirenBoardDiscovery()
        ..apply(
          '/devices/config/controls/Mode/meta',
          '{"type":"value","enum":{"0":"Manual","0x10":"Automatic"},"order":1}',
        )
        ..apply(
          '/devices/config/controls/Level/meta',
          '{"type":"range","min":10,"max":90,"order":2}',
        );
      final manager = _Recorder();
      await tester.pumpWidget(
        _app(manager, initialDevice: discovery.devices.single),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Relay module'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Automatic').last);
      await tester.pumpAndSettle();
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.min, 10);
      expect(slider.max, 90);
      slider.onChangeEnd!(50);
      await tester.pumpAndSettle();
      expect(manager.sent, [
        ('/devices/config/controls/Mode/on', '16', false),
        ('/devices/config/controls/Level/on', '50', false),
      ]);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await manager.dispose();
    },
  );

  testWidgets('RGB and local time controls publish editable scalar values', (
    tester,
  ) async {
    final discovery = WirenBoardDiscovery()
      ..apply('/devices/config/controls/Color/meta', '{"type":"rgb","order":1}')
      ..apply(
        '/devices/config/controls/Time/meta',
        '{"type":"local_time","order":2}',
      )
      ..apply(
        '/devices/config/controls/Readonly/meta',
        '{"type":"rgb","readonly":true,"order":3}',
      );
    final manager = _Recorder();
    await tester.pumpWidget(
      _app(manager, initialDevice: discovery.devices.single),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Relay module'));
    await tester.pumpAndSettle();
    for (final (label, value) in [
      ('Color', '255;128;0'),
      ('Time', '1792627200'),
    ]) {
      final row = find.ancestor(
        of: _inSheet(find.text(label)),
        matching: find.byType(WirenBoardControlRow),
      );
      await tester.enterText(
        find.descendant(of: row, matching: find.byType(TextField)),
        value,
      );
      await tester.tap(
        find.descendant(of: row, matching: find.byIcon(Icons.check)),
      );
      await tester.pumpAndSettle();
    }
    final readonly = find.ancestor(
      of: _inSheet(find.text('Readonly')),
      matching: find.byType(WirenBoardControlRow),
    );
    expect(
      find.descendant(of: readonly, matching: find.byType(TextField)),
      findsNothing,
    );
    expect(manager.sent, [
      ('/devices/config/controls/Color/on', '255;128;0', false),
      ('/devices/config/controls/Time/on', '1792627200', false),
    ]);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await manager.dispose();
  });

  testWidgets(
    'typed text follows its control when live metadata reorders the sheet',
    (tester) async {
      final discovery = WirenBoardDiscovery()
        ..apply(
          '/devices/board/controls/Alpha/meta',
          '{"type":"text","order":1}',
        )
        ..apply(
          '/devices/board/controls/Beta/meta',
          '{"type":"text","order":2}',
        );
      final updates = StreamController<List<WirenBoardDevice>>.broadcast();
      final mgr = _Recorder();
      await tester.pumpWidget(
        _app(
          mgr,
          initialDevice: discovery.devices.single,
          updates: updates.stream,
        ),
      );
      await tester.pumpAndSettle();
      updates.add(discovery.devices);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Relay module'));
      await tester.pumpAndSettle();
      Finder inputFor(String label) => find.descendant(
        of: find.ancestor(
          of: _inSheet(find.text(label)),
          matching: find.byType(WirenBoardControlRow),
        ),
        matching: find.byType(TextField),
      );
      await tester.enterText(inputFor('Alpha'), 'pending {value} command');
      discovery.apply(
        '/devices/board/controls/Alpha/meta',
        '{"type":"text","order":3}',
      );
      updates.add(discovery.devices);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(inputFor('Alpha')).controller!.text,
        'pending {value} command',
      );
      expect(
        tester.widget<TextField>(inputFor('Beta')).controller!.text,
        isEmpty,
      );
      final alpha = find.ancestor(
        of: _inSheet(find.text('Alpha')),
        matching: find.byType(WirenBoardControlRow),
      );
      await tester.tap(
        find.descendant(of: alpha, matching: find.byIcon(Icons.check)),
      );
      await tester.pumpAndSettle();
      expect(mgr.sent.single, (
        '/devices/board/controls/Alpha/on',
        'pending {value} command',
        false,
      ));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await updates.close();
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
      expect(_inSheet(find.byType(Switch)), findsNWidgets(2));
      final switchFrame = tester.widgetList<PanelReliabilityFrame>(
        find.ancestor(
          of: _inSheet(find.byType(Switch)),
          matching: find.byType(PanelReliabilityFrame),
        ),
      );
      expect(switchFrame.any((f) => !f.controlsEnabled), isTrue);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('23.5'),
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
