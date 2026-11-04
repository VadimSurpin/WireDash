import 'dart:io';

/// Reuse resolved settings only while both their configuration and backing
/// storage are unchanged. A missing/unreadable version always forces a read.
class SettingsReadCache<T> {
  SettingsReadCache({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  final _entries = <String, ({Object version, T value, DateTime expires})>{};

  Future<T> read(String key, Object? version, Future<T> Function() load) async {
    final old = _entries[key];
    if (version != null &&
        old != null &&
        old.version == version &&
        _now().isBefore(old.expires)) {
      return old.value;
    }
    // Do not serve an old value after a failed refresh or unreadable stamp.
    _entries.remove(key);
    final value = await load();
    if (version != null) {
      _entries[key] = (
        version: version,
        value: value,
        expires: _now().add(const Duration(minutes: 1)),
      );
    }
    return value;
  }

  void forget(String key) => _entries.remove(key);
}

/// File metadata only: never read encrypted preferences outside their plugin.
/// Android writes SharedPreferences atomically; modification/change times and
/// length detect password, tunnel and relay edits, including backup restores.
Future<Object?> settingsFileVersion(File file) async {
  try {
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) return null;
    return (
      stat.modified.microsecondsSinceEpoch,
      stat.changed.microsecondsSinceEpoch,
      stat.size,
    );
  } on FileSystemException {
    return null;
  }
}
