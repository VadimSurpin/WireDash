import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wiredash/data/database/database.dart';
import 'package:wiredash/data/database/tables/panels.dart';
import 'package:wiredash/data/repositories/panel_repo.dart';
import 'package:wiredash/features/panels/models/panel_config.dart';
import 'package:wiredash/features/panels/widgets/tile_actions_sheet.dart';
import 'package:wiredash/features/dashboards/edit_mode.dart';
import 'package:wiredash/l10n/app_localizations.dart';

class _UnusedPanelRepo implements PanelRepo {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Edit from the tile actions opens the existing panel route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final stamp = DateTime(2026);
    final panel = Panel(
      id: 'panel-1',
      dashboardId: 'dashboard-1',
      name: 'Gate',
      type: PanelType.cover,
      topic: '/devices/gate/controls/Open/on',
      width: PanelWidth.small,
      sortOrder: 0,
      qos: 1,
      retain: false,
      config: const CoverConfig().encode(),
      mergeFlags: 0,
      createdAt: stamp,
      updatedAt: stamp,
    );
    final rootKey = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: rootKey,
      initialLocation: '/connections/connection-1/dashboards',
      routes: [
        ShellRoute(
          builder: (_, _, child) => Scaffold(body: child),
          routes: [
            GoRoute(
              path: '/connections/:id/dashboards',
              builder: (context, state) => Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    if (ref.watch(editModeProvider) != null) {
                      return const Text('Edit mode replaced the source tile');
                    }
                    return TextButton(
                      onPressed: () {
                        ref
                            .read(editModeProvider.notifier)
                            .enter('dashboard-1');
                        showTileActions(
                          context,
                          ref,
                          connectionId: 'connection-1',
                          panel: panel,
                        );
                      },
                      child: const Text('Actions'),
                    );
                  },
                ),
              ),
              routes: [
                GoRoute(
                  parentNavigatorKey: rootKey,
                  path: ':dashboardId/panels/:panelId/edit',
                  builder: (_, state) => Scaffold(
                    body: Text('Editing ${state.pathParameters['panelId']}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [panelRepoProvider.overrideWithValue(_UnusedPanelRepo())],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Edit mode replaced the source tile'), findsOneWidget);
    await tester.ensureVisible(find.text('Remove from dashboard'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Remove from dashboard')).dy,
      lessThan(360),
    );
    await tester.ensureVisible(find.text('Edit tile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit tile'));
    await tester.pumpAndSettle();
    expect(find.text('Editing panel-1'), findsOneWidget);
  });
}
