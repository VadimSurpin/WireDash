import 'package:flutter/foundation.dart';
import 'hikvision_client.dart';
import 'recording_cache.dart';
import 'recording_search.dart';

/// The player's complete event range, independent of the browser's filters and
/// loaded page. Fetches progressively without blocking video startup.
class PlaybackArchive extends ChangeNotifier {
  PlaybackArchive({
    required this.start,
    required this.end,
    required this.client,
    required this.filters,
    required this.cache,
    Iterable<Recording> seed = const [],
  }) : records = RecordingSearch.merge(seed);

  final DateTime start, end;
  final HikvisionClient client;
  final Set<RecordingFilter> filters;
  final RecordingCache cache;
  List<Recording> records;
  bool loading = false, _disposed = false;
  String? error;
  Future<void>? _pending;

  Future<void> load() =>
      _pending ??= _load().whenComplete(() => _pending = null);
  Future<void> _load() async {
    if (_disposed) return;
    loading = true;
    error = null;
    notifyListeners();
    final query = RecordingSearch(start, end, filters);
    final key = 'player-events-v1/${query.key}';
    try {
      final saved = await cache.readJson(key);
      if (_disposed) return;
      if (saved != null) {
        try {
          records = RecordingSearch.merge([
            ...records,
            for (final value in saved['records'] as List)
              RecordingCache.decodeRecord(
                Map<String, dynamic>.from(value as Map),
                client.config,
              ),
          ]);
          notifyListeners();
          final written = DateTime.parse(saved['savedAt'] as String);
          final age = DateTime.now().difference(written);
          final historical = end.isBefore(
            DateTime.now().subtract(const Duration(hours: 1)),
          );
          if (!age.isNegative &&
              age <
                  (historical
                      ? const Duration(days: 1)
                      : const Duration(minutes: 1))) {
            return;
          }
        } catch (_) {
          // Incompatible cache data must not prevent an online search.
        }
      }
      final found = <Recording>[];
      while (!_disposed && query.hasMore) {
        final page = await query.next(client, active: () => !_disposed);
        if (_disposed) return;
        found.addAll(page.records);
        records = RecordingSearch.merge([...records, ...page.records]);
        error = page.error;
        notifyListeners();
        if (error != null) return;
      }
      if (!_disposed && found.length <= 2000) {
        await cache.writeJson(key, {
          'records': found.map(RecordingCache.encodeRecord).toList(),
          'savedAt': DateTime.now().toUtc().toIso8601String(),
        });
      }
    } catch (e) {
      if (!_disposed) {
        error = e is RecorderException
            ? e.message
            : 'Could not read some recording results.';
      }
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
