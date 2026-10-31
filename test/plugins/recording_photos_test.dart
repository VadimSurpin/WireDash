import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash_plugin_api/wiredash_plugin_api.dart';
import 'package:wiredash_video/wiredash_video.dart';
import 'plugin_test_fakes.dart';

class _RealNetwork extends HttpOverrides {}

String pictureMatch(
  int track,
  String time,
  String type, {
  String path = '/ISAPI/Streaming/tracks/103/',
}) =>
    '<searchMatchItem><trackID>$track</trackID><timeSpan><startTime>$time</startTime><endTime>$time</endTime></timeSpan>'
    '<mediaSegmentDescriptor><contentType>picture</contentType><codecType>jpeg</codecType>'
    '<playbackURI>http://admin:private@internal$path?name=capture&amp;size=123</playbackURI></mediaSegmentDescriptor>'
    '<metadataMatches><metadataDescriptor>recordType.meta.isapi.com/$type</metadataDescriptor></metadataMatches></searchMatchItem>';

Recording get detectionClip => Recording(
  start: DateTime.utc(2026, 10, 31, 10),
  end: DateTime.utc(2026, 10, 31, 10, 10),
  playback: Uri.parse('rtsp://recorder/Streaming/tracks/101?name=video'),
  target: RecordingTarget.human,
);

class _PhotoFixture extends RecordingPhotos {
  _PhotoFixture(this.frame)
    : super(
        host: MemoryHost(),
        config: const VideoConfig(),
        cache: RecordingCache(namespace: 'fixture', memoryOnly: true),
      );
  final Uint8List frame;
  @override
  Future<RecordingPicture?> find(Recording record) async => RecordingPicture(
    DateTime.utc(2026, 10, 31, 10, 3, 42),
    Uri.parse('http://recorder/ISAPI/Streaming/tracks/103?name=event'),
    const [RecordingEvent.human],
  );
  @override
  Future<List<int>> bytes(RecordingPicture picture) async => frame;
}

