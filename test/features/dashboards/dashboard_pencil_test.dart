import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiredash/data/database/database.dart';
import 'package:wiredash/data/database/tables/connections.dart';
import 'package:wiredash/data/repositories/connection_repo.dart';
import 'package:wiredash/data/repositories/dashboard_repo.dart';
import 'package:wiredash/data/repositories/panel_repo.dart';
import 'package:wiredash/features/dashboards/edit_mode.dart';
import 'package:wiredash/features/dashboards/screens/dashboards_screen.dart';
import 'package:wiredash/features/devices/device_registry.dart';
import 'package:wiredash/features/devices/devices_providers.dart';
import 'package:wiredash/features/history/history_service.dart';
import 'package:wiredash/features/settings/providers/settings_controller.dart';
import 'package:wiredash/l10n/app_localizations.dart';
import 'package:wiredash/mqtt/mqtt_status.dart';
import 'package:wiredash/mqtt/providers/mqtt_manager_provider.dart';

void main() {
  final stamp = DateTime(2026);
  late AppDatabase database;

  setUpAll(() => database = AppDatabase.test(NativeDatabase.memory()));
  tearDownAll(() => database.close());

  Future<(ProviderContainer, GoRouter)> showDashboard(
    WidgetTester tester, {
    required bool locked,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final dashboard = Dashboard(
      id: 'd1',
      connectionId: 'c1',
      name: 'Home',
      topicPrefix: null,
      colorSeed: 0xFF3B82F6,
      iconCodepoint: Icons.home.codePoint,
      locked: locked,
      sortOrder: 0,
      createdAt: stamp,
      updatedAt: stamp,
    );
    final connection = Connection(
      transport: ConnectionTransport.mqtt,
      id: 'c1',
      name: 'Home',
      host: '192.168.1.10',
      port: 1883,
      protocol: MqttProtocol.tcp,
      keepAliveSeconds: 60,
      autoConnect: true,
      createdAt: stamp,
      updatedAt: stamp,
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(prefs),
        connectionByIdProvider.overrideWith((ref, id) async => connection),
        connectionsStreamProvider.overrideWith(
          (ref) => Stream.value([connection]),
        ),
        homeBaseTopicProvider.overrideWith((ref, id) => null),
        dashboardsForConnectionProvider.overrideWith(
          (ref, id) => Stream.value([dashboard]),
        ),
        panelsForDashboardProvider.overrideWith((ref, id) => Stream.value([])),
        unassignedDevicesProvider.overrideWith(
          (ref, id) => const AsyncValue.data([]),
        ),
        historyRecorderOnlineProvider.overrideWith(
          (ref, id) => Stream.value(false),
        ),
        connectionStatusProvider.overrideWith(
          (ref, id) => Stream.value(MqttStatus.connected),
        ),
      ],
    );
    final router = GoRouter(
      initialLocation: '/connections/c1/dashboards',
      routes: [
        GoRoute(
          path: '/connections/:id/dashboards',
          builder: (_, _) => const DashboardsScreen(connectionId: 'c1'),
          routes: [
            GoRoute(
              path: ':dashboardId/edit',
              builder: (_, _) => const Scaffold(body: Text('Dashboard form')),
            ),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return (container, router);
  }

  testWidgets('pencil enters edit mode on an unlocked dashboard', (
    tester,
  ) async {
    final (container, _) = await showDashboard(tester, locked: false);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();

    expect(container.read(editModeProvider), 'd1');
    expect(find.text('Done'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pencil opens settings to unlock a locked dashboard', (tester) async {
    final (container, _) = await showDashboard(tester, locked: true);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(container.read(editModeProvider), isNull);
    expect(find.text('Dashboard form'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
