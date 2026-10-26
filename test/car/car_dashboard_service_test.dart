import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart' as mc;
import 'package:rxdart/rxdart.dart';
import 'package:wiredash/car/car_control.dart';
import 'package:wiredash/car/car_dashboard_service.dart';
import 'package:wiredash/data/database/database.dart';
import 'package:wiredash/data/database/tables/connections.dart';
import 'package:wiredash/data/database/tables/panels.dart';
import 'package:wiredash/features/devices/device_profile.dart';
import 'package:wiredash/features/discovery/models/wirenboard_device.dart';
import 'package:wiredash/features/panels/models/panel_config.dart';
import 'package:wiredash/l10n/app_localizations.dart';
import 'package:wiredash/mqtt/broker_config.dart';
import 'package:wiredash/mqtt/mqtt_manager.dart';
import 'package:wiredash/mqtt/mqtt_status.dart';

final _time = DateTime.utc(2026, 10, 26);
final _l10n = lookupAppLocalizations(const Locale('en'));
const _binding = WirenBoardCoverBinding(deviceId: 'wb-mr6c_12', number: 1);

class _Manager extends MqttManager {
  _Manager()
    : super(
        config: const BrokerConfig(
          id: 'h',
          host: 'unused',
          port: 1883,
          protocol: MqttProtocol.tcp,
        ),
        password: '',
      );
  bool connected = true;
  int generation = 1;
  final reconnects = <bool>[];
  final subjects = <String, BehaviorSubject<MqttRxMessage>>{};
  final released = <String>[];
  final sent = <(String, String, bool, mc.MqttQos)>[];
  @override
  bool get isConnected => connected;
  @override
  MqttStatus get status =>
      connected ? MqttStatus.connected : MqttStatus.reconnecting;
  @override
  int get connectionGeneration => generation;
  @override
  void reconnectNow({bool force = false}) {
    reconnects.add(force);
    generation++;
  }

  @override
  Stream<MqttRxMessage> subscribe(String pattern) =>
      subjects.putIfAbsent(pattern, BehaviorSubject.new).stream;
  @override
  void unsubscribe(String pattern) {
    released.add(pattern);
  }

  @override
  void publish(
    String topic,
    String template,
    Object value, {
    mc.MqttQos qos = mc.MqttQos.atLeastOnce,
    bool retain = false,
  }) {
    sent.add((topic, template.replaceAll('{value}', '$value'), retain, qos));
  }

