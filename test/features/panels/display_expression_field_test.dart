import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/features/panels/widgets/display_expression_field.dart';
import 'package:zigdash/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'the editor previews expressions and rejects malformed JavaScript',
    (tester) async {
      final form = GlobalKey<FormState>();
      String? expression;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Form(
                key: form,
                child: SingleChildScrollView(
                  child: DisplayExpressionField(
                    onChanged: (value) => expression = value,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Before display (JavaScript)'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('display-expression'));
      await tester.enterText(field, '(Number(value) / 100).toFixed(2)');
      await tester.enterText(
        find.byKey(const ValueKey('display-expression-sample')),
        '1230',
      );
      await tester.tap(find.text('Test expression'));
      await tester.pumpAndSettle();
      expect(find.text('Result: 12.30'), findsOneWidget);
      expect(expression, '(Number(value) / 100).toFixed(2)');
      expect(form.currentState!.validate(), isTrue);
      await tester.enterText(field, 'value +');
      await tester.tap(find.text('Test expression'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Expression failed'), findsOneWidget);
      expect(form.currentState!.validate(), isFalse);
      await tester.enterText(field, '');
      expect(form.currentState!.validate(), isTrue);
    },
  );
}
