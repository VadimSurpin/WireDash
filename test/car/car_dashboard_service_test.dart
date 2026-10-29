import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:drift/drift.dart' show Value;
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
  String? sectionId,
  int sortOrder = 0,
  bool retain = true,
}) => Panel(
  id: id,
  dashboardId: 'd',
  name: id,
  type: type,
  topic: topic,
  subscribeTopic: subscribeTopic,
  topicPrefixOverride: prefix,
  sectionId: sectionId,
  qos: 1,
  retain: retain,
  width: PanelWidth.wide,
  sortOrder: sortOrder,
  config: config.encode(),
  mergeFlags: 0,
  createdAt: _time,
  updatedAt: _time,
);

void main() {
  test(
    'built-in radio shutters retain their labels, payloads and state topic',
    () {
      final controls = carControls(_dashboard(), [
        _panel(
          OptionsConfig.coverDefault(),
          type: PanelType.radio,
          prefix: 'zigbee2mqtt/bedroom',
          subscribeTopic: '',
        ),
      ], _l10n);
      final cover = controls.single;
      expect(cover.kind, 'cover');
      expect(cover.topics, ['zigbee2mqtt/bedroom']);
      expect(cover.path, 'state');
      expect(cover.actions.map((a) => a.id), ['OPEN', 'STOP', 'CLOSE']);
      expect(cover.actions.map((a) => a.title), ['Open', 'Stop', 'Close']);
      expect(cover.actions.map((a) => a.commands.single.payload), [
        '{"state":"OPEN"}',
        '{"state":"STOP"}',
        '{"state":"CLOSE"}',
      ]);
      expect(
        cover.actions.every(
          (a) => a.commands.single.topic == 'zigbee2mqtt/bedroom/set',
        ),
        isTrue,
      );
    },
  );

  test('device shutter endpoint uses its writable state property', () {
    const profile = DeviceProfile(
      deviceClass: DeviceClass.cover,
      features: [
        DeviceFeature(
          type: 'enum',
          name: 'state',
          property: 'state_left',
          parent: 'cover',
          access: accessState | accessSet,
        ),
      ],
    );
    final cover = carControls(_dashboard(), [
      _panel(
        const DeviceTileConfig(profile: profile),
        type: PanelType.device,
        prefix: 'zigbee2mqtt/shutter',
        subscribeTopic: '',
      ),
    ], _l10n).single;
    expect(cover.path, 'state_left');
    expect(cover.actions.map((a) => a.commands.single.payload), [
      '{"state_left":"OPEN"}',
      '{"state_left":"CLOSE"}',
      '{"state_left":"STOP"}',
    ]);
    expect(
      cover.actions.first.commands.single.topic,
      'zigbee2mqtt/shutter/set',
    );
  });

  test(
    'saved position option buttons keep labels, order, payloads and exact state matches',
    () {
      const config = OptionsConfig(
        jsonPath: 'position_left',
        options: [
          SelectOption(
            label: 'Closed',
            match: '0',
            payload: '{"position_left":0}',
          ),
          SelectOption(
            label: 'Half open',
            match: '50',
            payload: '{"position_left":50}',
          ),
          SelectOption(
            label: 'Fully open',
            match: '100',
            payload: '{"position_left":100}',
          ),
        ],
      );
      for (final type in [
        PanelType.radio,
        PanelType.combo,
        PanelType.multiState,
      ]) {
        final c = carControls(_dashboard(), [
          _panel(
            config,
            type: type,
            prefix: 'zigbee2mqtt/blinds',
            subscribeTopic: '',
          ),
        ], _l10n).single;
        expect(c.kind, 'options');
        expect(c.actions.map((a) => a.title), [
          'Closed',
          'Half open',
          'Fully open',
        ]);
        expect(c.actions.map((a) => a.stateMatch), ['0', '50', '100']);
        expect(c.actions[1].toJson()['stateMatch'], '50');
        expect(c.actions[1].commands.single.payload, '{"position_left":50}');
        expect(c.actions[1].commands.single.topic, 'zigbee2mqtt/blinds/set');
        expect(c.actions[1].commands.single.retain, isTrue);
        expect(c.topics, ['zigbee2mqtt/blinds']);
      }
    },
  );

  test(
    'cover positions preserve presets, endpoint payload, topics and visibility',
    () {
      final c = carControls(_dashboard(), [
        _panel(
          const CoverConfig(
            positionPath: 'position_left',
            positionTemplate: '{"position_left":{value}}',
            presets: [75, 25, 25, -1, 101],
            showSlider: false,
            openButton: CoverButtonConfig(visible: false),
            closeButton: CoverButtonConfig(visible: false),
            stopButton: CoverButtonConfig(visible: false),
          ),
          prefix: 'zigbee2mqtt/curtain',
          subscribeTopic: '',
          retain: false,
        ),
      ], _l10n).single;
      expect(c.positionPath, 'position_left');
      expect(c.actions.map((a) => a.title), ['75%', '25%']);
      expect(c.actions.map((a) => a.position), [75, 25]);
      expect(c.actions.first.toJson()['position'], 75);
      expect(c.topics, ['zigbee2mqtt/curtain']);
      final command = c.actions.first.commands.single;
      expect(
        (command.topic, command.payload, command.retain),
        ('zigbee2mqtt/curtain/set', '{"position_left":75}', false),
      );
      for (final cfg in [
        const CoverConfig(presets: [], showSlider: false),
        const CoverConfig(waitForFeedback: false),
        const CoverConfig(wirenBoard: _binding, waitForFeedback: true),
      ]) {
        final actions = carControls(_dashboard(), [
          _panel(cfg),
        ], _l10n).single.actions;
        expect(actions.every((a) => a.position == null), isTrue);
      }
      final sliderOnly = carControls(_dashboard(), [
        _panel(const CoverConfig(presets: [])),
      ], _l10n).single;
      expect(
        sliderOnly.actions
            .where((a) => a.position != null)
            .map((a) => a.position),
        [0, 25, 50, 75, 100],
      );
    },
  );

  test(
    'position-only device covers use writable endpoint feature, not a fabricated state',
    () {
      for (final writable in [false, true]) {
        final profile = DeviceProfile(
          deviceClass: DeviceClass.cover,
          features: [
            DeviceFeature(
              type: 'numeric',
              name: 'position',
              property: 'position_right',
              parent: 'cover',
              access: writable ? accessState | accessSet : accessState,
            ),
          ],
        );
        final controls = carControls(_dashboard(), [
          _panel(DeviceTileConfig(profile: profile), type: PanelType.device),
        ], _l10n);
        expect(controls.length, writable ? 1 : 0);
        if (writable) {
          expect(controls.single.positionPath, 'position_right');
          expect(
            controls.single.actions.every((a) => a.position != null),
            isTrue,
          );
          expect(
            controls.single.actions[2].commands.single.payload,
            '{"position_right":50}',
          );
        }
      }
    },
  );

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
      'position option buttons confirm numeric feedback and reject deleted choices',
      () async {
        const config = OptionsConfig(
          jsonPath: 'position',
          options: [
            SelectOption(
              label: 'Half open',
              match: '50',
              payload: '{"position":50}',
            ),
          ],
        );
        await save(_panel(config, type: PanelType.radio, retain: false));
        await service.open('d');
        expect(
          (await service.command('d', 'gate', 'OPTION_0'))['outcome'],
          'sent',
        );
        expect(mgr.sent.single.$2, '{"position":50}');
        now = now.add(const Duration(seconds: 1));
        mgr.feedback('ignored/state', '{"position":25}', now);
        await Future<void>.delayed(Duration.zero);
        expect(first(await service.open('d'))['pending'], 'OPTION_0');
        mgr.feedback('ignored/state', '{"position":50}', now);
        await Future<void>.delayed(Duration.zero);
        final confirmed = first(await service.open('d'));
        expect(confirmed['pending'], isNull);
        expect(confirmed['state'], '50');
        await save(
          _panel(const OptionsConfig(options: []), type: PanelType.radio),
        );
        expect(
          (await service.command('d', 'gate', 'OPTION_0'))['outcome'],
          'removed',
        );
        expect(mgr.sent, hasLength(1));
      },
    );

    test(
      'position commands confirm only the target from fresh current-session feedback',
      () async {
        await save(
          _panel(
            const CoverConfig(
              positionPath: 'position_left',
              positionTemplate: '{"position_left":{value}}',
            ),
            retain: false,
          ),
        );
        await service.open('d');
        expect(first(await service.open('d'))['position'], isNull);
        expect(
          (await service.command('d', 'gate', 'POSITION_50'))['outcome'],
          'sent',
        );
        expect(mgr.sent.single.$2, '{"position_left":50}');
        now = now.add(const Duration(seconds: 1));
        for (final sample in [
          ('{"position_left":50}', mgr.generation - 1),
          ('{"state":"OPEN","position_left":25}', mgr.generation),
        ]) {
          mgr.feedback('ignored/state', sample.$1, now, gen: sample.$2);
          await Future<void>.delayed(Duration.zero);
          expect(first(await service.open('d'))['pending'], 'POSITION_50');
        }
        mgr.feedback('ignored/state', '{"position_left":"50"}', now);
        await Future<void>.delayed(Duration.zero);
        final confirmed = first(await service.open('d'));
        expect(confirmed['pending'], isNull);
        expect(confirmed['position'], 50);
        await save(_panel(const CoverConfig(presets: [25], showSlider: false)));
        expect(
          (await service.command('d', 'gate', 'POSITION_50'))['outcome'],
          'removed',
        );
        expect(mgr.sent, hasLength(1));
        mgr.generation++;
        expect(first(await service.open('d'))['position'], isNull);
      },
    );

    test(
      'car groups match phone order, include orphans and preserve button appearance',
      () async {
        for (final entry in [
          ('later', 'Second group', 20),
          ('first', 'First group', 10),
          ('empty', 'Empty', 30),
        ]) {
          await db
              .into(db.sections)
              .insert(
                SectionsCompanion.insert(
                  id: entry.$1,
                  dashboardId: 'd',
                  name: entry.$2,
                  sortOrder: Value(entry.$3),
                  createdAt: _time,
                  updatedAt: _time,
                ),
              );
        }
        const cfg = ButtonConfig(
          payload: '1',
          iconCodepoint: 0xe88a,
          colorArgb: 0xff123456,
        );
        await save(
          _panel(
            cfg,
            id: 'second',
            type: PanelType.button,
            sectionId: 'later',
            sortOrder: 0,
          ),
        );
        await save(
          _panel(
            cfg,
            id: 'first-b',
            type: PanelType.button,
            sectionId: 'first',
            sortOrder: 2,
          ),
        );
        await save(
          _panel(
            cfg,
            id: 'first-a',
            type: PanelType.button,
            sectionId: 'first',
            sortOrder: 1,
          ),
        );
        // Older backups can contain a reference to a missing section.
        await db.customStatement('PRAGMA foreign_keys = OFF');
        await save(
          _panel(
            cfg,
            id: 'orphan',
            type: PanelType.button,
            sectionId: 'deleted',
            sortOrder: 3,
          ),
        );
        await db.customStatement('PRAGMA foreign_keys = ON');
        await save(
          _panel(cfg, id: 'loose', type: PanelType.button, sortOrder: 4),
        );
        final data = await service.open('d');
        expect(data['sections'], [
          {'id': 'first', 'name': 'First group'},
          {'id': 'later', 'name': 'Second group'},
        ]);
        final controls = (data['controls'] as List)
            .cast<Map<String, Object?>>();
        expect(controls.map((c) => c['id']), [
          'orphan',
          'loose',
          'first-a',
          'first-b',
          'second',
        ]);
        expect(controls.take(2).every((c) => c['sectionId'] == null), isTrue);
        final action = (controls.last['actions'] as List).single as Map;
        expect(action['iconCodepoint'], 0xe88a);
        expect(action['colorArgb'], 0xff123456);

        // Moving/renaming a group on the phone is reflected by the next poll.
        await (db.update(
          db.sections,
        )..where((s) => s.id.equals('later'))).write(
          const SectionsCompanion(sortOrder: Value(0), name: Value('Renamed')),
        );
        final updated = await service.open('d');
        expect((updated['sections'] as List).first, {
          'id': 'later',
          'name': 'Renamed',
        });
        expect(mgr.sent, isEmpty);
      },
    );

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
