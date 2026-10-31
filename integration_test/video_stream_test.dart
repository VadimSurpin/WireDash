import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wiredash_video/wiredash_video.dart';
import 'package:wiredash_plugin_api/wiredash_plugin_api.dart';

class _CameraHost implements PluginHost {
  @override
  final network = const DirectPluginNetwork();
  @override
  Future<String?> readSecret(String key) async =>
      const VideoCredentials('viewer', 'viewer-test').encode();
  @override
  Future<void> writeSecret(String key, String value) async {}
  @override
  Future<void> deleteSecret(String key) async {}
}

/// Synthetic RTSP source, with a real Android decoder/texture. No MQTT account
/// or physical camera is used. Run through the video-preview GitHub workflow.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const source = String.fromEnvironment('WIREDASH_TEST_RTSP');
  testWidgets('Android decodes and renders authenticated RTSP over TCP', (
    tester,
  ) async {
    expect(
      source,
      isNotEmpty,
      reason: 'Set WIREDASH_TEST_RTSP to the fixture source.',
    );
    final session = NativeVideoSession();
    final errors = <String>[];
    final diagnostics = session.player.stream.log.listen((message) {
      if (message.level == 'error') {
        errors.add(
          message.text.replaceAll(RegExp(r'rtsps?://\S+'), '<fixture stream>'),
        );
      }
    });
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: session.buildView(),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await session.open(Uri.parse(source), muted: true);
        await session.controller.waitUntilFirstFrameRendered.timeout(
          const Duration(seconds: 40),
        );
      });
      await tester.pump(const Duration(seconds: 1));
      expect(session.player.state.width, 320);
      expect(session.player.state.height, 180);
      expect(session.error, isNull, reason: 'Decoder errors: $errors');
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 300));
      final screenshot = await binding.takeScreenshot('rtsp-frame');
      final directory = await getApplicationSupportDirectory();
      await File('${directory.path}/rtsp-frame.png').writeAsBytes(screenshot);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await diagnostics.cancel();
      await session.close();
    }
  });

  testWidgets(
    'timeline extracts a saved-stream preview without a visible player',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      final session = NativeVideoSession.preview();
      final errors = <String>[];
      final diagnostics = session.player.stream.log.listen((message) {
        if (message.level == 'error') {
          errors.add(
            message.text.replaceAll(
              RegExp(r'rtsps?://\S+'),
              '<fixture stream>',
            ),
          );
        }
      });
      try {
        await tester.pump();
        try {
          await session
              .open(Uri.parse(source), muted: true)
              .timeout(const Duration(seconds: 30));
        } catch (e) {
          fail('Preview open failed: $e; decoder errors: $errors');
        }
        final image = await session.captureFrame().timeout(
          const Duration(seconds: 5),
        );
        expect(
          image,
          isNotNull,
          reason:
              'Platform ${session.player.platform.runtimeType}; '
              'playing=${session.playing}, buffering=${session.buffering}, position=${session.position}; errors=$errors',
        );
        expect(image!.take(2), [0xff, 0xd8]);
        expect(session.player.state.width, 320);
        final directory = await getApplicationSupportDirectory();
        await File(
          '${directory.path}/recording-preview.jpg',
        ).writeAsBytes(image);
        final cacheDirectory = Directory('${directory.path}/cache-test');
        final record = Recording(
          start: DateTime.utc(2026, 10, 31),
          end: DateTime.utc(2026, 10, 31, 0, 0, 6),
          playback: Uri.parse(source),
        );
        RecordingCache diskCache() => RecordingCache(
          namespace: 'native-preview',
          directory: cacheDirectory,
          maxMemoryBytes: 0,
        );
        try {
          await diskCache().writeImage(record, image);
          expect(await diskCache().readImage(record), image);
        } finally {
          if (await cacheDirectory.exists()) {
            await cacheDirectory.delete(recursive: true);
          }
        }
      } finally {
        await diagnostics.cancel();
        await session.close();
      }
    },
  );

  testWidgets(
    'historical preview recovers through a real file and caches a decoded JPEG',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      final address = Uri.parse(source).replace(userInfo: '');
      final time = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      final config = VideoConfig(
        streamUrl: address.toString(),
        credentialId: 'fixture',
        useHomeNetwork: false,
      );
      final event = Recording(
        start: time,
        end: time.add(const Duration(seconds: 6)),
        playback: address.replace(path: '/missing-recording'),
      );
      final file = Recording(
        start: time,
        end: time.add(const Duration(hours: 1)),
        playback: address.replace(
          queryParameters: {'name': 'fixture-recording'},
        ),
      );
      final sessions = <NativeVideoSession>[];
      var resolved = 0;
      final previews = RecordingPreviews(
        host: _CameraHost(),
        config: config,
        resolveRecording: (_) async {
          resolved++;
          return file;
        },
        sessionFactory: () {
          final session = NativeVideoSession.preview();
          sessions.add(session);
          return session;
        },
      );
      try {
        await tester.runAsync(() async {
          final image = await previews
              .request(event)
              .image
              .timeout(const Duration(seconds: 45));
          expect(image, isNotNull);
          expect(image!.take(2), [0xff, 0xd8]);
          expect(sessions, hasLength(2));
          expect(resolved, 1);
          expect(await previews.request(event).image, image);
          expect(sessions, hasLength(2));
        });
      } finally {
        previews.dispose();
        for (final session in sessions) {
          await session.close();
        }
      }
    },
  );

  testWidgets(
    'recording viewer recovers from a rejected RTSP range and can seek with a real Android player',
    (tester) async {
      final address = Uri.parse(source).replace(userInfo: '');
      final config = VideoConfig(
        streamUrl: address.toString(),
        credentialId: 'fixture',
        useHomeNetwork: false,
      );
      final time = DateTime.parse(
        HikvisionClient.isoTime(
          DateTime.now().toUtc().subtract(const Duration(hours: 1)),
        ),
      );
      final record = Recording(
        start: time,
        end: time.add(const Duration(hours: 2)),
        playback: address.replace(
          queryParameters: {
            'name': 'fixture-recording',
            'size': '100',
            'starttime': HikvisionClient.isoTime(
              time,
            ).replaceAll('-', '').replaceAll(':', ''),
          },
        ),
      );
      final sessions = <NativeVideoSession>[];
      Future<void> ready(int count) async {
        await tester.runAsync(() async {
          for (var attempt = 0; attempt < 400; attempt++) {
            if (sessions.length >= count &&
                sessions.last.player.state.width == 320 &&
                !sessions.last.buffering &&
                sessions.last.error == null) {
              return;
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          fail(
            'Recording viewer did not recover from the rejected fixture path.',
          );
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VideoPane(
                context: PluginTileContext(
                  id: 'fixture',
                  title: 'Recording',
                  host: _CameraHost(),
                  settings: config.toJson(),
                ),
                playback: HikvisionClient.continuousPlayback(
                  config,
                  time,
                ).replace(path: '/missing-recording'),
                recording: record,
                autoStart: true,
                showRecordings: false,
                videoHeight: 200,
                sessionFactory: () {
                  final session = NativeVideoSession();
                  sessions.add(session);
                  return session;
                },
              ),
            ),
          ),
        );
        await tester.pump();
        await ready(2);
        expect(sessions, hasLength(2));
        expect(find.byKey(const Key('video-viewport')), findsOneWidget);
        expect(find.textContaining('could not start'), findsNothing);
        await tester.tap(find.byTooltip('Rewind 10 seconds'));
        await tester.pump();
        await ready(3);
        expect(find.byType(RecordingTimeRuler), findsOneWidget);
        final ruler = find.byKey(const Key('recording-time-ruler'));
        await tester.tapAt(tester.getCenter(ruler) + const Offset(30, 0));
        await tester.pump();
        await ready(4);
        final screenshot = await binding.takeScreenshot('recording-timeline');
        final directory = await getApplicationSupportDirectory();
        await File(
          '${directory.path}/recording-timeline.png',
        ).writeAsBytes(screenshot);
        expect(find.textContaining('could not start'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        for (final session in sessions) {
          await session.close();
        }
      }
    },
  );
}
