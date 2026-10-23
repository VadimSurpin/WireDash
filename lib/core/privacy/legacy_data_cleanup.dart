import 'package:shared_preferences/shared_preferences.dart';

/// Drop usage events left by older builds. Never reads their contents.
Future<void> clearLegacyUsageData(SharedPreferences prefs) async {
  for (final key in prefs.getKeys()) {
    if (key == 'analytics_consent' ||
        key == 'poll_next_done' ||
        key.startsWith('aptabase_') ||
        key.startsWith('shortcut.used.') ||
        key.startsWith('shortcut.added.')) {
      await prefs.remove(key);
    }
  }
}
