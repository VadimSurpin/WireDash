import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash_video/wiredash_video.dart';
import 'plugin_test_fakes.dart';

Recording record(int minute) => Recording(
  start: DateTime.utc(2026, 10, 31, 10, minute),
  end: DateTime.utc(2026, 10, 31, 10, minute, 6),
  playback: Uri.parse(
    'rtsp://recorder/Streaming/tracks/101?name=clip$minute&endtime=clip-end',
  ),
);

void main() {
  test(
    'recording playback starts at the event timestamp without its six-second/file limits',
    () {
      final uri = HikvisionClient.continuousPlayback(
        const VideoConfig(
          streamUrl: 'rtsp://recorder:8554/Streaming/Channels/1702?name=live',
          channel: 17,
        ),
        DateTime.parse('2026-10-31T13:45:21+03:00'),
      );
      expect(uri.host, 'recorder');
      expect(uri.port, 8554);
      expect(uri.path, '/Streaming/tracks/1701');
      expect(uri.queryParameters, {'starttime': '20261031T104521Z'});
      expect(uri.userInfo, isEmpty);
    },
  );

  test(
    'disk cache survives recreation, isolates cameras and expires images/results separately',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'wiredash-cache-test-',
      );
      var clock = DateTime.now().toUtc();
      RecordingCache store(String scope) => RecordingCache(
        namespace: scope,
        directory: root,
        maxMemoryBytes: 0,
        now: () => clock,
      );
      try {
        final first = store('camera-a');
        await first.writeImage(record(0), Uint8List.fromList([1, 2, 3]));
        await first.writeJson('capabilities', {
          'targets': ['human'],
        });
        final restored = store('camera-a');
        expect(await restored.readImage(record(0)), [1, 2, 3]);
        expect(await restored.readJson('capabilities'), {
          'targets': ['human'],
        });
        expect(await store('camera-b').readImage(record(0)), isNull);
        clock = clock.add(const Duration(days: 2));
        expect(await restored.readJson('capabilities'), isNull);
        expect(await restored.readImage(record(0)), [1, 2, 3]);
        clock = clock.add(const Duration(days: 6));
        expect(await restored.readImage(record(0)), isNull);
        final names = await root
            .list()
            .map((f) => f.uri.pathSegments.last)
            .toList();
        expect(
          names.every((n) => RegExp(r'^[a-f0-9]{64}\.cache$').hasMatch(n)),
          isTrue,
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'disk limits evict old entries and corrupt entries are safe cache misses',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'wiredash-cache-limit-',
      );
      try {
        final cache = RecordingCache(
          namespace: 'camera',
          directory: root,
          maxMemoryBytes: 0,
          maxDiskBytes: 80,
          maxFiles: 2,
        );
        await cache.writeImage(record(0), Uint8List(40));
        await cache.writeImage(record(1), Uint8List(40));
        expect(await cache.readImage(record(0)), isNull);
        expect(await cache.readImage(record(1)), hasLength(40));
        final files = await root
            .list()
            .where((f) => f.path.endsWith('.cache'))
            .cast<File>()
            .toList();
        expect(files, hasLength(1));
        await files.single.writeAsBytes(Uint8List(16));
        expect(await cache.readImage(record(1)), isNull);
        await cache.writeJson('recovered', {'ok': true});
        expect(await cache.readJson('recovered'), {'ok': true});
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'a reopened preview cache returns its frame without another recorder connection',
    (tester) async {
      final cache = RecordingCache(namespace: 'previews', memoryOnly: true);
      final firstHost = MemoryHost();
      final first = RecordingPreviews(
        host: firstHost,
        cache: cache,
        config: const VideoConfig(streamUrl: 'rtsp://recorder/live'),
        sessionFactory: () =>
            FakeSession()..frame = Uint8List.fromList([1, 2, 3]),
      );
      final ticket = first.request(record(0));
      await tester.pump();
      expect(await ticket.image, [1, 2, 3]);
      first.dispose();
      final nextHost = MemoryHost();
      final next = RecordingPreviews(
        host: nextHost,
        cache: cache,
        config: const VideoConfig(streamUrl: 'rtsp://recorder/live'),
        sessionFactory: () =>
            throw StateError('Cached frame must not create a decoder'),
      );
      final cached = next.request(record(0));
      await tester.pump();
      expect(await cached.image, [1, 2, 3]);
      expect(nextHost.network.leases, isEmpty);
      expect(firstHost.network.leases.single.closed, isTrue);
      next.dispose();
    },
  );

  test(
    'cached records keep event metadata and never restore embedded login data',
    () {
      final original = Recording(
        start: record(0).start,
        end: record(0).end,
        playback: Uri.parse(
          'rtsp://admin:private-password@internal/Streaming/tracks/101?name=clip',
        ),
        target: RecordingTarget.human,
        eventTypes: const [RecordingEvent.motion],
      );
      final encoded = RecordingCache.encodeRecord(original);
      expect(encoded.toString(), isNot(contains('private-password')));
      final restored = RecordingCache.decodeRecord(
        encoded,
        const VideoConfig(streamUrl: 'rtsp://external:8554/live'),
      );
      expect(restored.events, [RecordingEvent.motion, RecordingEvent.human]);
      expect(restored.playback.host, 'external');
      expect(restored.playback.port, 8554);
      expect(restored.playback.userInfo, isEmpty);
    },
  );
}
