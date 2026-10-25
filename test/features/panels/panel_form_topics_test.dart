import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zigdash/data/database/database.dart';
import 'package:zigdash/data/database/tables/panels.dart';
import 'package:zigdash/data/repositories/connection_repo.dart';
import 'package:zigdash/data/repositories/dashboard_repo.dart';
import 'package:zigdash/data/repositories/panel_repo.dart';
import 'package:zigdash/features/discovery/models/z2m_device.dart';
import 'package:zigdash/features/discovery/models/wirenboard_device.dart';
import 'package:zigdash/features/discovery/providers/discovery_provider.dart';
import 'package:zigdash/features/discovery/providers/wirenboard_discovery_provider.dart';
import 'package:zigdash/features/devices/devices_providers.dart';
import 'package:zigdash/features/panels/models/panel_config.dart';
import 'package:zigdash/features/panels/screens/panel_form_screen.dart';
import 'package:zigdash/l10n/app_localizations.dart';
import 'package:zigdash/mqtt/providers/mqtt_manager_provider.dart';

void main() {
  group('deviceTopics (Pick a device)', () {
    test('dashboard prefix zigbee2mqtt → the friendly name', () {
      expect(
        deviceTopics(
          deviceTopic: 'zigbee2mqtt/Porch light',
          prefix: 'zigbee2mqtt',
          base: 'zigbee2mqtt',
        ),
        (state: 'Porch light', prefixOverride: null),
      );
    });
    test('no prefix → the whole device topic', () {
      expect(
        deviceTopics(
          deviceTopic: 'zigbee2mqtt/Porch light',
          prefix: '',
          base: 'zigbee2mqtt',
        ),
        (state: 'zigbee2mqtt/Porch light', prefixOverride: null),
      );
    });
    test('an unrelated prefix → a prefix override of the base topic', () {
      expect(
        deviceTopics(
          deviceTopic: 'zigbee2mqtt/Porch light',
          prefix: 'home/sensors',
          base: 'zigbee2mqtt',
        ),
        (state: 'Porch light', prefixOverride: 'zigbee2mqtt'),
      );
    });
    test('the prefix is the device topic → empty state, command "set"', () {
      final t = deviceTopics(
        deviceTopic: 'zigbee2mqtt/lamp',
        prefix: 'zigbee2mqtt/lamp',
        base: 'zigbee2mqtt',
      );
      expect(t.state, '');
      expect(commandFor(t.state), 'set');
    });
  });

  group('the form', () {
    final stamp = DateTime(2026);
    Panel panel({String? prefixOverride, int qos = 1}) => Panel(
      id: 'p1',
      dashboardId: 'd1',
      name: 'Lamp',
      type: PanelType.toggle,
      topic: 'lamp/set',
      subscribeTopic: 'lamp',
      topicPrefixOverride: prefixOverride,
      qos: qos,
      retain: false,
      width: PanelWidth.small,
      sortOrder: 0,
      config: const ToggleConfig().encode(),
      mergeFlags: 0,
      createdAt: stamp,
      updatedAt: stamp,
    );
    final dashboard = Dashboard(
      id: 'd1',
      connectionId: 'c1',
      name: 'Home',
      topicPrefix: 'zigbee2mqtt',
      colorSeed: 0,
      iconCodepoint: 0,
      locked: false,
      sortOrder: 0,
      createdAt: stamp,
      updatedAt: stamp,
    );

    final wb =
        (WirenBoardDiscovery()
              ..apply('/devices/relay/meta/name', 'Relay module')
              ..apply('/devices/relay/controls/K1/meta', '{"type":"switch"}')
              ..apply(
                '/devices/hwmon/controls/Board temperature/meta',
                '{"type":"temperature","readonly":true}',
              )
              ..apply(
                '/devices/room_lamp/controls/State/meta',
                '{"type":"switch"}',
              ))
            .devices;

    Widget app(
      Panel p, {
      _Panels? repo,
      bool nativePending = false,
      Stream<List<WirenBoardDevice>>? wbStream,
    }) => ProviderScope(
      overrides: [
        panelRepoProvider.overrideWithValue(repo ?? _Panels(p)),
        homeBaseTopicProvider.overrideWith((ref, _) => 'home/z2m'),
        dashboardRepoProvider.overrideWithValue(_Dashboards(dashboard)),
        connectionsStreamProvider.overrideWith(
          (ref) => Stream.value(const <Connection>[]),
        ),
        dashboardsForConnectionProvider.overrideWith(
          (ref, _) => Stream.value([dashboard]),
        ),
        mqttManagerProvider.overrideWith((ref, _) => Completer<Never>().future),
        wirenBoardDevicesProvider.overrideWith(
          (ref, _) => wbStream ?? Stream.value(wb),
        ),
        bridgeDevicesStreamProvider.overrideWith((ref, args) {
          expect(args.base, 'home/z2m');
          if (nativePending) return const Stream<List<Z2mDevice>>.empty();
          return Stream.value(const [
            Z2mDevice(
              friendlyName: 'Porch light',
              type: 'Router',
              ieeeAddress: '0x01',
            ),
            Z2mDevice(friendlyName: 'room/lamp', type: 'Router'),
          ]);
        }),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(
          initialLocation: '/edit',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(),
              routes: [
                GoRoute(
                  path: 'edit',
                  builder: (_, _) => PanelFormScreen(
                    connectionId: 'c1',
                    dashboardId: 'd1',
                    panelId: p.id,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('an existing tile opens with its topics, Advanced folded', (
      tester,
    ) async {
      await tester.pumpWidget(app(panel()));
      await settle(tester);
      expect(find.text('State topic'), findsOneWidget);
      expect(_field('lamp'), findsOneWidget);
      expect(_field('lamp/set'), findsOneWidget);
      expect(find.text('Pick a device'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Advanced'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Topic prefix override (optional)'),
        findsNothing,
        reason: 'Advanced stays folded when unused',
      );
    });

    testWidgets('a tile using a prefix override opens Advanced', (
      tester,
    ) async {
      await tester.pumpWidget(app(panel(prefixOverride: 'z2m', qos: 0)));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('Retain'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(_field('z2m'), findsOneWidget);
    });

    testWidgets('picker shows every source with categories collapsed', (
      tester,
    ) async {
      await tester.pumpWidget(app(panel()));
      await settle(tester);
      await tester.tap(find.text('Pick a device'));
      await settle(tester);
      for (final label in [
        'Zigbee2MQTT',
        'Added modules',
        'Wirenboard Z2M devices',
        'Controller built-ins',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Porch light'), findsNothing);
      expect(find.text('Relay module'), findsNothing);
      await tester.tap(find.text('Zigbee2MQTT'));
      await settle(tester);
      await tester.tap(find.text('Porch light'));
      await settle(tester);
      expect(_field('Porch light'), findsOneWidget);
      expect(_field('Porch light/set'), findsOneWidget);
      expect(find.text('Linked to Porch light'), findsOneWidget);
    });

    testWidgets('WB-only picker selects and saves scalar switch topics', (
      tester,
    ) async {
      final repo = _Panels(panel());
      await tester.pumpWidget(app(panel(), repo: repo, nativePending: true));
      await settle(tester);
      await tester.tap(find.text('Pick a device'));
      await settle(tester);
      await tester.tap(find.text('Added modules'));
      await settle(tester);
      await tester.tap(find.text('Relay module'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('wb-property:relay/K1')));
      await settle(tester);
      expect(_field('on'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(repo.savedType, PanelType.toggle);
      expect(repo.savedPrefix, '/devices/relay/controls/K1');
      expect(repo.savedTopic, 'on');
      expect(repo.savedSubscribeTopic, '');
      final config = repo.savedConfig! as ToggleConfig;
      expect(config.onPayload, '1');
      expect(config.offPayload, '0');
      expect(config.jsonPath, isNull);
      expect(repo.savedName, 'Lamp');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'search finds builtin properties and saves their matching tile type',
      (tester) async {
        final repo = _Panels(panel());
        await tester.pumpWidget(app(panel(), repo: repo));
        await settle(tester);
        await tester.tap(find.text('Pick a device'));
        await settle(tester);
        await tester.enterText(
          find.descendant(
            of: find.byType(SearchBar),
            matching: find.byType(TextField),
          ),
          'board temperature',
        );
        await settle(tester);
        expect(find.text('Zigbee2MQTT'), findsNothing);
        await tester.tap(find.text('Board temperature'));
        await settle(tester);
        await tester.tap(find.text('Save'));
        await settle(tester);
        expect(repo.savedType, PanelType.reading);
        expect(repo.savedPrefix, '/devices/hwmon/controls/Board temperature');
        expect(repo.savedTopic, '');
        final config = repo.savedConfig! as ReadingConfig;
        expect(config.jsonPath, '');
        expect(config.unit, '°C');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('picker receives WB metadata while already open', (
      tester,
    ) async {
      final updates = StreamController<List<WirenBoardDevice>>.broadcast();
      await tester.pumpWidget(
        app(panel(), nativePending: true, wbStream: updates.stream),
      );
      await settle(tester);
      await tester.tap(find.text('Pick a device'));
      await settle(tester);
      updates.add(wb);
      await settle(tester);
      expect(find.text('Added modules'), findsOneWidget);
      await tester.tap(find.text('Added modules'));
      await settle(tester);
      expect(find.text('Relay module'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      await tester.runAsync(updates.close);
    });

    testWidgets('switching back to native Z2M restores JSON payloads', (
      tester,
    ) async {
      final repo = _Panels(panel());
      await tester.pumpWidget(app(panel(), repo: repo));
      await settle(tester);
      await tester.tap(find.text('Pick a device'));
      await settle(tester);
      await tester.enterText(
        find.descendant(
          of: find.byType(SearchBar),
          matching: find.byType(TextField),
        ),
        'K1',
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('wb-property:relay/K1')));
      await settle(tester);
      await tester.tap(find.text('Pick a device'));
      await settle(tester);
      await tester.tap(find.text('Zigbee2MQTT'));
      await settle(tester);
      await tester.tap(find.text('Porch light'));
      await settle(tester);
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(repo.savedPrefix, 'home/z2m');
      expect(repo.savedTopic, 'Porch light/set');
      final config = repo.savedConfig! as ToggleConfig;
      expect(config.onPayload, '{"state":"ON"}');
      expect(config.jsonPath, 'state');
    });

    testWidgets('whole-device tiles can select a complete WB module', (
      tester,
    ) async {
      final p = panel().copyWith(
        type: PanelType.device,
        config: PanelConfig.defaultFor(PanelType.device).encode(),
      );
      final repo = _Panels(p);
      await tester.pumpWidget(app(p, repo: repo));
      await settle(tester);
      await tester.tap(find.text('Pick a device'));
      await settle(tester);
      await tester.tap(find.text('Added modules'));
      await settle(tester);
      await tester.tap(find.byTooltip('Add whole device'));
      await settle(tester);
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(repo.savedType, PanelType.device);
      expect(repo.savedPrefix, '/devices/relay');
      expect((repo.savedConfig! as WirenBoardDeviceConfig).device.id, 'relay');
    });
  });
}

Finder _field(String text) => find.byWidgetPredicate(
  (w) => w is EditableText && w.controller.text == text,
);

class _Panels implements PanelRepo {
  _Panels(this.panel);
  final Panel panel;
  PanelType? savedType;
  PanelConfig? savedConfig;
  String? savedPrefix, savedTopic, savedSubscribeTopic, savedName;
  @override
  Future<Panel?> getById(String id) async => panel;
  @override
  Future<void> update({
    required String id,
    required String name,
    PanelType? type,
    required String topic,
    String? subscribeTopic,
    String? topicPrefixOverride,
    int qos = 1,
    bool retain = false,
    PanelWidth width = PanelWidth.small,
    required PanelConfig config,
  }) async {
    savedType = type;
    savedConfig = config;
    savedPrefix = topicPrefixOverride;
    savedTopic = topic;
    savedSubscribeTopic = subscribeTopic;
    savedName = name;
  }

  @override
  Future<void> setDevice(String id, String? ieee) async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Dashboards implements DashboardRepo {
  _Dashboards(this.dashboard);
  final Dashboard dashboard;
  @override
  Future<Dashboard?> getById(String id) async => dashboard;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
