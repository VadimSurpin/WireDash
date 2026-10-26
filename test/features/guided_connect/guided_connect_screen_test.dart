import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mqtt_client/mqtt_client.dart' as mc;
import 'package:wiredash/core/router/routes.dart';
import 'package:wiredash/core/storage/secure_storage.dart';
import 'package:wiredash/data/database/daos/connection_dao.dart';
import 'package:wiredash/data/database/database.dart';
import 'package:wiredash/data/database/tables/connections.dart';
import 'package:wiredash/data/repositories/connection_repo.dart';
import 'package:wiredash/features/connections/diagnostics/connect_diagnostics.dart';
import 'package:wiredash/features/connections/diagnostics/connect_diagnostics_provider.dart';
import 'package:wiredash/features/connections/discovery/broker_scan_providers.dart';
import 'package:wiredash/features/discovery/models/z2m_device.dart';
import 'package:wiredash/features/discovery/providers/discovery_provider.dart';
import 'package:wiredash/features/guided_connect/guided_connect_screen.dart';
import 'package:wiredash/features/onboarding/first_run.dart';
import 'package:wiredash/l10n/app_localizations.dart';
import 'package:wiredash/mqtt/broker_config.dart';
import 'package:wiredash/mqtt/mqtt_manager.dart';
import 'package:wiredash/mqtt/mqtt_status.dart';
import 'package:wiredash/mqtt/providers/mqtt_manager_provider.dart';

class _MemSecure implements SecureStore {
  final _wireGuard = <String, String>{};
  @override
  Future<String?> readWireGuard(String id) async => _wireGuard[id];
  @override
  Future<void> writeWireGuard(String id, String config) async =>
      _wireGuard[id] = config;
  @override
  Future<void> deleteWireGuard(String id) async => _wireGuard.remove(id);

  final _m = <String, String>{};

  @override
  Future<void> writePassword(String id, String pw) async => _m[id] = pw;

  @override
  Future<String?> readPassword(String id) async => _m[id];

  @override
  Future<void> deletePassword(String id) async => _m.remove(id);
}

/// Fake diagnostics that replays a queue of reports (last one repeats).
class _FakeDiagnostics extends ConnectDiagnostics {
  _FakeDiagnostics(this.results);

  final List<DiagnosticsReport> results;
  int calls = 0;
  BrokerConfig? lastConfig;

  @override
  Future<DiagnosticsReport> run({
    required BrokerConfig config,
    required String password,
    String base = 'zigbee2mqtt',
  }) async {
    lastConfig = config;
    final i = calls < results.length ? calls : results.length - 1;
    calls++;
    return results[i];
  }
}

class _StubManager extends MqttManager {
  _StubManager()
    : super(
        config: const BrokerConfig(
          id: 'x',
          host: 'h',
          port: 1883,
          protocol: MqttProtocol.tcp,
        ),
        password: '',
      );

  final publishedTopics = <String>[];

  @override
  void publish(
    String topic,
    String template,
    Object value, {
    mc.MqttQos qos = mc.MqttQos.atLeastOnce,
    bool retain = false,
  }) {
    publishedTopics.add(topic);
  }
}

DiagnosticsReport _failedReport() => const DiagnosticsReport(
  steps: [
    StepResult(step: DiagnosticStep.resolve, status: StepStatus.pass),
    StepResult(step: DiagnosticStep.tcp, status: StepStatus.pass),
    StepResult(
      step: DiagnosticStep.connack,
      status: StepStatus.fail,
      detailKey: 'diagConnackFail',
    ),
  ],
  connected: false,
  candidatesTried: 1,
);

