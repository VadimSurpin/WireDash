import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart' as mc;
import 'package:rxdart/rxdart.dart';
import 'package:zigdash/data/database/database.dart';
import 'package:zigdash/data/database/tables/connections.dart';
import 'package:zigdash/data/database/tables/panels.dart';
import 'package:zigdash/features/panels/models/panel_config.dart';
import 'package:zigdash/features/panels/providers/panel_value_provider.dart';
import 'package:zigdash/features/panels/widgets/panel_tile.dart';
import 'package:zigdash/features/panels/widgets/cover_button_icon.dart';
import 'package:zigdash/l10n/app_localizations.dart';
import 'package:zigdash/mqtt/broker_config.dart';
import 'package:zigdash/mqtt/mqtt_manager.dart';
import 'package:zigdash/mqtt/mqtt_status.dart';
import 'package:zigdash/mqtt/providers/mqtt_manager_provider.dart';

const _binding = WirenBoardCoverBinding(deviceId: 'relay', number: 1);
const _config = CoverConfig(
  wirenBoard: _binding,
  presets: [],
  showSlider: false,
  openButton: CoverButtonConfig(icon: CoverButtonIcon.gatePartial),
  closeButton: CoverButtonConfig(icon: CoverButtonIcon.gateClosed),
  stopButton: CoverButtonConfig(visible: false),
);

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
  bool connected = true;
  int generation = 7;
  final sent = <(String, String, bool)>[];
  @override
  bool get isConnected => connected;
  @override
  int get connectionGeneration => generation;
  @override
  void publish(
    String topic,
    String template,
    Object value, {
    mc.MqttQos qos = mc.MqttQos.atLeastOnce,
    bool retain = false,
  }) => sent.add((topic, template, retain));
}

PanelValueSnapshot _state(
  String value, {
  bool fresh = true,
  int generation = 7,
  bool old = false,
}) => PanelValueSnapshot(
  value: value,
  receivedAt: old
      ? DateTime.utc(2020)
      : DateTime.now().add(const Duration(seconds: 1)),
  connectionGeneration: generation,
  freshness: fresh ? PanelFreshness.fresh : PanelFreshness.stale,
);

class _Fixture {
  final manager = _Manager();
  final open = BehaviorSubject<PanelValueSnapshot>.seeded(
    _state('0', old: true),
  );
  final close = BehaviorSubject<PanelValueSnapshot>.seeded(
    _state('0', old: true),
  );
  final status = BehaviorSubject<MqttStatus>.seeded(MqttStatus.connected);
  Future<void> dispose() async {
    await open.close();
    await close.close();
    await status.close();
  }
}

