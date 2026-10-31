import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash_plugin_api/wiredash_plugin_api.dart';
import 'package:wiredash_video/wiredash_video.dart';
import 'plugin_test_fakes.dart';

Widget app(String language, Widget child) => MaterialApp(
  locale: Locale(language),
  supportedLocales: const [Locale('en'), Locale('ru'), Locale('he')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: Scaffold(body: child),
);

void main() {
  test('recorder errors translate while preserving diagnostic codes', () {
    const ru = VideoStrings('ru');
    expect(
      ru.text(
        'Recording search rejected by the recorder (400, badXmlContent).',
      ),
      ru.message('recordingRejected', {'details': '400, badXmlContent'}),
    );
    expect(
      ru.text('Event search rejected by the recorder (403).'),
      ru.message('eventRejected', {'details': '403'}),
    );
    expect(
      ru.text(
        'Recorder access denied. Enable recording playback permission (noPermission).',
      ),
      ru.message('accessDenied', {'details': ' (noPermission)'}),
    );
    expect(
      ru.text('Recorder access denied. Enable recording playback permission.'),
      ru.message('accessDenied', {'details': ''}),
    );
    expect(ru.text('My camera'), 'My camera');
    expect(const VideoStrings('xx').message('play'), 'Play video');
  });

  testWidgets(
    'editor follows locale changes without changing saved camera settings',
    (tester) async {
      final controller = VideoEditorController(
        const VideoConfig(
          streamUrl: 'rtsp://camera/live',
          recordings: true,
          playbackTime: RecorderPlaybackTime.local,
          playbackUtcOffset: '+03:00',
        ).toJson(),
        MemoryHost(),
      );
      Widget editor() => SingleChildScrollView(
        child: Builder(builder: controller.buildFields),
      );
      await tester.pumpWidget(app('ru', editor()));
      await tester.pumpAndSettle();
      expect(
        find.text(const VideoStrings('ru').message('streamUrl')),
        findsOneWidget,
      );
      expect(
        find.text(const VideoStrings('ru').message('playbackTime')),
        findsOneWidget,
      );
      expect(find.text('RTSP stream URL'), findsNothing);
      await tester.pumpWidget(app('en', editor()));
      await tester.pumpAndSettle();
      expect(find.text('RTSP stream URL'), findsOneWidget);
      expect(controller.stream.text, 'rtsp://camera/live');
      expect(controller.current.playbackTime, RecorderPlaybackTime.local);
      expect(controller.current.playbackUtcOffset, '+03:00');
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('player controls and an existing error follow locale changes', (
    tester,
  ) async {
    final session = FakeSession();
    final context = PluginTileContext(
      id: 'localized-camera',
      title: 'Front door',
      host: MemoryHost(),
      settings: const VideoConfig(streamUrl: 'rtsp://camera/live').toJson(),
    );
    Widget tile() => VideoTile(context: context, sessionFactory: () => session);
    await tester.pumpWidget(app('ru', tile()));
    await tester.tap(
      find.byTooltip(const VideoStrings('ru').message('playLive')),
    );
    await tester.pumpAndSettle();
    session.health.failed(const Duration(seconds: 20));
    session.notifyListeners();
    await tester.pump();
    expect(
      find.text(const VideoStrings('ru').message('videoUnavailable')),
      findsOneWidget,
    );
    expect(find.text('Front door'), findsOneWidget);
    await tester.pumpWidget(app('en', tile()));
    await tester.pumpAndSettle();
    expect(
      find.text(const VideoStrings('en').message('videoUnavailable')),
      findsOneWidget,
    );
    expect(find.byTooltip('Mute'), findsNothing);
    expect(find.byTooltip('Unmute'), findsOneWidget);
    expect(session.closed, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('recording filters and status are translated in RTL', (
    tester,
  ) async {
    final host = MemoryHost()..delayedSecret = Completer<String?>();
    final context = PluginTileContext(
      id: 'rtl-browser',
      title: 'Entrance',
      host: host,
      settings: const VideoConfig(
        recorderUrl: 'http://recorder',
        recordings: true,
      ).toJson(),
    );
    await tester.pumpWidget(
      app(
        'he',
        RecordingBrowser(
          context: context,
          sessionFactory: FakeSession.new,
          previewFactory: FakeSession.new,
          cache: RecordingCache(namespace: 'rtl-test', memoryOnly: true),
        ),
      ),
    );
    await tester.pump();
    const he = VideoStrings('he');
    final chip = find.text(he.message('motionDetected'));
    expect(chip, findsOneWidget);
    expect(find.text(he.message('people')), findsOneWidget);
    expect(find.text(he.message('searching')), findsOneWidget);
    expect(Directionality.of(tester.element(chip)), TextDirection.rtl);
    expect(find.text('Motion detected'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    host.delayedSecret!.complete(null);
    await tester.pump();
  });

  testWidgets(
    'timeline mirrors its gutter and translates event and duration labels',
    (tester) async {
      final record = Recording(
        start: DateTime.utc(2026, 10, 31, 10),
        end: DateTime.utc(2026, 10, 31, 10, 1),
        playback: Uri.parse('rtsp://recorder/Streaming/tracks/101'),
        eventTypes: const [RecordingEvent.motion],
      );
      final previews = RecordingPreviews(
        host: MemoryHost(),
        config: const VideoConfig(streamUrl: 'rtsp://recorder/live'),
        sessionFactory: FakeSession.new,
      );
      Widget timeline() => CustomScrollView(
        slivers: [
          RecordingTimeline(
            records: [record],
            previews: previews,
            onSelected: (_) {},
          ),
        ],
      );
      await tester.pumpWidget(app('he', timeline()));
      await tester.pumpAndSettle();
      final label = find.text(const VideoStrings('he').message('motion'));
      expect(label, findsOneWidget);
      expect(find.textContaining('Until'), findsNothing);
      final dot = find.byKey(ValueKey('timeline-dot/${record.identity}'));
      expect(tester.getCenter(dot).dx, greaterThan(tester.getCenter(label).dx));
      await tester.pumpWidget(app('en', timeline()));
      await tester.pumpAndSettle();
      expect(find.text('Motion'), findsOneWidget);
      expect(
        tester.getCenter(dot).dx,
        lessThan(tester.getCenter(find.text('Motion')).dx),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      previews.dispose();
    },
  );
}
