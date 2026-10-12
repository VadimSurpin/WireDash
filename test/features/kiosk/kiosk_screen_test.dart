import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zigdash/alerts/alerts_service.dart';
import 'package:zigdash/core/analytics/analytics.dart';
import 'package:zigdash/data/database/database.dart';
import 'package:zigdash/data/database/tables/connections.dart';
import 'package:zigdash/data/repositories/connection_repo.dart';
import 'package:zigdash/data/repositories/dashboard_repo.dart';
import 'package:zigdash/data/repositories/panel_repo.dart';
import 'package:zigdash/data/repositories/section_repo.dart';
import 'package:zigdash/features/dashboards/screens/dashboards_screen.dart';
import 'package:zigdash/features/dashboards/wall_display.dart';
import 'package:zigdash/features/devices/device_state_refresher.dart';
import 'package:zigdash/features/devices/devices_providers.dart';
import 'package:zigdash/features/kiosk/kiosk.dart';
import 'package:zigdash/features/kiosk/wall_display_sheet.dart';
import 'package:zigdash/features/settings/providers/settings_controller.dart';
import 'package:zigdash/l10n/app_localizations.dart';
import 'package:zigdash/mqtt/mqtt_status.dart';
import 'package:zigdash/mqtt/providers/mqtt_manager_provider.dart';

import 'kiosk_test.dart' show FakeKioskPinStore;

final _stamp = DateTime(2026, 10, 12);

final _home = Connection(
  id: 'c1',
  name: 'My Home',
  host: '192.168.1.5',
  port: 1883,
  protocol: MqttProtocol.tcp,
  keepAliveSeconds: 60,
  autoConnect: true,
  createdAt: _stamp,
  updatedAt: _stamp,
);

Dashboard _dash(String id, String name) => Dashboard(
  id: id,
  connectionId: 'c1',
  name: name,
  topicPrefix: 'zigbee2mqtt',
  colorSeed: 0xFF3B82F6,
  iconCodepoint: 0xe318,
  locked: false,
  sortOrder: 0,
  createdAt: _stamp,
  updatedAt: _stamp,
);

class _Sink implements AnalyticsSink {
  final sent = <Map<String, String>>[];
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  void send(String name, Map<String, String> props) =>
      sent.add({'name': name, ...props});
}

class _Wake extends ScreenWake {
  final lockCalls = <bool>[];
  final fullscreenCalls = <bool>[];
  @override
  Future<void> keepOn(bool on) async {}
  @override
  Future<void> fullscreen(bool on) async => fullscreenCalls.add(on);
  @override
  Future<void> dim(bool on) async {}
  @override
  Future<bool> lockTask(bool on) async {
    lockCalls.add(on);
    return true;
  }
}

