import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/data/repositories/connection_repo.dart';
import 'package:wiredash/data/repositories/dashboard_repo.dart';
import 'package:wiredash/features/dashboards/screens/dashboards_screen.dart';
import 'package:wiredash/l10n/app_localizations.dart';
import 'package:wiredash/mqtt/mqtt_status.dart';
import 'package:wiredash/mqtt/providers/mqtt_manager_provider.dart';

void main() {
  testWidgets('failed reconnect shows feedback without an uncaught exception', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionByIdProvider.overrideWith((ref, id) async => null),
          dashboardsForConnectionProvider.overrideWith(
            (ref, id) => Stream.value([]),
          ),
          connectionStatusProvider.overrideWith(
            (ref, id) => Stream.value(MqttStatus.reconnecting),
          ),
          mqttManagerProvider.overrideWith(
            (ref, id) =>
                Future.error(StateError('manager construction failed')),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DashboardsScreen(connectionId: 'c1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Reconnect now lives behind the status line's "Why?".
    await tester.tap(find.text('Why?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reconnect now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Connection failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