  void feedback(String topic, String payload, DateTime at, {int? gen}) {
    subjects[topic]!.add(
      MqttRxMessage(
        topic: topic,
        payload: payload,
        receivedAt: at,
        connectionGeneration: gen ?? generation,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    for (final s in subjects.values) {
      await s.close();
    }
    await super.dispose();
  }
}

Dashboard _dashboard() => Dashboard(
  id: 'd',
  connectionId: 'h',
  name: 'Driveway',
  topicPrefix: 'ignored',
  colorSeed: 0,
  iconCodepoint: 0,
  locked: true,
  sortOrder: 0,
  createdAt: _time,
  updatedAt: _time,
);

Panel _panel(
  PanelConfig config, {
  String id = 'gate',
  PanelType type = PanelType.cover,
  String topic = 'set',
  String? subscribeTopic = 'state',
  String? prefix,
  bool retain = true,
}) => Panel(
  id: id,
  dashboardId: 'd',
  name: id,
  type: type,
  topic: topic,
  subscribeTopic: subscribeTopic,
  topicPrefixOverride: prefix,
  qos: 1,
  retain: retain,
  width: PanelWidth.wide,
  sortOrder: 0,
  config: config.encode(),
  mergeFlags: 0,
  createdAt: _time,
  updatedAt: _time,
);

void main() {
  test(
    'WB cover keeps exact /on topics, raw repeated 1, custom titles/icons and hidden stop',
    () {
      final cfg = CoverConfig(
        wirenBoard: _binding,
        openButton: const CoverButtonConfig(
          title: 'Enter',
          icon: CoverButtonIcon.gatePartial,
        ),
        closeButton: const CoverButtonConfig(
          title: 'Exit',
          icon: CoverButtonIcon.gateClosed,
        ),
        stopButton: const CoverButtonConfig(visible: false),
      );
      final c = carControls(_dashboard(), [_panel(cfg)], _l10n).single;
      expect(c.topics, isEmpty);
      expect(c.actions.map((a) => a.id), ['OPEN', 'CLOSE']);
      expect(c.actions.first.title, 'Enter');
      expect(c.actions.first.icon, 'gatePartial');
      expect(c.actions.first.commands.single.topic, '${_binding.openTopic}/on');
      expect(c.actions.last.commands.single.topic, '${_binding.closeTopic}/on');
      expect(c.actions.first.commands.single.payload, '1');
      expect(
        c.actions.expand((a) => a.commands).every((cmd) => !cmd.retain),
        isTrue,
      );
    },
  );

  test('scalar and JSON switches use saved topic overrides and payloads', () {
    final scalar = _panel(
      const ToggleConfig(
        jsonPath: null,
        onMatch: '1',
        onPayload: '1',
        offPayload: '0',
      ),
      type: PanelType.toggle,
      prefix: '/devices/relay/controls/K1',
      topic: 'on',
      subscribeTopic: '',
    );
    final c = carControls(_dashboard(), [scalar], _l10n).single;
    expect(c.topics, ['/devices/relay/controls/K1']);
    expect(
      c.actions.last.commands.single.topic,
      '/devices/relay/controls/K1/on',
    );
    expect(c.actions.last.commands.single.payload, '0');
    final json = carControls(_dashboard(), [
      _panel(const ToggleConfig(), type: PanelType.toggle),
    ], _l10n).single;
    expect(json.actions.first.commands.single.payload, '{"state":"ON"}');
  });

  test(
    'whole WB devices expose only selected writable controls and group curtain pairs',
    () {
      final device =
          (WirenBoardDiscovery()
                ..apply('/devices/relay/controls/K1/meta', '{"type":"switch"}')
                ..apply(
                  '/devices/relay/controls/Hidden/meta',
                  '{"type":"switch"}',
                )
                ..apply(
                  '/devices/relay/controls/Input/meta',
                  '{"type":"switch","readonly":true}',
                )
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
      final controls = carControls(_dashboard(), [
        _panel(
          WirenBoardDeviceConfig(
            device: device,
            controlIds: const [
              'K1',
              'Input',
              'Curtain 1 Open',
              'Curtain 1 Close',
            ],
          ),
          type: PanelType.device,
        ),
      ], _l10n);
      expect(controls, hasLength(2));
      expect(controls.map((c) => c.kind), containsAll(['cover', 'switch']));
    },
  );

  test('read-only Z2M covers are not exposed as commands', () {
    for (final writable in [false, true]) {
      final profile = DeviceProfile(
        deviceClass: DeviceClass.cover,
        features: [
          DeviceFeature(
            type: 'enum',
            property: 'state',
            access: writable ? accessState | accessSet : accessState,
          ),
        ],
      );
      final controls = carControls(_dashboard(), [
        _panel(DeviceTileConfig(profile: profile), type: PanelType.device),
      ], _l10n);
      expect(controls.length, writable ? 1 : 0);
    }
  });

  group('headless car session', () {
    late AppDatabase db;
    late _Manager mgr;
    late CarDashboardService service;
    late DateTime now;
    late FakeAsync timers;
    setUp(() async {
      db = AppDatabase.test(NativeDatabase.memory());
      mgr = _Manager();
      now = _time;
      timers = FakeAsync();
      await db
          .into(db.connections)
          .insert(
            ConnectionsCompanion.insert(
              id: 'h',
              name: 'Home',
              host: 'unused',
              port: 1883,
              protocol: MqttProtocol.tcp,
              createdAt: _time,
              updatedAt: _time,
            ),
          );
      await db.into(db.dashboards).insert(_dashboard().toCompanion(false));
      service = CarDashboardService(
        database: () async => db,
        manager: (_) async => mgr,
        localizations: () async => _l10n,
        now: () => now,
        schedule: (duration, callback) =>
            timers.run((_) => Timer(duration, callback)),
      );
    });
    tearDown(() async {
      await service.close();
      await mgr.dispose();
      await db.close();
    });
    Future<void> save(Panel panel) =>
        db.into(db.panels).insertOnConflictUpdate(panel.toCompanion(false));
    Map<String, Object?> first(Map<String, Object?> snapshot) =>
        (snapshot['controls'] as List).first as Map<String, Object?>;

    test(
      'catalog works with phone closed and excludes unsupported dashboard content',
      () async {
        await save(
          _panel(const ButtonConfig(payload: '1'), type: PanelType.button),
        );
        expect((await service.catalog())['dashboards'], [
          {'id': 'd', 'name': 'Driveway', 'home': 'Home'},
        ]);
        expect(
          mgr.reconnects,
          isEmpty,
          reason: 'browsing never connects or publishes',
        );
        expect(mgr.sent, isEmpty);
        final data = await service.open('d');
        expect(mgr.reconnects, [true]);
        expect(jsonEncode(data), isNot(contains('/devices/')));
        expect(jsonEncode(data), isNot(contains('password')));
      },
    );

    test(
      'command-only cover repeats pulses, spins one second, never waits or subscribes',
      () async {
        await save(
          _panel(
            const CoverConfig(
              wirenBoard: _binding,
              stopButton: CoverButtonConfig(visible: false),
            ),
          ),
        );
        await service.open('d');
        expect(mgr.subjects, isEmpty);
        for (var i = 0; i < 3; i++) {
          expect(
            (await service.command('d', 'gate', 'OPEN'))['outcome'],
            'sent',
          );
          expect(first(await service.open('d'))['pending'], 'OPEN');
          timers.elapse(const Duration(milliseconds: 999));
          expect(first(await service.open('d'))['pending'], 'OPEN');
          timers.elapse(const Duration(milliseconds: 1));
          expect(first(await service.open('d'))['pending'], isNull);
        }
        expect(
          mgr.sent.map((s) => (s.$1, s.$2, s.$3)).toList(),
          List.filled(3, ('${_binding.openTopic}/on', '1', false)),
        );
        timers.elapse(const Duration(seconds: 20));
        final state = first(await service.open('d'));
        expect(state['failed'], isFalse);
        expect(state['state'], isNull);
        expect(
          (await service.command('d', 'gate', 'STOP'))['outcome'],
          'removed',
        );
        expect(mgr.sent, hasLength(3));
        await service.close();
      },
    );

    test(
      'feedback accepts only a fresh update from the current MQTT session',
      () async {
        await save(
          _panel(
            const CoverConfig(wirenBoard: _binding, waitForFeedback: true),
          ),
        );
        await service.open('d');
        await service.command('d', 'gate', 'OPEN');
        now = now.add(const Duration(seconds: 1));
        mgr.feedback(_binding.openTopic, '1', now, gen: mgr.generation - 1);
        await Future<void>.delayed(Duration.zero);
        expect(first(await service.open('d'))['pending'], 'OPEN');
        mgr.feedback(_binding.openTopic, '0', now);
        await Future<void>.delayed(Duration.zero);
        expect(first(await service.open('d'))['pending'], isNull);
        await service.command('d', 'gate', 'CLOSE');
        timers.elapse(const Duration(seconds: 15));
        expect(first(await service.open('d'))['failed'], isTrue);
        await service.close();
      },
    );

    test(
      'offline commands are rejected, not replayed, and closed sessions resubscribe',
      () async {
        await save(
          _panel(
            const ToggleConfig(
              jsonPath: null,
              onMatch: '1',
              onPayload: '1',
              offPayload: '0',
            ),
            type: PanelType.toggle,
          ),
        );
        await service.open('d');
        mgr.connected = false;
        expect(
          (await service.command('d', 'gate', 'ON'))['outcome'],
          'unreachable',
        );
        mgr.connected = true;
        await service.open('d');
        expect(mgr.sent, isEmpty);
        await service.close();
        expect(mgr.released, contains('ignored/state'));
        await service.open('d');
        expect(mgr.reconnects, [true, true]);
        expect(mgr.sent, isEmpty);
      },
    );

    test(
      'commands re-read saved configuration and reject deleted or hidden actions',
      () async {
        await save(_panel(const CoverConfig(wirenBoard: _binding)));
        await service.open('d');
        await save(
          _panel(
            const CoverConfig(
              wirenBoard: _binding,
              openButton: CoverButtonConfig(visible: false),
            ),
          ),
        );
        expect(
          (await service.command('d', 'gate', 'OPEN'))['outcome'],
          'removed',
        );
        await (db.delete(db.panels)..where((p) => p.id.equals('gate'))).go();
        expect(
          (await service.command('d', 'gate', 'CLOSE'))['outcome'],
          'removed',
        );
        expect(mgr.sent, isEmpty);
      },
    );

    test(
      'command-only spinner is independent of another tile watching the same relay',
      () async {
        await save(_panel(const CoverConfig(wirenBoard: _binding)));
        await save(
          _panel(
            const CoverConfig(wirenBoard: _binding, waitForFeedback: true),
            id: 'watcher',
          ),
        );
        await service.open('d');
        await service.command('d', 'gate', 'OPEN');
        now = now.add(const Duration(milliseconds: 200));
        mgr.feedback(_binding.openTopic, '1', now);
        await Future<void>.delayed(Duration.zero);
        final controls = (await service.open('d'))['controls'] as List;
        final gate = controls.cast<Map<String, Object?>>().firstWhere(
          (c) => c['id'] == 'gate',
        );
        expect(gate['pending'], 'OPEN');
        timers.elapse(const Duration(seconds: 1));
        expect(first(await service.open('d'))['pending'], isNull);
      },
    );

    test(
      'changing the phone tile to command-only clears an old confirmation failure',
      () async {
        await save(
          _panel(
            const CoverConfig(wirenBoard: _binding, waitForFeedback: true),
          ),
        );
        await service.open('d');
        await service.command('d', 'gate', 'OPEN');
        timers.elapse(const Duration(seconds: 15));
        expect(first(await service.open('d'))['failed'], isTrue);
        await save(
          _panel(
            const CoverConfig(wirenBoard: _binding, waitForFeedback: false),
          ),
        );
        final state = first(await service.open('d'));
        expect(state['failed'], isFalse);
        expect(state['pending'], isNull);
        expect(state['state'], isNull);
      },
    );

    test(
      'JSON CLOSED feedback confirms Close and selects its car action',
      () async {
        await save(_panel(const CoverConfig()));
        await service.open('d');
        await service.command('d', 'gate', 'CLOSE');
        now = now.add(const Duration(seconds: 1));
        mgr.feedback('ignored/state', '{"state":"CLOSED"}', now);
        await Future<void>.delayed(Duration.zero);
        final state = first(await service.open('d'));
        expect(state['pending'], isNull);
        expect(state['state'], 'CLOSE');
      },
    );

    test(
      'an expired tap never publishes after waiting for the headless engine',
      () async {
        await save(
          _panel(const ButtonConfig(payload: '1'), type: PanelType.button),
        );
        await service.open('d');
        final result = await service.command(
          'd',
          'gate',
          'PRESS',
          expiresAt: now
              .subtract(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
        );
        expect(result['outcome'], 'unreachable');
        expect(mgr.sent, isEmpty);
      },
    );
  });
}