/// The two devices behind [_successReport], as Zigbee2MQTT publishes them
/// on `bridge/devices`, parsed by the app's own parser.
final _devicesOverride = discoveredDevicesProvider.overrideWith(
  (ref, args) async => parseBridgeDevices(
    jsonEncode([
      for (final (name, ieee) in [('office_light', '0x01'), ('lamp', '0x02')])
        {
          'friendly_name': name,
          'ieee_address': ieee,
          'type': 'Router',
          'supported': true,
          'definition': {
            'model': 'LED1545G12',
            'vendor': 'IKEA',
            'exposes': [
              {
                'type': 'light',
                'features': [
                  {
                    'type': 'binary',
                    'name': 'state',
                    'property': 'state',
                    'access': 7,
                    'value_on': 'ON',
                    'value_off': 'OFF',
                  },
                ],
              },
            ],
          },
        },
    ]),
  ),
);

DiagnosticsReport _successReport({int count = 2}) => DiagnosticsReport(
  steps: [
    for (final s in DiagnosticStep.values)
      StepResult(
        step: s,
        status: StepStatus.pass,
        deviceCount: s == DiagnosticStep.devices ? count : null,
      ),
  ],
  connected: true,
  candidatesTried: 1,
  deviceNames: count > 0 ? ['office_light', 'lamp'] : const [],
);

class _RecordingFirstRun implements FirstRun {
  final finished = <String>[];
  @override
  Future<void> finish(String connectionId) async => finished.add(connectionId);
  @override
  Future<String> startDemo() async => 'demo';
}

var _firstRun = _RecordingFirstRun();

/// The form grew in 2.5 (hints, Get help); a tall view keeps every control
/// built and tappable.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

GoRouter _router() => GoRouter(
  initialLocation: Routes.guidedConnect,
  routes: [
    GoRoute(
      path: Routes.guidedConnect,
      // The ladder tests run against a filled-in host (2.5: the form
      // itself starts empty; see 'starts empty, with hints').
      builder: (_, __) => const GuidedConnectScreen(initialHost: 'localhost'),
    ),
    GoRoute(
      path: '/connections/:id/dashboards',
      builder: (_, __) => const Scaffold(body: Text('STUB_DASHBOARDS')),
    ),
  ],
);

