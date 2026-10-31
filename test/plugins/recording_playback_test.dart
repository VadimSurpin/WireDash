import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash_plugin_api/wiredash_plugin_api.dart';
import 'package:wiredash_video/wiredash_video.dart';
import 'plugin_test_fakes.dart';

/// Simulate a DVR that rejects reconstructed range URLs but plays the returned
/// file address. Startup errors arrive while the decoder still awaits a frame.
class _FileOnlySession extends FakeSession {
  @override
  Future<void> open(Uri uri, {required bool muted}) {
    opened = uri;
    if (!uri.queryParameters.containsKey('name')) {
      health.failed(Duration.zero);
      notifyListeners();
      return Completer<void>().future;
    }
    return Future.value();
  }
}

void main() {
  test(
    'video previews use the event timestamp instead of the older file URI start',
    () async {
      final host = MemoryHost(),
          player = FakeSession()..frame = Uint8List.fromList([1, 2, 3]);
      const clock = RecorderClock(local: true, zone: 'CST-3:00:00');
      final record = Recording(
        start: DateTime.utc(2026, 10, 31, 7, 3, 42),
        end: DateTime.utc(2026, 10, 31, 7, 3, 48),
        clock: clock,
        playback: Uri.parse(
          'rtsp://recorder/Streaming/tracks/101?name=file&size=100&starttime=20261031T100000Z&endtime=20261031T101000Z',
        ),
      );
      final previews = RecordingPreviews(
        host: host,
        config: const VideoConfig(streamUrl: 'rtsp://recorder/live'),
        sessionFactory: () => player,
      );
      try {
        expect(await previews.request(record).image, [1, 2, 3]);
        expect(player.opened!.queryParameters['starttime'], '20261031T100342Z');
        expect(
          player.opened!.queryParameters['endtime'],
          isNot('20261031T100348Z'),
        );
        expect(player.opened!.queryParameters.containsKey('name'), isFalse);
        expect(player.closed, isTrue);
      } finally {
        previews.dispose();
      }
    },
  );

  test(
    'preview promptly falls back from a rejected range to the real file',
    () async {
      final host = MemoryHost();
      final sessions = <_FileOnlySession>[];
      final record = Recording(
        start: DateTime.utc(2026, 10, 31, 7),
        end: DateTime.utc(2026, 10, 31, 7, 1),
        clock: const RecorderClock(
          standard: true,
          local: false,
          playbackLocal: true,
          forcePlaybackLocal: true,
          offsetMinutes: 180,
        ),
        playback: Uri.parse(
          'rtsp://recorder/Streaming/tracks/101?name=file&starttime=20261031T070000Z&timeType=STD',
        ),
      );
      final previews = RecordingPreviews(
        host: host,
        config: const VideoConfig(streamUrl: 'rtsp://recorder/live'),
        sessionFactory: () {
          final session = _FileOnlySession()
            ..frame = Uint8List.fromList([1, 2, 3]);
          sessions.add(session);
          return session;
        },
      );
      try {
        expect(
          await previews
              .request(record)
              .image
              .timeout(const Duration(seconds: 2)),
          [1, 2, 3],
        );
        expect(sessions, hasLength(2));
        expect(
          sessions.first.opened!.queryParameters.containsKey('name'),
          isFalse,
        );
        expect(sessions.last.opened!.queryParameters['name'], 'file');
        expect(
          sessions.every(
            (s) => s.opened!.queryParameters['starttime'] == '20261031T100000Z',
          ),
          isTrue,
        );
        expect(
          sessions.every(
            (s) => !s.opened!.queryParameters.containsKey('timeType'),
          ),
          isTrue,
        );
        expect(sessions.every((s) => s.closed), isTrue);
        expect(host.network.leases.every((l) => l.closed), isTrue);
      } finally {
        previews.dispose();
      }
    },
  );

  test(
    'short target previews resolve the ordinary recording when range playback fails',
    () async {
      final event = Recording(
        start: DateTime.utc(2026, 10, 31, 7),
        end: DateTime.utc(2026, 10, 31, 7, 0, 6),
        playback: Uri.parse(
          'rtsp://recorder/Streaming/tracks/101?starttime=event',
        ),
      );
      final file = Recording(
        start: event.start,
        end: event.end.add(const Duration(minutes: 30)),
        playback: Uri.parse(
          'rtsp://recorder/Streaming/tracks/101?name=long-file',
        ),
      );
      final sessions = <_FileOnlySession>[];
      var resolutions = 0;
      final previews = RecordingPreviews(
        host: MemoryHost(),
        config: const VideoConfig(streamUrl: 'rtsp://recorder/live'),
        resolveRecording: (record) async {
          resolutions++;
          return file;
        },
        sessionFactory: () {
          final player = _FileOnlySession()
            ..frame = Uint8List.fromList([4, 5, 6]);
          sessions.add(player);
          return player;
        },
      );
      try {
        expect(
          await previews
              .request(event)
              .image
              .timeout(const Duration(seconds: 2)),
          [4, 5, 6],
        );
        expect(resolutions, 1);
        expect(sessions.last.opened!.queryParameters['name'], 'long-file');
        expect(sessions.every((s) => s.closed), isTrue);
      } finally {
        previews.dispose();
      }
    },
  );

  test(
    'short event metadata retains the real file end in the recorder local clock',
    () {
      const config = VideoConfig(streamUrl: 'rtsp://recorder/live');
      const clock = RecorderClock(local: true, offsetMinutes: 180);
      final event = Recording(
        start: DateTime.utc(2026, 10, 31, 7),
        end: DateTime.utc(2026, 10, 31, 7, 0, 6),
        clock: clock,
        playback: Uri.parse(
          'rtsp://recorder/Streaming/tracks/101?name=file&starttime=20261031T100000Z&endtime=20261031T101000Z',
        ),
      );
      expect(HikvisionClient.fileEnd(event), DateTime.utc(2026, 10, 31, 7, 10));
      expect(
        HikvisionClient.filePlayback(
          config,
          event,
          event.start,
        ).queryParameters['endtime'],
        '20261031T101000Z',
      );
      final invalid = Recording(
        start: event.start,
        end: event.end,
        clock: clock,
        playback: Uri.parse('rtsp://recorder/archive?endtime=20991031T101000Z'),
      );
      expect(HikvisionClient.fileEnd(invalid), event.end);
    },
  );

  testWidgets(
    'rejected range playback uses the real DVR file and retains legacy-local time when seeking',
    (tester) async {
      final host = MemoryHost(), sessions = <_FileOnlySession>[];
      const config = VideoConfig(streamUrl: 'rtsp://public-recorder:8554/live');
      const clock = RecorderClock(local: true, zone: 'CST-3:00:00');
      final record = Recording(
        start: DateTime.utc(2026, 10, 31, 7),
        end: DateTime.utc(2026, 10, 31, 7, 10),
        clock: clock,
        playback: Uri.parse(
          'rtsp://internal/Streaming/tracks/101?name=real-file&size=100&starttime=20261031T100000Z&endtime=20261031T101000Z',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoPane(
              context: PluginTileContext(
                id: 'c',
                title: 'Camera',
                host: host,
                settings: config.toJson(),
              ),
              playback: HikvisionClient.continuousPlayback(
                config,
                record.start,
                source: record.playback,
                clock: record.clock,
              ),
              recording: record,
              autoStart: true,
              showRecordings: false,
              videoHeight: 200,
              sessionFactory: () {
                final s = _FileOnlySession();
                sessions.add(s);
                return s;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(sessions, hasLength(2));
      expect(sessions.first.closed, isTrue);
      expect(sessions.last.playing, isTrue);
      expect(sessions.last.opened!.host, 'public-recorder');
      expect(
        sessions.last.opened!.queryParameters,
        containsPair('name', 'real-file'),
      );
      expect(
        sessions.last.opened!.queryParameters['starttime'],
        '20261031T100000Z',
      );
      expect(find.textContaining('could not start'), findsNothing);
      await tester.tap(find.byTooltip('Forward 10 seconds'));
      await tester.pumpAndSettle();
      expect(
        sessions.last.opened!.queryParameters['starttime'],
        '20261031T100010Z',
      );
      expect(
        sessions.last.opened!.queryParameters['endtime'],
        '20261031T101000Z',
      );
      expect(host.network.leases.take(3).every((l) => l.closed), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(sessions.every((s) => s.closed), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'short target matches resolve actual video files and continue into the next file',
    (tester) async {
      final host = MemoryHost(), sessions = <_FileOnlySession>[];
      const config = VideoConfig(streamUrl: 'rtsp://recorder/live');
      final start = DateTime.utc(2026, 10, 31, 7);
      final target = Recording(
        start: start,
        end: start.add(const Duration(seconds: 6)),
        playback: HikvisionClient.boundedPlayback(
          config,
          start,
          start.add(const Duration(seconds: 6)),
        ),
      );
      final resolvedTimes = <DateTime>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoPane(
              context: PluginTileContext(
                id: 'c',
                title: 'Camera',
                host: host,
                settings: config.toJson(),
              ),
              playback: HikvisionClient.continuousPlayback(config, start),
              recording: target,
              resolveRecording: (time) async {
                resolvedTimes.add(time);
                final next = time.isAfter(start);
                return Recording(
                  start: next ? start.add(const Duration(hours: 1)) : start,
                  end: start.add(Duration(hours: next ? 2 : 1)),
                  playback: Uri.parse(
                    'rtsp://recorder/Streaming/tracks/101?name=${next ? 'next' : 'full-file'}&size=1000',
                  ),
                );
              },
              autoStart: true,
              showRecordings: false,
              videoHeight: 200,
              sessionFactory: () {
                final s = _FileOnlySession();
                sessions.add(s);
                return s;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(sessions.last.opened!.queryParameters['name'], 'full-file');
      expect(
        sessions.last.opened!.queryParameters['endtime'],
        '20261031T080000Z',
      );
      await tester.tap(find.byTooltip('Stop video'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Play video'));
      await tester.pumpAndSettle();
      expect(sessions.last.opened!.queryParameters['name'], 'full-file');

      sessions.last.position = const Duration(hours: 1);
      sessions.last.completed = true;
      sessions.last.notifyListeners();
      await tester.pumpAndSettle();
      expect(resolvedTimes, [start, start.add(const Duration(hours: 1))]);
      expect(sessions.last.opened!.queryParameters['name'], 'next');
      expect(
        sessions.last.opened!.queryParameters['starttime'],
        '20261031T080000Z',
      );
      expect(find.textContaining('could not start'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(host.network.leases.every((l) => l.closed), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
