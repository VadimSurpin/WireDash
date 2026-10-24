import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/features/panels/models/panel_config.dart';
import 'package:zigdash/features/panels/widgets/device_panel_display_editor.dart';
import 'package:zigdash/l10n/app_localizations.dart';

void main() {
  test(
    'device icon survives config round trip without changing default fields',
    () {
      final display = DevicePanelDisplay(
        iconCodepoint: Icons.lightbulb.codePoint,
      );
      final decoded = DevicePanelDisplay.fromJson(display.toJson());
      expect(decoded.iconCodepoint, Icons.lightbulb.codePoint);
      expect(decoded.hasPropertyOverrides, isFalse);
      expect(decoded.isDefault, isFalse);
      expect(DevicePanelDisplay.fromJson({}).isDefault, isTrue);
      final custom = DevicePanelDisplay.fromJson(
        DevicePanelDisplay(
          iconCodepoint: Icons.outlet.codePoint,
          properties: ['K1'],
          labels: {'K1': 'Kitchen'},
          expressions: {'temp': 'value / 10'},
        ).toJson(),
      );
      expect(custom.properties, ['K1']);
      expect(custom.labels, {'K1': 'Kitchen'});
      expect(custom.expressions, {'temp': 'value / 10'});
    },
  );

  testWidgets('device icon survives property edits and can reset separately', (
    tester,
  ) async {
    var value = DevicePanelDisplay(iconCodepoint: Icons.lightbulb.codePoint);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DevicePanelDisplayEditor(
                properties: const [(id: 'K1', label: 'Relay')],
                defaults: const ['K1'],
                value: value,
                onChanged: (next) => value = next,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('display-property:K1')));
    await tester.pumpAndSettle();
    expect(value.iconCodepoint, Icons.lightbulb.codePoint);
    expect(value.properties, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('display-label:0:K1')),
      'Kitchen',
    );
    expect(value.labels, {'K1': 'Kitchen'});
    expect(value.iconCodepoint, Icons.lightbulb.codePoint);
    await tester.ensureVisible(find.text('Automatic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Automatic'));
    await tester.pumpAndSettle();
    expect(value.iconCodepoint, isNull);
    expect(value.labels, {'K1': 'Kitchen'});
  });
}