void main() {
  late SharedPreferences prefs;
  late FakeKioskPinStore pins;
  late _Sink sink;
  late _Wake wake;

  Future<void> setPrefs(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    prefs = await SharedPreferences.getInstance();
  }

  setUp(() async {
    await setPrefs({'analytics_consent': true});
    pins = FakeKioskPinStore();
    sink = _Sink();
    wake = _Wake();
  });

  Widget app() => ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      kioskPinStoreProvider.overrideWithValue(pins),
      analyticsSinkProvider.overrideWithValue(sink),
      analyticsAvailableProvider.overrideWithValue(true),
      screenWakeProvider.overrideWithValue(wake),
      appDatabaseProvider.overrideWith((ref) {
        final db = AppDatabase.test(NativeDatabase.memory());
        ref.onDispose(db.close);
        return db;
      }),
      connectionsStreamProvider.overrideWith((ref) => Stream.value([_home])),
      connectionByIdProvider.overrideWith((ref, _) async => _home),
      dashboardsForConnectionProvider.overrideWith(
        (ref, _) =>
            Stream.value([_dash('d1', 'Living'), _dash('d2', 'Garden')]),
      ),
      sectionsForDashboardProvider.overrideWith(
        (ref, _) => Stream<List<Section>>.value(const []),
      ),
      panelsForDashboardProvider.overrideWith(
        (ref, _) => Stream<List<Panel>>.value(const []),
      ),
      connectionStatusProvider.overrideWith(
        (ref, _) => Stream.value(MqttStatus.connected),
      ),
      mqttManagerProvider.overrideWith((ref, _) => Completer<Never>().future),
      alertsConfigProvider.overrideWith((ref, _) => Stream.value(null)),
      deviceStateRefresherProvider.overrideWith(
        (ref, _) => Completer<DeviceStateRefresher>().future,
      ),
      batteryWatchProvider.overrideWith((ref, _) {}),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const DashboardsScreen(connectionId: 'c1'),
    ),
  );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(app());
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('outside kiosk the header has its actions and the menu opens '
      'the Wall display sheet', (tester) async {
    await pump(tester);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.text('Add tile'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wall display'));
    await tester.pumpAndSettle();
    expect(find.byType(WallDisplaySheet), findsOneWidget);
    expect(find.text('Kiosk lock'), findsOneWidget);
    expect(find.text('Fullscreen'), findsOneWidget);
    expect(
      find.text('Export backup', skipOffstage: false),
      findsOneWidget,
      reason: 'offered before a PIN is set',
    );
  });

  testWidgets('turning the Kiosk lock on starts kiosk with fullscreen and a '
      '5-minute dim, closes the sheet and is measured', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wall display'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kiosk lock'));
    await tester.pumpAndSettle();

    expect(prefs.getString('kiosk_dashboard'), 'd1');
    expect(prefs.getBool('wall_fullscreen_d1'), isTrue);
    expect(prefs.getInt('wall_dim_d1'), 5);
    expect(find.byType(WallDisplaySheet), findsNothing);
    expect(
      find.text('Kiosk on. Long-press the title to leave.'),
      findsOneWidget,
    );
    expect(sink.sent.where((e) => e['feature'] == 'kiosk').single, {
      'name': 'feature_used',
      'feature': 'kiosk',
      'lock': 'none',
      'os_pin': 'no',
      'dim': '5m',
    });
    // The header lost its actions and the add-tile button; tabs stay.
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.text('Add tile'), findsNothing);
    expect(find.text('Garden'), findsOneWidget);
  });

  testWidgets('in kiosk a long-press on the title asks to leave; Stay keeps '
      'it, Leave ends it', (tester) async {
    await setPrefs({'kiosk_connection': 'c1', 'kiosk_dashboard': 'd1'});
    await pump(tester);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);

    await tester.longPress(find.text('My Home'));
    await tester.pumpAndSettle();
    expect(find.text('Leave kiosk?'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(prefs.getString('kiosk_dashboard'), 'd1');

    await tester.longPress(find.text('My Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(prefs.getString('kiosk_dashboard'), isNull);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });

  testWidgets('with a PIN set, leaving asks for it and refuses a wrong one', (
    tester,
  ) async {
    await setPrefs({'kiosk_connection': 'c1', 'kiosk_dashboard': 'd1'});
    pins.pin = '2468';
    await pump(tester);

    await tester.longPress(find.text('My Home'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the PIN'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '1111');
    await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong PIN.'), findsOneWidget);
    expect(prefs.getString('kiosk_dashboard'), 'd1');

    await tester.tap(find.text('Forgot the PIN?'));
    await tester.pumpAndSettle();
    expect(find.textContaining("clearing ZigDash's data"), findsOneWidget);

    await tester.enterText(find.byType(TextField), '2468');
    await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
    await tester.pumpAndSettle();
    expect(prefs.getString('kiosk_dashboard'), isNull);
  });

  testWidgets('OS pinning is asked for when chosen, and released on leaving', (
    tester,
  ) async {
    await setPrefs({
      'kiosk_connection': 'c1',
      'kiosk_dashboard': 'd1',
      'kiosk_os_pinning': true,
      'wall_fullscreen_d1': true,
    });
    await pump(tester);
    expect(wake.lockCalls, [true]);
    expect(wake.fullscreenCalls, [true]);

    // A sibling dashboard is allowed, and stays pinned and fullscreen.
    await tester.tap(find.text('Garden'));
    await tester.pumpAndSettle();
    expect(wake.lockCalls, [true], reason: 'kiosk is app-wide');
    expect(wake.fullscreenCalls, [true]);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);

    await tester.longPress(find.text('My Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(wake.lockCalls, [true, false]);
  });
}
