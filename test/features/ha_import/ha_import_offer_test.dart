import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zigdash/features/ha_import/ha_import_offer.dart';
import 'package:zigdash/features/settings/providers/settings_controller.dart';
import 'package:zigdash/l10n/app_localizations.dart';

Future<(ProviderContainer, List<String>)> _pump(
  WidgetTester tester, {
  String? offered,
}) async {
  SharedPreferences.setMockInitialValues({HaImportOffer.key: ?offered});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  final pushed = <String>[];
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) =>
            const Scaffold(body: HaImportOfferCard(connectionId: 'c1')),
      ),
      GoRoute(
        path: '/settings/home/:id/ha-import',
        builder: (_, state) {
          pushed.add(state.uri.path);
          return const Scaffold();
        },
      ),
    ],
  );
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
  await tester.pumpAndSettle();
  return (container, pushed);
}

void main() {
  testWidgets('shown only for the home it was offered for', (tester) async {
    await _pump(tester, offered: 'other');
    expect(find.text('Import'), findsNothing);
  });

  testWidgets('Not now ends the offer', (tester) async {
    final (c, _) = await _pump(tester, offered: 'c1');
    expect(
      find.text('Bring your names and rooms from Home Assistant?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Import'), findsNothing);
    expect(
      c.read(sharedPreferencesProvider).getString(HaImportOffer.key),
      isNull,
    );
  });

  testWidgets('Import opens the import and ends the offer', (tester) async {
    final (c, pushed) = await _pump(tester, offered: 'c1');
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(pushed, ['/settings/home/c1/ha-import']);
    expect(c.read(haImportOfferProvider), isNull);
  });
}
