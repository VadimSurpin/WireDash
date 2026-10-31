import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash_video/wiredash_video.dart';

Recording item(
  int minute, {
  RecordingTarget target = RecordingTarget.all,
  List<RecordingEvent> events = const [],
  bool file = false,
}) => Recording(
  start: DateTime.utc(2026, 10, 31, 10, minute),
  end: DateTime.utc(2026, 10, 31, 10, minute, 6),
  playback: Uri.parse(
    'rtsp://recorder/Streaming/tracks/101${file ? '?name=file$minute&size=100' : ''}',
  ),
  target: target,
  eventTypes: events,
);

class _Recorder extends HikvisionClient {
  _Recorder(this.reply)
    : super(
        config: const VideoConfig(),
        credentials: const VideoCredentials('', ''),
      );
  final RecordingPage Function(RecordingTarget, int) reply;
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
    return reply(target, position);
  }
}

void main() {
  final start = DateTime.utc(2026, 10, 31), end = DateTime.utc(2026, 11, 1);
  test(
    'motion, people and vehicles form a union with independent paging and deduplicated labels',
    () async {
      final client = _Recorder(
        (source, position) => switch ((source, position)) {
          (RecordingTarget.all, 0) => RecordingPage(
            [
              item(0, events: [RecordingEvent.scheduled]),
            ],
            nextPosition: 40,
            hasMore: true,
          ),
          (RecordingTarget.all, 40) => RecordingPage(
            [
              item(1, events: [RecordingEvent.motion], file: true),
            ],
            nextPosition: 41,
            hasMore: false,
          ),
          (RecordingTarget.human, 0) => RecordingPage(
            [item(1, target: RecordingTarget.human)],
            nextPosition: 1,
            hasMore: false,
          ),
          (RecordingTarget.vehicle, 0) => RecordingPage(
            [item(2, target: RecordingTarget.vehicle)],
            nextPosition: 40,
            hasMore: true,
          ),
          (RecordingTarget.vehicle, 40) => RecordingPage(
            [item(3, target: RecordingTarget.vehicle)],
            nextPosition: 41,
            hasMore: false,
          ),
          _ => throw StateError('Unexpected cursor $source/$position'),
        },
      );
      try {
        final query = RecordingSearch(start, end, {
          RecordingFilter.motion,
          RecordingFilter.human,
          RecordingFilter.vehicle,
        });
        final first = await query.next(client);
        expect(first.error, isNull);
        expect(first.records, hasLength(2));
        expect(first.records.first.events.toSet(), {
          RecordingEvent.motion,
          RecordingEvent.human,
        });
        expect(first.records.first.playback.queryParameters['name'], 'file1');
        expect(query.hasMore, isTrue);
        final restored = RecordingSearch(start, end, {
          RecordingFilter.vehicle,
          RecordingFilter.human,
          RecordingFilter.motion,
        })..restore(query.save());
        expect(restored.key, query.key);
        final second = await restored.next(client);
        expect(client.calls.last, (RecordingTarget.vehicle, 40));
        expect(restored.hasMore, isFalse);
        expect(
          RecordingSearch.merge([...first.records, ...second.records]),
          hasLength(3),
        );
      } finally {
        client.close();
      }
    },
  );

  test(
    'empty generic pages keep their raw cursor instead of skipping or ending the search',
    () async {
      final client = _Recorder(
        (source, position) => position < 200
            ? RecordingPage(
                [
                  item(0, events: [RecordingEvent.scheduled]),
                ],
                nextPosition: position + 40,
                hasMore: true,
              )
            : RecordingPage(
                [
                  item(1, events: [RecordingEvent.motion]),
                ],
                nextPosition: 201,
                hasMore: false,
              ),
      );
      try {
        final query = RecordingSearch(start, end, {RecordingFilter.motion});
        expect((await query.next(client)).records, isEmpty);
        expect(query.hasMore, isTrue);
        expect((await query.next(client)).records.single.events, [
          RecordingEvent.motion,
        ]);
        expect(client.calls.map((c) => c.$2), [0, 40, 80, 120, 160, 200]);
        expect(query.hasMore, isFalse);
      } finally {
        client.close();
      }
    },
  );

  test(
    'one unavailable source preserves other results and remains retryable',
    () async {
      var denied = true;
      final client = _Recorder((source, position) {
        if (source == RecordingTarget.human && denied) {
          throw const RecorderException('Access denied.', status: 403);
        }
        return RecordingPage(
          [item(source == RecordingTarget.human ? 1 : 2, target: source)],
          nextPosition: 1,
          hasMore: false,
        );
      });
      try {
        final query = RecordingSearch(start, end, {
          RecordingFilter.human,
          RecordingFilter.vehicle,
        });
        final first = await query.next(client);
        expect(first.records.single.target, RecordingTarget.vehicle);
        expect(first.error, 'Access denied.');
        expect(query.hasMore, isTrue);
        denied = false;
        expect(
          (await query.next(client)).records.single.target,
          RecordingTarget.human,
        );
        expect(query.hasMore, isFalse);
      } finally {
        client.close();
      }
    },
  );
}
