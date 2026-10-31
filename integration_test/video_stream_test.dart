import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wiredash_video/wiredash_video.dart';

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
      } finally {
        await diagnostics.cancel();
        await session.close();
      }
    },
  );
}
