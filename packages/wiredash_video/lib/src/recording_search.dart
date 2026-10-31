import 'package:uuid/uuid.dart';
import 'hikvision_client.dart';
import 'recording_event.dart';
import 'video_config.dart';

enum RecordingFilter {
  motion,
  human,
  vehicle,
  alarm,
  lineCrossing,
  intrusion,
  other;

  String get label => switch (this) {
    motion => 'Motion detected',
    human => 'People',
    vehicle => 'Vehicles',
    alarm => 'Alarm',
    lineCrossing => 'Line crossing',
    intrusion => 'Intrusion',
    other => 'Other events',
  };
  bool get generic => this != human && this != vehicle;
  bool matches(Recording record) => switch (this) {
    motion => record.events.contains(RecordingEvent.motion),
    human => record.events.contains(RecordingEvent.human),
    vehicle => record.events.contains(RecordingEvent.vehicle),
    alarm => record.events.contains(RecordingEvent.alarm),
    lineCrossing => record.events.contains(RecordingEvent.lineCrossing),
    intrusion => record.events.contains(RecordingEvent.intrusion),
    other => record.events.any(
      (e) => e == RecordingEvent.other || e == RecordingEvent.manual,
    ),
  };
  bool supported(RecorderCapabilities? capabilities) =>
      generic ||
      (capabilities?.targets.contains(
            this == human ? RecordingTarget.human : RecordingTarget.vehicle,
          ) ??
          false);
}

class _Cursor {
  _Cursor({this.position = 0, this.more = true, String? id})
    : id = id ?? const Uuid().v4();
  int position;
  bool more;
  final String id;
}

/// OR-search across independent firmware endpoints, with a cursor per source.
class RecordingSearch {
  RecordingSearch(this.start, this.end, Set<RecordingFilter> filters)
    : filters = Set.of(filters) {
    for (final source in sources) {
      cursors[source] = _Cursor();
    }
  }
  final DateTime start, end;
  final Set<RecordingFilter> filters;
  final cursors = <RecordingTarget, _Cursor>{};
  Set<RecordingTarget> get sources => {
    if (filters.isEmpty || filters.any((f) => f.generic)) RecordingTarget.all,
    if (filters.contains(RecordingFilter.human)) RecordingTarget.human,
    if (filters.contains(RecordingFilter.vehicle)) RecordingTarget.vehicle,
  };
  bool get hasMore => cursors.values.any((c) => c.more);
  String get key {
    final names = filters.map((f) => f.name).toList()..sort();
    return 'filtered-timeline/v2/${start.toUtc().toIso8601String()}/${end.toUtc().toIso8601String()}/${names.join(',')}';
  }

  Map<String, dynamic> save() => {
    for (final entry in cursors.entries)
      entry.key.name: {
        'position': entry.value.position,
        'more': entry.value.more,
        'id': entry.value.id,
      },
  };
  void restore(Map<String, dynamic> saved) {
    final next = <RecordingTarget, _Cursor>{};
    for (final source in sources) {
      final value = saved[source.name] as Map;
      final position = value['position'] as int;
      if (position < 0) throw const FormatException('Invalid search position.');
      next[source] = _Cursor(
        position: position,
        more: value['more'] as bool,
        id: value['id'] as String,
      );
    }
    cursors
      ..clear()
      ..addAll(next);
  }

  Future<({List<Recording> records, String? error})> next(
    HikvisionClient client, {
    bool Function()? active,
  }) async {
    final results = <Recording>[];
    String? error;
    for (final entry in cursors.entries) {
      if (active != null && !active()) break;
      final source = entry.key, cursor = entry.value;
      if (!cursor.more) continue;
      try {
        // Ordinary search may page through continuous footage before finding
        // motion/alarm matches. Keep its raw cursor even when a page is filtered.
        for (var scan = 0; scan < 5 && cursor.more; scan++) {
          final page = await client.search(
            start: start,
            end: end,
            target: source,
            position: cursor.position,
            searchId: cursor.id,
          );
          if (active != null && !active()) {
            return (records: <Recording>[], error: null);
          }
          cursor.more = page.hasMore && page.nextPosition > cursor.position;
          cursor.position = page.nextPosition;
          final selected = source == RecordingTarget.all && filters.isNotEmpty
              ? page.records
                    .where((r) => filters.any((f) => f.matches(r)))
                    .toList()
              : page.records;
          results.addAll(selected);
          if (selected.isNotEmpty || source != RecordingTarget.all) break;
        }
      } catch (e) {
        error = e is RecorderException
            ? e.message
            : 'Could not read some recording results.';
      }
    }
    return (records: merge(results), error: error);
  }

  static List<Recording> merge(Iterable<Recording> records) {
    final combined = <String, Recording>{};
    for (final record in records) {
      final key =
          '${record.start.toUtc().microsecondsSinceEpoch}/${record.end.toUtc().microsecondsSinceEpoch}';
      final previous = combined[key];
      if (previous == null) {
        combined[key] = record;
        continue;
      }
      final playback =
          record.playback.queryParameters.containsKey('name') &&
              !previous.playback.queryParameters.containsKey('name')
          ? record.playback
          : previous.playback;
      combined[key] = Recording(
        start: record.start,
        end: record.end,
        playback: playback,
        clock: record.clock,
        target: previous.target == record.target
            ? record.target
            : RecordingTarget.all,
        eventTypes: {...previous.events, ...record.events}.toList(),
      );
    }
    return combined.values.toList()..sort((a, b) => a.start.compareTo(b.start));
  }
}
