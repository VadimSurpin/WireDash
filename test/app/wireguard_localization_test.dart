import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/l10n/app_localizations.dart';

void main() {
  test('wireguard UI has explicit translations in every supported locale', () {
    const keys = [
      'wgTitle',
      'wgDescription',
      'wgConfiguration',
      'wgSecretHint',
      'wgHide',
      'wgShow',
      'wgImport',
      'wgInvalidConfiguration',
      'wgConnect',
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
      expect(localized.wgInvalidConfiguration, isNotEmpty);
      expect(localized.wgConnect, isNotEmpty);
    }
  });
}
