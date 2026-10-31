import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash_plugin_api/wiredash_plugin_api.dart';
import 'package:wiredash_video/wiredash_video.dart';
import 'plugin_test_fakes.dart';

void main() {
  testWidgets(
    'unavailable overlay disappears when the existing stream recovers',
    (tester) async {
      final session = FakeSession();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoTile(
              context: PluginTileContext(
                id: 'c',
                title: 'Camera',
                host: MemoryHost(),
                settings: const VideoConfig(
                  streamUrl: 'rtsp://camera/live',
                ).toJson(),
              ),
              sessionFactory: () => session,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Play live video'));
      await tester.pumpAndSettle();
      session.health.failed(const Duration(seconds: 20));
      session.notifyListeners();
      await tester.pump();
      expect(find.textContaining('Video unavailable'), findsOneWidget);
      session.health.progress(
        const Duration(seconds: 1),
        playing: true,
        buffering: false,
      );
      session.notifyListeners();
      await tester.pump();
      expect(find.textContaining('Video unavailable'), findsNothing);
      expect(find.byKey(const Key('fake-video')), findsOneWidget);
      expect(session.closed, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'pinch zoom, dragging and reset affect video while controls stay fixed',
    (tester) async {
      final session = FakeSession();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoTile(
              context: PluginTileContext(
                id: 'camera',
                title: 'Driveway',
                host: MemoryHost(),
                settings: const VideoConfig(
                  streamUrl: 'rtsp://camera/live',
                  recordings: true,
                  recorderUrl: 'http://camera',
                ).toJson(),
              ),
              sessionFactory: () => session,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Play live video'));
      await tester.pumpAndSettle();
      final viewport = find.byKey(const Key('video-viewport'));
      final controller = tester
          .widget<InteractiveViewer>(viewport)
          .transformationController!;
      final controls = tester.getCenter(find.byTooltip('Saved recordings'));
      final center = tester.getCenter(viewport);
      final first = await tester.startGesture(
        center - const Offset(35, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(35, 0),
        pointer: 2,
      );
      await tester.pump();
      await first.moveTo(center - const Offset(90, 0));
      await second.moveTo(center + const Offset(90, 0));
      await tester.pump();
      await first.up();
      await second.up();
      expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
      final translation = controller.value.getTranslation().clone();
      await tester.drag(viewport, const Offset(30, 20));
      await tester.pump();
      expect(controller.value.getTranslation(), isNot(translation));
      expect(tester.getCenter(find.byTooltip('Saved recordings')), controls);
      expect(find.byTooltip('Human and vehicle events'), findsOneWidget);
      await tester.tap(find.byTooltip('Reset zoom'));
      await tester.pump();
      expect(controller.value, Matrix4.identity());
      await tester.tap(find.byTooltip('Pause video'));
      await tester.pump();
      expect(session.paused, isTrue);
      expect(find.byTooltip('Resume video'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'fullscreen transfers playback and releases both routes when dismissed',
    (tester) async {
      final host = MemoryHost();
      final sessions = <FakeSession>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoTile(
              context: PluginTileContext(
                id: 'c',
                title: 'Camera',
                host: host,
                settings: const VideoConfig(
                  streamUrl: 'rtsp://camera/live',
                ).toJson(),
              ),
              sessionFactory: () {
                final session = FakeSession();
                sessions.add(session);
                return session;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Play live video'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Fullscreen video'));
      await tester.pumpAndSettle();
      expect(sessions, hasLength(2));
      expect(sessions.first.closed, isTrue);
      expect(host.network.leases.first.closed, isTrue);
      expect(find.byKey(const Key('video-viewport')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(sessions.last.closed, isTrue);
      expect(host.network.leases.every((l) => l.closed), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('video editor keeps URL logins only in secure storage', () async {
    final host = MemoryHost();
    final editor = VideoEditorController({}, host);
    editor.stream.text = 'rtsp://admin:p%40ss@camera/live';
    await editor.save();
    expect(editor.stream.text, 'rtsp://camera/live');
    expect(editor.settings.toString(), isNot(contains('p%40ss')));
    final saved = VideoCredentials.decode(host.secrets[editor.credentialId]);
    expect(saved.username, 'admin');
    expect(saved.password, 'p@ss');
    editor.dispose();
  });
  test(
    'editing credentials on a duplicated panel leaves the original login intact',
    () async {
      final host = MemoryHost()
        ..secrets['shared'] = const VideoCredentials(
          'original',
          'old',
        ).encode();
      final editor = VideoEditorController({
        'credentialId': 'shared',
        'streamUrl': 'rtsp://camera/live',
      }, host);
      await editor.loadingCredentials;
      editor.username.text = 'new';
      editor.password.text = 'new-password';
      editor.credentialsEdited = true;
      await editor.save();
      expect(editor.credentialId, isNot('shared'));
      expect(
        VideoCredentials.decode(host.secrets['shared']).username,
        'original',
      );
      expect(
        VideoCredentials.decode(host.secrets[editor.credentialId]).username,
        'new',
      );
      editor.dispose();
    },
  );
  testWidgets(
    'embedded video starts on tap and closes player and route in the background',
    (tester) async {
      final host = MemoryHost();
      final session = FakeSession();
      final plugin = VideoPanelPlugin(sessionFactory: () => session);
      final context = PluginTileContext(
        id: 'camera',
        title: 'Driveway',
        host: host,
        settings: const VideoConfig(streamUrl: 'rtsp://camera/live').toJson(),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: plugin.buildTile(context))),
      );
      expect(host.network.leases, isEmpty);
      await tester.tap(find.byTooltip('Play live video'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fake-video')), findsOneWidget);
      expect(session.opened!.host, 'camera');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(session.closed, isTrue);
      expect(host.network.leases.single.closed, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Play live video'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'backgrounding during credential lookup cannot start a late stream',
    (tester) async {
      final host = MemoryHost()..delayedSecret = Completer<String?>();
      var starts = 0;
      final plugin = VideoPanelPlugin(
        sessionFactory: () {
          starts++;
          return FakeSession();
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: plugin.buildTile(
              PluginTileContext(
                id: 'c',
                title: 'Camera',
                host: host,
                settings: const VideoConfig(
                  streamUrl: 'rtsp://camera/live',
                ).toJson(),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Play live video'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      host.delayedSecret!.complete(null);
      await tester.pumpAndSettle();
      expect(starts, 0);
      expect(host.network.leases, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
