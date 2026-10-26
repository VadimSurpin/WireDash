import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:wiredash/core/router/routes.dart';
import 'package:wiredash/data/database/database.dart';
import 'package:wiredash/data/database/tables/connections.dart';
import 'package:wiredash/data/repositories/connection_repo.dart';
import 'package:wiredash/features/devices/device_registry.dart';
import 'package:wiredash/features/devices/devices_providers.dart';
import 'package:wiredash/features/history/app_history_recorder.dart';
import 'package:wiredash/features/home/home_shell.dart';
import 'package:wiredash/features/settings/providers/settings_controller.dart';
import 'package:wiredash/l10n/app_localizations.dart';

final _stamp = DateTime(2026, 9, 26);
Connection _home(String id, String name) => Connection(
  transport: ConnectionTransport.mqtt,
  id: id,
  name: name,
  host: 'h',
  port: 1883,
  protocol: MqttProtocol.tcp,
  keepAliveSeconds: 60,
  autoConnect: true,
  createdAt: _stamp,
  updatedAt: _stamp,
);

Widget _app(
  List<Connection> homes, {
  int newDevices = 0,
  Set<String> lowBatteries = const {},
  Locale? locale,
}) {
  Widget page(String label, String id) => Scaffold(
    appBar: AppBar(title: HomeTitle(connectionId: id)),
    body: Text(label),
  );
  GoRoute tab(String name) => GoRoute(
    path: '/connections/:id/$name',
    builder: (_, s) =>
        page('$name ${s.pathParameters['id']}', s.pathParameters['id']!),
  );
  final router = GoRouter(
    initialLocation: Routes.homeDashboards('c1'),
    routes: [
      ShellRoute(
        builder: (_, state, child) => HomeShell(
          connectionId: state.pathParameters['id']!,
          location: state.matchedLocation,
          child: child,
        ),
        routes: [
          tab('dashboards'),
          tab('devices'),
          tab('scenes'),
          tab('automations'),
        ],
      ),
      GoRoute(path: Routes.setup, builder: (_, __) => const Text('setup')),
      GoRoute(path: Routes.settings, builder: (_, __) => const Text('homes')),
    ],
  );
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(_prefs),
      connectionsStreamProvider.overrideWith((ref) => Stream.value(homes)),
      unassignedCountProvider.overrideWith(
        (ref, _) => AsyncValue.data(newDevices),
      ),
      homeBaseTopicProvider.overrideWith((ref, _) => null),
      batteryAlertsProvider.overrideWith(
        (ref, _) => Stream.value(lowBatteries),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

late SharedPreferences _prefs;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  testWidgets('the history recorder lives with the home, not a tab (2.9.1)', (
    tester,
  ) async {
    await tester.pumpWidget(_app([_home('c1', 'My Home')]));
    await tester.pumpAndSettle();
    final first = tester.state(find.byType(AppHistoryRecorder));
    await tester.tap(find.text('Devices'));
    await tester.pumpAndSettle();
    expect(find.text('devices c1'), findsOneWidget);
    expect(
      tester.state(find.byType(AppHistoryRecorder)),
      same(first),
      reason: 'switching tabs must not restart (or stop) recording',
    );
  });

  testWidgets('one home: plain name, no switcher', (tester) async {
    await tester.pumpWidget(_app([_home('c1', 'My Home')]));
    await tester.pumpAndSettle();
    expect(find.text('My Home'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
  });

  testWidgets('two homes: the name switches home; tabs follow the home', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app([_home('c1', 'My Home'), _home('c2', 'SMHUB')]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Home'));
    await tester.pumpAndSettle();
    expect(find.text('Add a home'), findsOneWidget);
    expect(find.text('Manage homes'), findsOneWidget);
    await tester.tap(find.text('SMHUB').last);
    await tester.pumpAndSettle();
    expect(find.text('dashboards c2'), findsOneWidget);

    await tester.tap(find.text('Scenes'));
    await tester.pumpAndSettle();
    expect(find.text('scenes c2'), findsOneWidget);
  });

  testWidgets('the Devices destination carries a dot for new devices', (
    tester,
  ) async {
    await tester.pumpWidget(_app([_home('c1', 'My Home')], newDevices: 2));
    await tester.pumpAndSettle();
    final badges = tester.widgetList<Badge>(find.byType(Badge));
    expect(badges.any((b) => b.isLabelVisible), isTrue);
  });

  testWidgets('a battery that went low also lights the dot, and says so', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app([_home('c1', 'My Home')], lowBatteries: {'0x01'}),
    );
    await tester.pumpAndSettle();
    final badges = tester.widgetList<Badge>(find.byType(Badge));
    expect(badges.first.isLabelVisible, isTrue);
    final devices =
        tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations[1]
            as NavigationDestination;
    expect(devices.tooltip, 'Devices, Battery low');
  });

  testWidgets('from 600 dp a navigation rail replaces the bar, dot included', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app([_home('c1', 'My Home')], newDevices: 1));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    // TalkBack reaches the rail beside the page (regression: the page's
    // route hid it).
    expect(find.bySemanticsLabel(RegExp('^Scenes')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Devices')), findsOneWidget);
    expect(
      tester.widgetList<Badge>(find.byType(Badge)).first.isLabelVisible,
      isTrue,
    );
    await tester.tap(find.text('Scenes'));
    await tester.pumpAndSettle();
    expect(find.text('scenes c1'), findsOneWidget);
  });

  testWidgets('Automations is a tab of its own (3.1.1)', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app([_home('c1', 'My Home')]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Automations'));
    await tester.pumpAndSettle();
    expect(find.text('automations c1'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
  });

  testWidgets('four tabs fit a narrow phone in the longest languages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final l in const ['es', 'fr', 'nl', 'ru', 'de']) {
      await tester.pumpWidget(
        _app([_home('c1', 'My Home')], locale: Locale(l)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: l);
    }
  });
}
