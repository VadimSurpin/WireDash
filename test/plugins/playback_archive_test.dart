import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash_video/wiredash_video.dart';

class _Recorder extends HikvisionClient {
  _Recorder()
    : super(
        config: const VideoConfig(),
        credentials: const VideoCredentials('', ''),
      );
  final calls = <(RecordingTarget, int)>[];
  @override
  Future<RecordingPage> search({
    required DateTime start,
    required DateTime end,
    RecordingTarget target = RecordingTarget.all,
    int position = 0,
    String? searchId,
  }) async {
    calls.add((target, position));
    final time = start.add(Duration(minutes: position + target.index * 10));
    return RecordingPage(
      [
        Recording(
          start: time,
          end: time.add(const Duration(seconds: 10)),
          playback: Uri.parse('rtsp://recorder/archive'),
          target: target,
          eventTypes: target == RecordingTarget.all
              ? [RecordingEvent.motion]
              : [],
        ),
      ],
      nextPosition: position + 1,
      hasMore: position == 0,
    );
  }
}

void main() {
  test(
    'player loads every page and target independently of the entry filter, then reuses cache',
    () async {
      final client = _Recorder(),
          cache = RecordingCache(namespace: 'archive', memoryOnly: true);
      final start = DateTime.utc(2026, 10, 29);
      PlaybackArchive archive() => PlaybackArchive(
        start: start,
        end: start.add(const Duration(hours: 1)),
        client: client,
        filters: RecordingFilter.values.toSet(),
        cache: cache,
      );
      final first = archive();
      await first.load();
      expect(first.error, isNull);
      expect(first.loading, isFalse);
      expect(first.records, hasLength(6));
      expect(client.calls.toSet(), {
        (RecordingTarget.all, 0),
        (RecordingTarget.all, 1),
        (RecordingTarget.human, 0),
        (RecordingTarget.human, 1),
        (RecordingTarget.vehicle, 0),
        (RecordingTarget.vehicle, 1),
      });
      first.dispose();
      final second = archive();
      await second.load();
      expect(second.records, hasLength(6));
      expect(client.calls, hasLength(6));
      second.dispose();
      client.close();
    },
  );
}
