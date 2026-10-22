import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// JSF's Dart package license is bundled by Flutter; also retain the separate
/// upstream engine notice in About's license page.
void registerJavaScriptLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['QuickJS'],
      await rootBundle.loadString('assets/licenses/QuickJS-MIT.txt'),
    );
  });
}
