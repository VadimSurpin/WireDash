import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wiredash_plugin_api/wiredash_plugin_api.dart';
import 'hikvision_client.dart';
import 'recording_event.dart';
import 'recording_picture.dart';
import 'video_config.dart';

class _CacheEntry {
  const _CacheEntry(this.data, this.written);
  final Uint8List data;
  final DateTime written;
}

/// App-private, bounded cache. A panel/configuration/credential reference scopes
/// all entries; neither filenames nor entry keys contain a login or password.
class RecordingCache {
  RecordingCache({
    required this.namespace,
    this.directory,
    this.shared = false,
    this.memoryOnly = false,
    this.maxMemoryBytes = 16 * 1024 * 1024,
    this.maxDiskBytes = 64 * 1024 * 1024,
    this.maxFiles = 512,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  factory RecordingCache.forPanel(PluginTileContext context) {
    final scope = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              context.id,
              VideoConfig.fromJson(context.settings).toJson(),
            ]),
          ),
        )
        .toString();
    final existing = _panels.remove(scope);
    final cache = existing ?? RecordingCache(namespace: scope, shared: true);
    _panels[scope] = cache;
    if (_panels.length > 32) _panels.remove(_panels.keys.first);
    return cache;
  }
  static final _panels = <String, RecordingCache>{};
  static final _sharedMemory = <String, _CacheEntry>{};
  static int _sharedMemoryBytes = 0;
  static Future<void> _sharedWrites = Future.value();
  final String namespace;
  final Directory? directory;
  final bool memoryOnly, shared;
  final int maxMemoryBytes, maxDiskBytes, maxFiles;
  final DateTime Function() now;
  final _localMemory = <String, _CacheEntry>{};
  Map<String, _CacheEntry> get _memory => shared ? _sharedMemory : _localMemory;
  int _localMemoryBytes = 0;
  int get _memoryBytes => shared ? _sharedMemoryBytes : _localMemoryBytes;
  set _memoryBytes(int value) {
    if (shared) {
      _sharedMemoryBytes = value;
    } else {
      _localMemoryBytes = value;
    }
  }

  Future<Directory?>? _root;
  Future<void> _localWrites = Future.value();
  Future<void> get _writes => shared ? _sharedWrites : _localWrites;
  set _writes(Future<void> value) {
    if (shared) {
      _sharedWrites = value;
    } else {
      _localWrites = value;
    }
  }

  String _key(String key) =>
      sha256.convert(utf8.encode('$namespace/$key')).toString();
  Future<Directory?> _directory() => _root ??= () async {
    if (memoryOnly) return null;
    try {
      final root =
          directory ??
          Directory(
            '${(await getTemporaryDirectory()).path}/wiredash-recordings-v1',
          );
      await root.create(recursive: true);
      return root;
    } catch (_) {
      return null;
    } // Caching must not prevent recorder access.
  }();

  void _remember(String key, _CacheEntry entry) {
    final old = _memory.remove(key);
    if (old != null) _memoryBytes -= old.data.length;
    if (entry.data.length > maxMemoryBytes) return;
    _memory[key] = entry;
    _memoryBytes += entry.data.length;
    while (_memoryBytes > maxMemoryBytes || _memory.length > maxFiles) {
      _memoryBytes -= _memory.remove(_memory.keys.first)!.data.length;
    }
  }

  Future<Uint8List?> _read(String key, Duration maxAge) async {
    final digest = _key(key);
    var entry = _memory.remove(digest);
    if (entry == null) {
      final root = await _directory();
      if (root == null) return null;
      final file = File('${root.path}/$digest.cache');
      try {
        final size = await file.length();
        if (size < 12 || size > 4 * 1024 * 1024 + 12) return null;
        final bytes = await file.readAsBytes();
        if (bytes.length < 12 ||
            ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'WDC1') {
          return null;
        }
        final written = DateTime.fromMillisecondsSinceEpoch(
          ByteData.sublistView(bytes).getInt64(4),
          isUtc: true,
        );
        entry = _CacheEntry(Uint8List.sublistView(bytes, 12), written);
        unawaited(_touch(file));
      } on FileSystemException {
        return null;
      } on ArgumentError {
        return null;
      }
    } else {
      _memoryBytes -= entry.data.length;
    }
    if (now().difference(entry.written).isNegative ||
        now().difference(entry.written) > maxAge) {
      return null;
    }
    _remember(digest, entry);
    return entry.data;
  }

  Future<void> _touch(File file) async {
    try {
      await file.setLastModified(now());
    } on FileSystemException {
      /* Evicted. */
    }
  }

  Future<void> _write(String key, Uint8List data) {
    if (data.isEmpty || data.length > 4 * 1024 * 1024) return Future.value();
    final digest = _key(key), written = now();
    _remember(digest, _CacheEntry(data, written));
    final next = _writes.then((_) async {
      final root = await _directory();
      if (root == null) return;
      final file = File('${root.path}/$digest.cache');
      final temporary = File('${file.path}.tmp');
      try {
        final bytes = Uint8List(12 + data.length);
        bytes.setRange(0, 4, ascii.encode('WDC1'));
        ByteData.sublistView(bytes).setInt64(4, written.millisecondsSinceEpoch);
        bytes.setRange(12, bytes.length, data);
        await temporary.writeAsBytes(bytes, flush: true);
        await temporary.rename(file.path);
        await _prune(root);
      } on FileSystemException {
        /* Optional cache write. */
      } finally {
        try {
          if (await temporary.exists()) await temporary.delete();
        } on FileSystemException {
          /* Optional cache. */
        }
      }
    });
    _writes = next.catchError((Object _) {});
    return _writes;
  }

  Future<void> _prune(Directory root) async {
    final files = <(File, FileStat)>[];
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! File || !entry.path.endsWith('.cache')) continue;
      try {
        files.add((entry, await entry.stat()));
      } on FileSystemException {
        /* Evicted. */
      }
    }
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    var total = files.fold<int>(0, (sum, f) => sum + f.$2.size),
        count = files.length;
    for (final item in files) {
      if (total <= maxDiskBytes && count <= maxFiles) break;
      try {
        await item.$1.delete();
        total -= item.$2.size;
        count--;
      } on FileSystemException {
        /* Evicted. */
      }
    }
  }

  Future<Map<String, dynamic>?> readJson(String key) async {
    final bytes = await _read(key, const Duration(days: 1));
    if (bytes == null) return null;
    try {
      final value = jsonDecode(utf8.decode(bytes));
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> writeJson(String key, Map<String, dynamic> value) =>
      _write(key, utf8.encode(jsonEncode(value)));
  Future<Uint8List?> readImage(Recording record) => _read(
    'preview/${record.start.toUtc().microsecondsSinceEpoch}',
    const Duration(days: 7),
  );
  Future<void> writeImage(Recording record, Uint8List bytes) =>
      _write('preview/${record.start.toUtc().microsecondsSinceEpoch}', bytes);
  Future<Uint8List?> readPicture(RecordingPicture picture) => _read(
    'picture/${picture.time.toUtc().microsecondsSinceEpoch}/${picture.uri}',
    const Duration(days: 7),
  );
  Future<void> writePicture(RecordingPicture picture, Uint8List bytes) =>
      _write(
        'picture/${picture.time.toUtc().microsecondsSinceEpoch}/${picture.uri}',
        bytes,
      );
  String timelineKey(DateTime start, DateTime end, RecordingTarget target) =>
      'timeline/${start.toUtc().toIso8601String()}/${end.toUtc().toIso8601String()}/${target.name}';

  static Map<String, dynamic> encodeRecord(Recording record) => {
    'start': record.start.toUtc().toIso8601String(),
    'end': record.end.toUtc().toIso8601String(),
    'playback': record.playback.replace(userInfo: '').toString(),
    'target': record.target.name,
    'events': record.eventTypes.map((e) => e.name).toList(),
  };
  static Recording decodeRecord(
    Map<String, dynamic> value,
    VideoConfig config,
  ) {
    final start = DateTime.parse(value['start'] as String);
    final end = DateTime.parse(value['end'] as String);
    if (!end.isAfter(start)) {
      throw const FormatException('Invalid cached recording.');
    }
    return Recording(
      start: start,
      end: end,
      playback: config.playbackUri(value['playback'] as String),
      target: RecordingTarget.values.firstWhere(
        (t) => t.name == value['target'],
        orElse: () => RecordingTarget.all,
      ),
      eventTypes: [
        for (final name in value['events'] as List? ?? [])
          ...RecordingEvent.values.where((e) => e.name == name),
      ],
    );
  }
}
