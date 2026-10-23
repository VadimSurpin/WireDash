import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zigdash/core/privacy/legacy_data_cleanup.dart';

void main() {
  test(
    'upgrade clears old usage records and preserves app and shortcut settings',
    () async {
      const kept = <String, Object>{
        'locale': 'ru',
        'theme_mode': 'dark',
        'shortcut.strings': '{"on":"On"}',
        'shortcut.slot.1': 'living-room',
        'last_dashboard': 'd1',
      };
      SharedPreferences.setMockInitialValues({
        ...kept,
        'analytics_consent': true,
        'aptabase_queued_event': '{"name":"app_started"}',
        'poll_next_done': '1',
        'shortcut.used.tile': '1',
        'shortcut.added.control.reported': '1',
      });
      final prefs = await SharedPreferences.getInstance();
      await clearLegacyUsageData(prefs);
      await clearLegacyUsageData(prefs);
      expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, kept);
    },
  );
}