Widget _app(
  _Fixture f, {
  CoverConfig config = _config,
  double scale = 1,
  bool feedback = true,
}) {
  final now = DateTime(2026);
  final panel = Panel(
    id: 'p1',
    dashboardId: 'd1',
    name: 'Drive',
    type: PanelType.cover,
    topic: 'on',
    subscribeTopic: '',
    topicPrefixOverride: _binding.openTopic,
    qos: 1,
    retain: true,
    width: PanelWidth.wide,
    sortOrder: 0,
    config: config.encode(),
    mergeFlags: 0,
    createdAt: now,
    updatedAt: now,
  );
  return ProviderScope(
    overrides: [
      mqttManagerProvider.overrideWith((ref, _) async => f.manager),
      connectionStatusProvider.overrideWith((ref, _) => f.status.stream),
      panelValueSnapshotProvider.overrideWith(
        (ref, key) => !feedback
            ? const Stream<PanelValueSnapshot>.empty()
            : key.topic == _binding.closeTopic
            ? f.close.stream
            : f.open.stream,
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Center(
            child: SizedBox(
              width: 290,
              child: PanelTile(
                connectionId: 'c1',
                dashboardId: 'd1',
                topicPrefix: 'unrelated',
                panel: panel,
                locked: true,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  late _Fixture f;
  setUp(() => f = _Fixture());
  tearDown(() => f.dispose());

  for (final action in ['OPEN', 'CLOSE']) {
    testWidgets(
      '$action sends 1 on every tap, including while pending and after pulse feedback',
      (tester) async {
        await tester.pumpWidget(_app(f));
        await _pump(tester);
        final button = find.byKey(ValueKey('wb-cover-$action'));
        final topic = action == 'OPEN'
            ? _binding.openTopic
            : _binding.closeTopic;
        final feedback = action == 'OPEN' ? f.open : f.close;
        final other = action == 'OPEN' ? f.close : f.open;

        await tester.tap(button);
        await _pump(tester);
        await tester.pump(const Duration(seconds: 8));
        await tester.tap(button);
        await _pump(tester);
        expect(f.manager.sent, [
          ('$topic/on', '1', false),
          ('$topic/on', '1', false),
        ]);
        // The second tap starts a new confirmation window.
        await tester.pump(const Duration(seconds: 8));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        other.add(_state('0'));
        feedback.add(_state('invalid'));
        await _pump(tester);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        feedback.add(_state('0', fresh: false));
        await _pump(tester);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        feedback.add(_state('0', old: true));
        await _pump(tester);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        feedback.add(_state('0', generation: 6));
        await _pump(tester);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        // A pulse may have reset to zero before the next MQTT state report.
        feedback.add(_state('0'));
        await _pump(tester);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.tap(button);
        await _pump(tester);
        feedback.add(_state('1'));
        await _pump(tester);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        // An active/highlighted button must also remain repeatable.
        await tester.tap(button);
        await _pump(tester);
        expect(f.manager.sent, List.filled(4, ('$topic/on', '1', false)));
        feedback.add(_state('0'));
        await _pump(tester);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );
  }

  testWidgets(
    'two buttons send scalar non-retained commands; spinner waits for fresh matching feedback',
    (tester) async {
      await tester.pumpWidget(_app(f));
      await _pump(tester);
      expect(find.text('Stop'), findsNothing);
      expect(find.byType(Slider), findsNothing);
      await tester.tap(find.byKey(const ValueKey('wb-cover-OPEN')));
      await _pump(tester);
      expect(f.manager.sent, [('${_binding.openTopic}/on', '1', false)]);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      f.open.add(_state('1', old: true));
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      f.open.add(_state('1', generation: 6));
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      f.open.add(_state('invalid'));
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      f.close.add(_state('0'));
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      f.open.add(_state('1'));
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is CoverButtonGlyph && w.icon == CoverButtonIcon.gatePartial,
        ),
        findsOneWidget,
      );
      f.open.add(_state('0'));
      await _pump(tester);
      expect(f.manager.sent.length, 1);
    },
  );

  testWidgets(
    'reversal tracks the latest direction and ignores acknowledgements for the previous one',
    (tester) async {
      await tester.pumpWidget(_app(f));
      await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('wb-cover-OPEN')));
      await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('wb-cover-CLOSE')));
      await _pump(tester);
      expect(f.manager.sent.map((v) => v.$1), [
        '${_binding.openTopic}/on',
        '${_binding.closeTopic}/on',
      ]);
      f.open.add(_state('1'));
      await _pump(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('wb-cover-CLOSE')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      f.open.add(_state('0'));
      f.close.add(_state('1'));
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'optional Stop and custom titles/icons are rendered and Stop clears both controls',
    (tester) async {
      await tester.pumpWidget(
        _app(
          f,
          config: _config.copyWith(
            openButton: const CoverButtonConfig(
              title: 'Enter',
              icon: CoverButtonIcon.gateOpen,
            ),
            closeButton: const CoverButtonConfig(visible: false),
            stopButton: const CoverButtonConfig(
              title: 'Halt',
              icon: CoverButtonIcon.stop,
            ),
          ),
        ),
      );
      await _pump(tester);
      expect(find.text('Enter'), findsOneWidget);
      expect(find.text('Close'), findsNothing);
      await tester.tap(find.text('Halt'));
      await _pump(tester);
      expect(f.manager.sent, [
        ('${_binding.openTopic}/on', '0', false),
        ('${_binding.closeTopic}/on', '0', false),
      ]);
      f.open.add(_state('0'));
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      f.close.add(_state('0'));
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'missing confirmation times out and disconnect never replays the command',
    (tester) async {
      await tester.pumpWidget(_app(f));
      await _pump(tester);
      await tester.tap(find.text('Open'));
      await _pump(tester);
      await tester.pump(const Duration(seconds: 16));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Not confirmed'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await _pump(tester);
      f.manager.connected = false;
      f.status.add(MqttStatus.disconnected);
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      f.manager.connected = true;
      f.manager.generation = 8;
      f.status.add(MqttStatus.connected);
      f.open.add(_state('0', generation: 8));
      f.close.add(_state('0', generation: 8));
      await _pump(tester);
      expect(f.manager.sent.length, 2);
    },
  );

  testWidgets(
    'connected cover can publish before either feedback topic arrives',
    (tester) async {
      await tester.pumpWidget(_app(f, feedback: false));
      await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('wb-cover-OPEN')));
      await _pump(tester);
      expect(f.manager.sent, [('${_binding.openTopic}/on', '1', false)]);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(seconds: 16));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Not confirmed'), findsOneWidget);
    },
  );

  testWidgets(
    'large text wraps and stale feedback does not block a connected command',
    (tester) async {
      await tester.pumpWidget(_app(f, scale: 2));
      await _pump(tester);
      expect(tester.takeException(), isNull);
      f.open.add(_state('1', fresh: false));
      await _pump(tester);
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('wb-cover-OPEN')),
      );
      expect(button.onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('wb-cover-OPEN')));
      await _pump(tester);
      expect(f.manager.sent, [('${_binding.openTopic}/on', '1', false)]);
      f.open.add(_state('1', fresh: false));
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      f.open.add(_state('1'));
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'JSON covers keep configurable buttons and wait for newer JSON feedback',
    (tester) async {
      final config = const CoverConfig(
        showSlider: false,
        presets: [],
        openButton: CoverButtonConfig(
          title: 'Raise',
          icon: CoverButtonIcon.rollerOpen,
        ),
        closeButton: CoverButtonConfig(visible: false),
        stopButton: CoverButtonConfig(
          title: 'Halt',
          icon: CoverButtonIcon.gatePartial,
        ),
      );
      await tester.pumpWidget(_app(f, config: config));
      await _pump(tester);
      expect(find.text('Raise'), findsOneWidget);
      expect(find.text('Halt'), findsOneWidget);
      expect(find.text('Close'), findsNothing);
      await tester.tap(find.text('Raise'));
      await _pump(tester);
      expect(f.manager.sent.single.$2, '{"state":"OPEN"}');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      f.open.add(_state('{"state":"OPEN"}', old: true));
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      f.open.add(_state('{"state":"OPEN"}'));
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
}
