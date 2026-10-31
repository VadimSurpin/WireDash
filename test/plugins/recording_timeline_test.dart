import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash_video/wiredash_video.dart';
import 'plugin_test_fakes.dart';

Recording clip(int minute, {List<RecordingEvent> events = const []}) =>
    Recording(
      start: DateTime.utc(2026, 10, 31, 10, minute),
      end: DateTime.utc(2026, 10, 31, 10, minute + 1),
      playback: Uri.parse('rtsp://recorder/Streaming/tracks/101?clip=$minute'),
      eventTypes: events,
    );

void main() {
  test(
    'a recovered stream clears its error after progress, including a reset clock',
    () {
      final health = VideoPlaybackHealth();
      health.failed(const Duration(seconds: 10));
      health.progress(
        const Duration(seconds: 10),
        playing: true,
        buffering: false,
      );
      expect(health.error, isNotNull);
      health.progress(
        const Duration(seconds: 11),
        playing: true,
        buffering: true,
      );
      expect(health.error, isNotNull);
      health.progress(
        const Duration(seconds: 11),
        playing: false,
        buffering: false,
      );
      expect(health.error, isNotNull);
      health.progress(Duration.zero, playing: true, buffering: false);
      expect(health.error, isNotNull);
      health.progress(
        const Duration(seconds: 1),
        playing: true,
        buffering: false,
      );
      expect(health.error, isNull);
    },
  );

  testWidgets(
    'historical previews are serialized, shared, cached and close their routes',
    (tester) async {
      final host = MemoryHost();
      final sessions = <FakeSession>[];
      final previews = RecordingPreviews(
        host: host,
        config: const VideoConfig(streamUrl: 'rtsp://recorder/live'),
        sessionFactory: () {
          final s = FakeSession()
            ..opening = Completer<void>()
            ..frame = Uint8List.fromList([1, 2, 3]);
          sessions.add(s);
          return s;
        },
      );
      final first = previews.request(clip(0));
      final shared = previews.request(clip(0));
      final second = previews.request(clip(5));
      await tester.pump();
      expect(sessions, hasLength(1));
      expect(sessions.first.opened!.path, '/Streaming/tracks/101');
      first.release();
      expect(sessions.first.closed, isFalse);
      sessions.first.opening!.complete();
      await tester.pump();
      expect(await shared.image, [1, 2, 3]);
      expect(sessions.first.closed, isTrue);
      expect(host.network.leases.first.closed, isTrue);
      expect(sessions, hasLength(2));
      sessions.last.opening!.complete();
      await tester.pump();
      expect(await second.image, [1, 2, 3]);
      expect(await previews.request(clip(0)).image, [1, 2, 3]);
      expect(sessions, hasLength(2));
      expect(host.network.leases.every((l) => l.closed), isTrue);
      shared.release();
      second.release();
      previews.dispose();
    },
  );

  testWidgets(
    'cancelling an opening preview releases the next job without waiting for it',
    (tester) async {
      final host = MemoryHost();
      final stalled = FakeSession()..opening = Completer<void>();
      final next = FakeSession()..frame = Uint8List.fromList([4, 5]);
      var count = 0;
      final previews = RecordingPreviews(
        host: host,
        config: const VideoConfig(streamUrl: 'rtsp://recorder/live'),
        sessionFactory: () => count++ == 0 ? stalled : next,
      );
      final first = previews.request(clip(0));
      final second = previews.request(clip(5));
      await tester.pump();
      first.release();
      await tester.pump();
      expect(await first.image, isNull);
      expect(stalled.closed, isTrue);
      expect(await second.image, [4, 5]);
      expect(host.network.leases.every((l) => l.closed), isTrue);
      stalled.opening!.complete();
      await tester.pump();
      await previews.setPaused(true);
      expect(await previews.request(clip(9)).image, isNull);
      expect(count, 2);
      previews.dispose();
    },
  );

  testWidgets(
    'preview cache evicts old frames and late credential replies cannot open a stream',
    (tester) async {
      final host = MemoryHost();
      var count = 0;
      final previews = RecordingPreviews(
        host: host,
        maxEntries: 1,
        config: const VideoConfig(streamUrl: 'rtsp://recorder/live'),
        sessionFactory: () {
          count++;
          return FakeSession()..frame = Uint8List.fromList([1]);
        },
      );
      for (final minute in [0, 5, 0]) {
        final ticket = previews.request(clip(minute));
        await tester.pump();
        expect(await ticket.image, [1]);
        ticket.release();
      }
      expect(count, 3);
      previews.dispose();
      final delayedHost = MemoryHost()..delayedSecret = Completer<String?>();
      final delayed = RecordingPreviews(
        host: delayedHost,
        config: const VideoConfig(streamUrl: 'rtsp://recorder/live'),
        sessionFactory: FakeSession.new,
      );
      final ticket = delayed.request(clip(0));
      await tester.pump();
      delayed.dispose();
      delayedHost.delayedSecret!.complete(null);
      await tester.pump();
      expect(await ticket.image, isNull);
      expect(delayedHost.network.leases, isEmpty);
    },
  );

  testWidgets(
    'vertical timeline shows event labels, real image bytes, and selectable cards',
    (tester) async {
      final frame = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(4, 4);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        image.dispose();
        picture.dispose();
        return bytes;
      });
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final previews = RecordingPreviews(
        host: MemoryHost(),
        config: const VideoConfig(streamUrl: 'rtsp://recorder/live'),
        sessionFactory: () => FakeSession()..frame = frame,
      );
      final records = [
        clip(0, events: [RecordingEvent.motion]),
        clip(5, events: [RecordingEvent.human]),
      ];
      Recording? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                RecordingTimeline(
                  records: records,
                  previews: previews,
                  onSelected: (r) => selected = r,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Motion'), findsOneWidget);
      expect(find.text('Person'), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(2));
      final first = tester.getCenter(
        find.byKey(ValueKey('timeline-dot/${records.first.identity}')),
      );
      final last = tester.getCenter(
        find.byKey(ValueKey('timeline-dot/${records.last.identity}')),
      );
      expect(first.dx, last.dx);
      expect(last.dy, greaterThan(first.dy));
      await tester.tap(find.text('Person'));
      expect(selected, records.last);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      previews.dispose();
    },
  );
}