Widget _wrap({
  required AppDatabase db,
  required ConnectDiagnostics diagnostics,
  Map<dynamic, dynamic> extraOverrides = const {},
}) {
  final overrides = <Override>[
    appDatabaseProvider.overrideWithValue(db),
    secureStorageProvider.overrideWithValue(_MemSecure()),
    connectionRepoProvider.overrideWith(
      (ref) => ConnectionRepo(
        ConnectionDao(ref.read(appDatabaseProvider)),
        ref.read(secureStorageProvider),
      ),
    ),
    connectDiagnosticsProvider.overrideWithValue(diagnostics),
    firstRunProvider.overrideWithValue(_firstRun),
    deviceIpProvider.overrideWith((ref) async => '192.168.1.37'),
    ...extraOverrides.values,
  ];
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      routerConfig: _router(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

void main() {
  setUp(() => _firstRun = _RecordingFirstRun());

  for (final invalid in [false, true]) {
    testWidgets(
      'initial WireGuard form ${invalid ? 'rejects invalid configuration' : 'persists and probes the tunnel'}',
      (tester) async {
        _tall(tester);
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const channel = MethodChannel('zigdash/wireguard');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (invalid) throw PlatformException(code: 'invalid');
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final db = AppDatabase.test(NativeDatabase.memory());
        addTearDown(db.close);
        final storage = _MemSecure();
        final diagnostics = _FakeDiagnostics([_successReport(count: 0)]);
        await tester.pumpWidget(
          _wrap(
            db: db,
            diagnostics: diagnostics,
            extraOverrides: {
              'storage': secureStorageProvider.overrideWithValue(storage),
              'status': connectionStatusProvider.overrideWith(
                (ref, _) => Stream.value(MqttStatus.disconnected),
              ),
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Use embedded WireGuard'), findsOneWidget);
        await tester.tap(find.text('Use embedded WireGuard'));
        await tester.pumpAndSettle();
        final field = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'WireGuard configuration',
        );
        const configuration =
            '[Interface]\nPrivateKey = test\nAddress = 10.0.0.2/32\n[Peer]\nEndpoint = example.com:51820';
        await tester.enterText(field, configuration);
        final connect = find.text('Test & connect');
        await tester.ensureVisible(connect);
        await tester.pumpAndSettle();
        await tester.tap(connect);
        await tester.pumpAndSettle();
        if (invalid) {
          expect(
            find.text(
              'Invalid WireGuard configuration. Check the configuration file and try again.',
            ),
            findsOneWidget,
          );
          expect(diagnostics.calls, 0);
          expect(await db.select(db.connections).get(), isEmpty);
        } else {
          expect(diagnostics.lastConfig!.viaWireGuard, isTrue);
          expect(diagnostics.lastConfig!.wireGuardConfig, configuration);
          final saved = (await db.select(db.connections).get()).single;
          expect(saved.transport, ConnectionTransport.wireGuard);
          expect(await storage.readWireGuard(saved.id), configuration);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  // 2.5: an empty host, with where to find it, instead of "localhost".
  testWidgets('starts empty, with hints on where the address is', (
    tester,
  ) async {
    _tall(tester);
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceIpProvider.overrideWith((ref) async => '192.168.1.37'),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GuidedConnectScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('localhost'), findsNothing);
    expect(
      find.text(
        'Your phone is 192.168.1.37, so the hub usually starts with 192.168.1.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Using Home Assistant? The host'),
      findsOneWidget,
    );
    expect(find.text('Still stuck? Get help'), findsOneWidget);

    await tester.tap(find.text('Test & connect'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsWidgets);
  });

  testWidgets('a hub the scan found arrives filled in', (tester) async {
    _tall(tester);
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GuidedConnectScreen(
            initialHost: '192.168.1.20',
            initialPort: 1883,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('192.168.1.20'), findsOneWidget);
    expect(find.text('1883'), findsOneWidget);
  });

  testWidgets('preset pre-fills host, port and base topic', (tester) async {
    _tall(tester);
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final fake = _FakeDiagnostics([_successReport()]);

    await tester.pumpWidget(_wrap(db: db, diagnostics: fake));
    await tester.pumpAndSettle();

    expect(find.text('localhost'), findsOneWidget);
    expect(find.text('1883'), findsOneWidget);
    // Value and hint both read "zigbee2mqtt" — accept either.
    expect(find.text('zigbee2mqtt'), findsWidgets);
    expect(find.text('Test & connect'), findsOneWidget);
    expect(fake.calls, 0);
  });

  testWidgets('empty host blocks the run and shows validation', (tester) async {
    _tall(tester);
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final fake = _FakeDiagnostics([_successReport()]);

    await tester.pumpWidget(_wrap(db: db, diagnostics: fake));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Local host'),
      '',
    );
    await tester.tap(find.text('Test & connect'));
    await tester.pumpAndSettle();

    expect(find.text('Required'), findsWidgets);
    expect(fake.calls, 0);
  });

  testWidgets('failed ladder shows the failing step, detail and actions', (
    tester,
  ) async {
    _tall(tester);
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final fake = _FakeDiagnostics([_failedReport()]);

    await tester.pumpWidget(_wrap(db: db, diagnostics: fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Test & connect'));
    await tester.pumpAndSettle();

    expect(find.text('MQTT handshake'), findsOneWidget);
    expect(
      find.textContaining("didn't complete the MQTT handshake"),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Edit settings'), findsOneWidget);

    // Back to the form keeps the entered values.
    await tester.tap(find.text('Edit settings'));
    await tester.pumpAndSettle();
    expect(find.text('localhost'), findsOneWidget);
  });

  testWidgets('after two failed checks a person is offered (2.9.2)', (
    tester,
  ) async {
    _tall(tester);
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final fake = _FakeDiagnostics([_failedReport(), _failedReport()]);

    await tester.pumpWidget(_wrap(db: db, diagnostics: fake));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test & connect'));
    await tester.pumpAndSettle();
    expect(find.text('Stuck? Ask a person'), findsNothing, reason: 'one try');

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Stuck? Ask a person'), findsOneWidget);
    expect(find.text('WireDash on GitHub'), findsOneWidget);
    expect(find.text('Tips and email'), findsOneWidget);
  });

  testWidgets('retry re-runs the ladder and can reach success', (tester) async {
    _tall(tester);
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final fake = _FakeDiagnostics([_failedReport(), _successReport()]);

    await tester.pumpWidget(_wrap(db: db, diagnostics: fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Test & connect'));
    await tester.pumpAndSettle();
    expect(find.text('MQTT handshake'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Found 2 devices'), findsOneWidget);
    expect(fake.calls, 2);
  });

  testWidgets('success saves the connection and shows device names', (
    tester,
  ) async {
    _tall(tester);
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final fake = _FakeDiagnostics([_successReport()]);

    await tester.pumpWidget(
      _wrap(
        db: db,
        diagnostics: fake,
        extraOverrides: {'devices': _devicesOverride},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Test & connect'));
    await tester.pumpAndSettle();

    expect(find.text('Found 2 devices'), findsOneWidget);
    expect(find.text('office_light'), findsOneWidget);
    expect(find.text('lamp'), findsOneWidget);
    expect(find.text('Continue to dashboard'), findsOneWidget);

    // Continue navigates to the saved connection's dashboards (proving the
    // auto-save persisted a row the router can resolve).
    await tester.tap(find.text('Continue to dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('STUB_DASHBOARDS'), findsOneWidget);
    // Manual entry also finishes first run with the saved home.
    expect(_firstRun.finished, hasLength(1));

    // …and builds the first dashboard from the devices, as setup does,
    // instead of opening an empty home.
    final dashboards = await db.select(db.dashboards).get();
    expect(dashboards, hasLength(1));
    final tiles = await db.select(db.panels).get();
    expect(tiles, hasLength(2));
    // Unmount here so drift's stream-close timer runs inside the test.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('continue still opens the home when devices cannot be read', (
    tester,
  ) async {
    _tall(tester);
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final fake = _FakeDiagnostics([_successReport()]);

    await tester.pumpWidget(
      _wrap(
        db: db,
        diagnostics: fake,
        extraOverrides: {
          'devices': discoveredDevicesProvider.overrideWith(
            (ref, args) async => throw StateError('offline'),
          ),
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test & connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to dashboard'));
    await tester.pumpAndSettle();

    expect(find.text('STUB_DASHBOARDS'), findsOneWidget);
    expect(await db.select(db.dashboards).get(), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('zero devices flags the state and offers pairing', (
    tester,
  ) async {
    _tall(tester);
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final fake = _FakeDiagnostics([_successReport(count: 0)]);
    final stubManager = _StubManager();
    final overrides = <Override>[
      mqttManagerProvider.overrideWith((ref, id) async => stubManager),
      connectionStatusProvider.overrideWith(
        (ref, id) => Stream.value(MqttStatus.connected),
      ),
    ];

    await tester.pumpWidget(
      _wrap(
        db: db,
        diagnostics: fake,
        extraOverrides: {'mgr': overrides[0], 'status': overrides[1]},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Test & connect'));
    await tester.pumpAndSettle();

    expect(find.text('Connected — no devices found yet'), findsOneWidget);
    expect(find.text('Start pairing'), findsOneWidget);

    await tester.tap(find.text('Start pairing'));
    await tester.pumpAndSettle();

    expect(
      stubManager.publishedTopics,
      contains('zigbee2mqtt/bridge/request/permit_join'),
    );
    expect(
      find.text(
        'Pairing is enabled. Press the pairing button on your device to join it.',
      ),
      findsOneWidget,
    );
  });
}
