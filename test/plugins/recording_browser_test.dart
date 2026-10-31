import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash_plugin_api/wiredash_plugin_api.dart';
import 'package:wiredash_video/wiredash_video.dart';
import 'plugin_test_fakes.dart';

class _RecorderNetwork extends HttpOverrides {}

void main() {
  testWidgets('playing a timeline clip and returning keeps its scroll position', (
    tester,
  ) async {
    late HttpServer server;
    await tester.runAsync(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await request.drain<void>();
        if (request.uri.path.contains('capabilities')) {
          request.response.statusCode = 404;
        } else {
          request.response.headers.contentType = ContentType(
            'application',
            'xml',
          );
          request.response.write(
            '<CMSearchResult><responseStatus>true</responseStatus><responseStatusStrg>OK</responseStatusStrg><matchList>',
          );
          for (var index = 0; index < 12; index++) {
            final start = DateTime.utc(2026, 10, 31, 10, index);
            request.response.write(
              '<searchMatchItem><trackID>101</trackID><timeSpan><startTime>${start.toIso8601String()}</startTime>'
              '<endTime>${start.add(const Duration(minutes: 1)).toIso8601String()}</endTime></timeSpan>'
              '<playbackURI>rtsp://recorder/Streaming/tracks/101?clip=$index</playbackURI>'
              '<metadataDescriptor>recordType.meta.isapi.com/motion</metadataDescriptor></searchMatchItem>',
            );
          }
          request.response.write('</matchList></CMSearchResult>');
        }
        await request.response.close();
      });
    });
    final sessions = <FakeSession>[];
    try {
      await HttpOverrides.runWithHttpOverrides(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: RecordingBrowser(
              context: PluginTileContext(
                id: 'camera',
                title: 'Driveway',
                host: MemoryHost(),
                settings: VideoConfig(
                  streamUrl: 'rtsp://recorder/live',
                  recordings: true,
                  recorderUrl: 'http://127.0.0.1:${server.port}',
                ).toJson(),
              ),
              previewFactory: FakeSession.new,
              sessionFactory: () {
                final s = FakeSession();
                sessions.add(s);
                return s;
              },
            ),
          ),
        );
        for (
          var attempt = 0;
          attempt < 100 && find.byType(RecordingTimeline).evaluate().isEmpty;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(find.byType(RecordingTimeline), findsOneWidget);
        await tester.pumpAndSettle();
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -650));
        await tester.pumpAndSettle();
        final scroll = tester
            .widget<CustomScrollView>(find.byType(CustomScrollView))
            .controller!;
        final offset = scroll.offset;
        expect(offset, greaterThan(100));
        await tester.tap(find.text('Motion').hitTestable().first);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(sessions.single.opened!.path, '/Streaming/tracks/101');
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(sessions.single.closed, isTrue);
        expect(scroll.offset, closeTo(offset, 0.1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, _RecorderNetwork());
    } finally {
      await tester.runAsync(() => server.close(force: true));
    }
  });
}
