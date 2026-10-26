import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/features/pro/pro.dart';
import 'package:wiredash/features/pro/pro_screen.dart';
import 'package:wiredash/l10n/app_localizations.dart';

Future<void> _pump(
  WidgetTester tester, {
  required ProStatus status,
  VoidCallback? buy,
  String? price,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        proStatusProvider.overrideWithValue(status),
        proPurchaseProvider.overrideWithValue(buy),
        proPriceProvider.overrideWith((ref) async => price),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProScreen(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  // 2.9.6: Unlock used to open Play's sheet straight away; now Pro says
  // what it adds, what stays free, and why it exists, first.
  testWidgets('says what Pro adds and what stays free, with Play\'s price', (
    tester,
  ) async {
    var bought = 0;
    await _pump(
      tester,
      status: ProStatus.locked,
      buy: () => bought++,
      price: '€7.99',
    );
    expect(find.textContaining('open source'), findsOneWidget);
    expect(
      find.text('History for 7 and 30 days, not just today'),
      findsOneWidget,
    );
    expect(find.text('Free forever'), findsOneWidget);
    await tester.tap(find.text('Get Pro · €7.99'));
    expect(bought, 1);
  });

  testWidgets('no price from Play: the button still works', (tester) async {
    await _pump(tester, status: ProStatus.locked, buy: () {});
    expect(find.text('Get Pro'), findsOneWidget);
  });

  testWidgets('bought: thanks, and nothing to buy', (tester) async {
    await _pump(tester, status: ProStatus.unlocked);
    expect(
      find.text('Unlocked. Thank you for supporting WireDash.'),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsNothing);
  });
}