void main() {
  test(
    'picture search accepts instantaneous captures and rejects wrong channels or arbitrary download paths',
    () {
      const config = VideoConfig(recorderUrl: 'https://public-recorder:8443');
      final photos = HikvisionClient.parsePictures(
        '<CMSearchResult><responseStatusStrg>OK</responseStatusStrg><matchList>'
        '${pictureMatch(103, '2026-10-31T10:03:42Z', 'human')}'
        '${pictureMatch(203, '2026-10-31T10:03:42Z', 'vehicle')}'
        '${pictureMatch(103, '2026-10-31T10:03:43Z', 'human', path: '/private-login')}'
        '</matchList></CMSearchResult>',
        config,
      );
      expect(photos, hasLength(1));
      expect(photos.single.time, DateTime.utc(2026, 10, 31, 10, 3, 42));
      expect(photos.single.events, [RecordingEvent.human]);
      expect(photos.single.uri.origin, 'https://public-recorder:8443');
      expect(photos.single.uri.userInfo, isEmpty);
      expect(photos.single.uri.hasFragment, isFalse);
      expect(photos.single.uri.queryParameters['name'], 'capture');
    },
  );

  test(
    'classified event photo uses its capture time, Digest and cache without decoding the pre-recording',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var requests = 0, photoRequests = 0;
        final jpeg = Uint8List.fromList([0xff, 0xd8, 1, 2, 0xff, 0xd9]);
        server.listen((request) async {
          requests++;
          final body = await utf8.decoder.bind(request).join();
          if (request.headers.value(HttpHeaders.authorizationHeader) == null) {
            request.response.statusCode = 401;
            request.response.headers.set(
              HttpHeaders.wwwAuthenticateHeader,
              'Digest realm="recorder", nonce="first", qop="auth"',
            );
          } else if (request.uri.path.endsWith('capabilities')) {
            request.response.write(
              '<RacmCap><pictureSearchType opt="MOTION,human,vehicle"/></RacmCap>',
            );
          } else if (request.uri.path.endsWith('search')) {
            expect(body, contains('<trackID>103</trackID>'));
            expect(
              body,
              contains('<startTime>2026-10-31T10:00:00Z</startTime>'),
            );
            expect(request.headers.chunkedTransferEncoding, isFalse);
            expect(request.contentLength, utf8.encode(body).length);
            request.response.write(
              '<CMSearchResult><responseStatusStrg>OK</responseStatusStrg><matchList>'
              '${pictureMatch(103, '2026-10-31T10:01:00Z', 'timing')}'
              '${pictureMatch(103, '2026-10-31T10:02:00Z', 'vehicle')}'
              '${pictureMatch(103, '2026-10-31T10:03:00Z', 'motion')}'
              '${pictureMatch(103, '2026-10-31T10:03:42Z', 'human')}'
              '</matchList></CMSearchResult>',
            );
          } else {
            photoRequests++;
            expect(request.uri.path, '/ISAPI/Streaming/tracks/103/');
            expect(
              request.headers.value(HttpHeaders.acceptHeader),
              'image/jpeg',
            );
            expect(
              request.headers.value(HttpHeaders.authorizationHeader),
              contains(
                'uri="/ISAPI/Streaming/tracks/103/?name=capture&size=123"',
              ),
            );
            request.response.headers.contentType = ContentType('image', 'jpeg');
            request.response.add(jpeg);
          }
          await request.response.close();
        });
        final host = MemoryHost()
          ..secrets['camera-login'] = const VideoCredentials(
            'viewer',
            'secret',
          ).encode();
        final config = VideoConfig(
          streamUrl: 'rtsp://recorder/live',
          recorderUrl: 'http://127.0.0.1:${server.port}',
          credentialId: 'camera-login',
        );
        final cache = RecordingCache(
          namespace: 'stored-photos',
          memoryOnly: true,
        );
        RecordingPreviews previews() => RecordingPreviews(
          host: host,
          config: config,
          cache: cache,
          photos: RecordingPhotos(host: host, config: config, cache: cache),
          sessionFactory: () => throw StateError(
            'A stored event photo must not open a video decoder',
          ),
        );
        RecordingPreviews? active;
        try {
          active = previews();
          final photo = await active.request(detectionClip).preview;
          expect(photo, isNotNull);
          expect(photo!.eventPhoto, isTrue);
          expect(photo.time, DateTime.utc(2026, 10, 31, 10, 3, 42));
          expect(photo.bytes, jpeg);
          expect(host.network.leases, isEmpty);
          expect(photoRequests, 1);
          final before = requests;
          active.dispose();
          active = previews();
          final restored = await active.request(detectionClip).preview;
          expect(restored!.time, photo.time);
          expect(restored.bytes, jpeg);
          expect(requests, before);
        } finally {
          active?.dispose();
          await server.close(force: true);
        }
      }, _RealNetwork());
    },
  );

  testWidgets(
    'preview photo taps select the capture timestamp several minutes after recording start',
    (tester) async {
      final frame = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(
          recorder,
        ).drawColor(const Color(0xff789abc), ui.BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(16, 9);
        final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return encoded!.buffer.asUint8List();
      });
      final previews = RecordingPreviews(
        host: MemoryHost(),
        config: const VideoConfig(),
        photos: _PhotoFixture(frame!),
        sessionFactory: () => throw StateError('No decoder needed'),
      );
      Recording? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                RecordingTimeline(
                  records: [detectionClip],
                  previews: previews,
                  onSelected: (r) => selected = r,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Person capture'), findsOneWidget);
      expect(find.textContaining('detection photo unavailable'), findsNothing);
      await tester.tap(find.byType(Image));
      expect(selected!.start, detectionClip.start);
      expect(selected!.playbackTime, DateTime.utc(2026, 10, 31, 10, 3, 42));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      previews.dispose();
    },
  );

  testWidgets(
    'rewind and forward reopen unknown-duration RTSP at wall-clock time and release old routes',
    (tester) async {
      final host = MemoryHost();
      final sessions = <FakeSession>[];
      const config = VideoConfig(streamUrl: 'rtsp://recorder:8554/live');
      final start = DateTime.utc(2026, 10, 31, 10, 3, 42);
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
              sessionFactory: () {
                final session = FakeSession();
                sessions.add(session);
                return session;
              },
              playback: HikvisionClient.continuousPlayback(config, start),
              autoStart: true,
              showRecordings: false,
              videoHeight: 200,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNothing);
      sessions.last.position = const Duration(seconds: 17);
      sessions.last.notifyListeners();
      await tester.pump();
      await tester.tap(find.byTooltip('Rewind 10 seconds'));
      await tester.pumpAndSettle();
      expect(sessions.last.opened!.queryParameters, {
        'starttime': '20261031T100349Z',
      });
      expect(sessions.first.closed, isTrue);
      expect(host.network.leases.first.closed, isTrue);
      sessions.last.position = const Duration(seconds: 2);
      await tester.tap(find.byTooltip('Forward 1 minute'));
      await tester.pumpAndSettle();
      expect(
        sessions.last.opened!.queryParameters['starttime'],
        '20261031T100451Z',
      );
      await tester.tap(find.byTooltip('Rewind 1 minute'));
      await tester.pumpAndSettle();
      expect(
        sessions.last.opened!.queryParameters['starttime'],
        '20261031T100351Z',
      );
      await tester.tap(find.byTooltip('Return to selected event'));
      await tester.pumpAndSettle();
      expect(
        sessions.last.opened!.queryParameters['starttime'],
        '20261031T100342Z',
      );
      expect(find.text('2026-10-31 10:03:42'), findsOneWidget);
      await tester.tap(find.byTooltip('Rewind 1 minute'));
      await tester.pumpAndSettle();
      expect(
        sessions.last.opened!.queryParameters['starttime'],
        '20261031T100242Z',
      );
      sessions.last.position = const Duration(seconds: 17);
      await tester.tap(find.byTooltip('Fullscreen video'));
      await tester.pumpAndSettle();
      expect(
        sessions.last.opened!.queryParameters['starttime'],
        '20261031T100259Z',
      );
      await tester.tap(
        find.byTooltip('Return to selected event').hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(
        sessions.last.opened!.queryParameters['starttime'],
        '20261031T100342Z',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      expect(sessions.every((s) => s.closed), isTrue);
      expect(host.network.leases.every((l) => l.closed), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'a cancelled stored-photo request cannot block the next preview or open a late decoder',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final seen = Completer<void>(), held = Completer<void>();
        var calls = 0;
        server.listen((request) async {
          await request.drain<void>();
          calls++;
          if (calls == 1) {
            seen.complete();
            await held.future;
          } else {
            request.response.statusCode = 404;
          }
          await request.response.close();
        });
        final host = MemoryHost();
        final config = VideoConfig(
          streamUrl: 'rtsp://recorder/live',
          recorderUrl: 'http://127.0.0.1:${server.port}',
        );
        final cache = RecordingCache(
          namespace: 'cancelled-photos',
          memoryOnly: true,
        );
        final sessions = <FakeSession>[];
        final previews = RecordingPreviews(
          host: host,
          config: config,
          cache: cache,
          photos: RecordingPhotos(host: host, config: config, cache: cache),
          sessionFactory: () {
            final s = FakeSession()..frame = Uint8List.fromList([1, 2, 3]);
            sessions.add(s);
            return s;
          },
        );
        try {
          final first = previews.request(detectionClip);
          await seen.future.timeout(const Duration(seconds: 2));
          first.release();
          final second = previews.request(
            Recording(
              start: detectionClip.start.add(const Duration(hours: 1)),
              end: detectionClip.end.add(const Duration(hours: 1)),
              playback: detectionClip.playback,
            ),
          );
          expect(await first.image, isNull);
          expect(await second.image.timeout(const Duration(seconds: 2)), [
            1,
            2,
            3,
          ]);
          expect(sessions, hasLength(1));
          expect(sessions.single.closed, isTrue);
          expect(calls, 2);
        } finally {
          held.complete();
          previews.dispose();
          await server.close(force: true);
        }
      }, _RealNetwork());
    },
  );

  test(
    'missing captures are cached and Refresh discovers newly enabled event pictures',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var available = false, calls = 0;
        server.listen((request) async {
          calls++;
          await request.drain<void>();
          if (request.uri.path.endsWith('capabilities')) {
            request.response.write(
              '<RacmCap><pictureSearchType>MOTION,human</pictureSearchType></RacmCap>',
            );
          } else {
            request.response.write(
              available
                  ? '<CMSearchResult><responseStatusStrg>OK</responseStatusStrg><matchList>${pictureMatch(103, '2026-10-31T10:03:42Z', 'human')}</matchList></CMSearchResult>'
                  : '<CMSearchResult><responseStatusStrg>NO MATCHES</responseStatusStrg></CMSearchResult>',
            );
          }
          await request.response.close();
        });
        final photos = RecordingPhotos(
          host: MemoryHost(),
          config: VideoConfig(recorderUrl: 'http://127.0.0.1:${server.port}'),
          cache: RecordingCache(namespace: 'new-captures', memoryOnly: true),
        );
        try {
          expect(await photos.find(detectionClip), isNull);
          expect(calls, 2);
          available = true;
          expect(await photos.find(detectionClip), isNull);
          expect(calls, 2);
          photos.refresh();
          expect(
            (await photos.find(detectionClip))!.time,
            DateTime.utc(2026, 10, 31, 10, 3, 42),
          );
          expect(calls, 4);
        } finally {
          photos.dispose();
          await server.close(force: true);
        }
      }, _RealNetwork());
    },
  );
}
