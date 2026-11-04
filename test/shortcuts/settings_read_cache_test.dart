import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/shortcuts/settings_read_cache.dart';

void main() {
  test(
    'unchanged settings avoid plugin reads; edits and explicit forget reload',
    () async {
      final cache = SettingsReadCache<int>();
      var reads = 0;
      Future<int> load() async => ++reads;
      expect(await cache.read('home', ('broker', 'file-v1'), load), 1);
      expect(await cache.read('home', ('broker', 'file-v1'), load), 1);
      expect(await cache.read('home', ('broker', 'file-v2'), load), 2);
      expect(await cache.read('home', ('new-broker', 'file-v2'), load), 3);
      cache.forget(
        'home',
      ); // Settings save before its async disk write finishes.
      expect(await cache.read('home', ('new-broker', 'file-v2'), load), 4);
    },
  );

  test(
    'unreadable versions, expiry and failed refresh never serve stale settings',
    () async {
      var now = DateTime.utc(2026, 11, 4);
      final cache = SettingsReadCache<int>(now: () => now);
      var reads = 0;
      Future<int> load() async => ++reads;
      expect(await cache.read('home', 'v1', load), 1);
      now = now.add(const Duration(minutes: 1));
      expect(await cache.read('home', 'v1', load), 2);
      expect(await cache.read('home', null, load), 3);
      expect(await cache.read('home', null, load), 4);
      expect(await cache.read('home', 'v2', load), 5);
      await expectLater(
        cache.read('home', 'v3', () async => throw StateError('locked')),
        throwsStateError,
      );
      expect(await cache.read('home', 'v3', load), 6);
    },
  );

  test(
    'preference file versions detect same-length replacements and missing storage',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'wiredash-settings-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/settings.xml');
      expect(await settingsFileVersion(file), isNull);
      await file.writeAsString('first');
      final before = await settingsFileVersion(file);
      expect(before, isNotNull);
      expect(await settingsFileVersion(file), before);
      await file.writeAsString('other');
      await file.setLastModified(DateTime.utc(2026, 10, 1));
      expect(await settingsFileVersion(file), isNot(before));
      await file.delete();
      expect(await settingsFileVersion(file), isNull);
      expect(await settingsFileVersion(File(directory.path)), isNull);
    },
  );
}
