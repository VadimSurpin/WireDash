import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/l10n/app_localizations.dart';

void main() {
  test('wirenboard UI has explicit translations in every supported locale', () {
    const keys = [
      'discoverWirenBoardHint',
      'discoverWirenBoardNone',
      'wbControllerBuiltins',
      'wbAddedModules',
      'wbAddWholeDevice',
      'wbControlCount',
      'wbSearch',
      'wbClearSearch',
      'wbAutoAdded',
      'wbAutoAddFailed',
      'wbBuiltinsAvailable',
      'wbZ2mDevices',
      'wbOpenControls',
      'wbAddSelected',
      'wbChooseProperties',
      'panelPropertyWidget',
      'panelDisplayTitle',
      'panelDisplayHint',
      'panelDisplayLabel',
      'panelDisplayReset',
    ];
    final english =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map;
    for (final locale in AppLocalizations.supportedLocales) {
      final language = locale.languageCode;
      final messages =
          jsonDecode(File('lib/l10n/app_$language.arb').readAsStringSync())
              as Map;
      for (final key in keys) {
        expect(messages[key], isA<String>(), reason: '$language: $key');
        expect(
          (messages[key] as String).trim(),
          isNotEmpty,
          reason: '$language: $key',
        );
        if (language != 'en') {
          expect(
            messages[key],
            isNot(english[key]),
            reason: '$language must translate $key',
          );
        }
      }
      final localized = lookupAppLocalizations(locale);
      expect(localized.wbControlCount(3), contains('3'));
      expect(localized.wbAutoAdded(3), contains('3'));
    }
  });
}
