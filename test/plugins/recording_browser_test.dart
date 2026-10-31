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
              '<endTime>${start.add(const Duration(seconds: 6)).toIso8601String()}</endTime></timeSpan>'
              '<playbackURI>rtsp://recorder/Streaming/tracks/101?name=clip$index&amp;size=100&amp;starttime=old&amp;endtime=clip-end</playbackURI>'
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
        final query = sessions.single.opened!.queryParameters;
        expect(query.keys, ['starttime']);
        expect(query['starttime'], startsWith('20261031T10'));
        expect(query['starttime'], endsWith('Z'));
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

  testWidgets(
    'reopening reuses cached results, refresh fetches and offline keeps the timeline',
    (tester) async {
      late HttpServer server;
      var requests = 0;
      var offline = false;
      final cache = RecordingCache(
        namespace: 'browser-reopen',
        memoryOnly: true,
      );
      await tester.runAsync(() async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          requests++;
          await request.drain<void>();
          if (offline) {
            request.response.statusCode = 503;
          } else if (request.uri.path.contains('capabilities')) {
            request.response.statusCode = 404;
          } else {
            request.response.headers.contentType = ContentType(
              'application',
              'xml',
            );
            request.response.write(
              '<CMSearchResult><responseStatus>true</responseStatus><responseStatusStrg>OK</responseStatusStrg><matchList>'
              '<searchMatchItem><trackID>101</trackID><timeSpan><startTime>2026-10-31T10:00:00Z</startTime>'
              '<endTime>2026-10-31T10:00:06Z</endTime></timeSpan>'
              '<playbackURI>rtsp://recorder/Streaming/tracks/101?name=clip</playbackURI>'
              '<metadataDescriptor>recordType.meta.isapi.com/motion</metadataDescriptor></searchMatchItem>'
              '</matchList></CMSearchResult>',
            );
          }
          await request.response.close();
        });
      });
      Future<void> settleRequests() async {
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          if (find.byType(RecordingTimeline).evaluate().isNotEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty) {
            return;
          }
        }
        fail('Timeline did not finish loading');
      }

      Future<void> showBrowser() async {
        await tester.pumpWidget(
          MaterialApp(
            home: RecordingBrowser(
              cache: cache,
              context: PluginTileContext(
                id: 'cached-camera',
                title: 'Driveway',
                host: MemoryHost(),
                settings: VideoConfig(
                  streamUrl: 'rtsp://recorder/live',
                  recordings: true,
                  recorderUrl: 'http://127.0.0.1:${server.port}',
                ).toJson(),
              ),
              sessionFactory: FakeSession.new,
              previewFactory: FakeSession.new,
            ),
          ),
        );
        await settleRequests();
      }

      try {
        await HttpOverrides.runWithHttpOverrides(() async {
          await showBrowser();
          final initialRequests = requests;
          expect(initialRequests, greaterThanOrEqualTo(2));
          await tester.pumpWidget(const SizedBox.shrink());
          await showBrowser();
          expect(find.text('Cached results'), findsOneWidget);
          expect(requests, initialRequests);
          await tester.tap(find.byTooltip('Refresh recordings'));
          await settleRequests();
          expect(requests, greaterThan(initialRequests));
          expect(find.text('Cached results'), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
          offline = true;
          await showBrowser();
          expect(find.text('Cached results'), findsOneWidget);
          await tester.tap(find.byTooltip('Refresh recordings'));
          await settleRequests();
          expect(find.byType(RecordingTimeline), findsOneWidget);
          expect(find.textContaining('503'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }, _RecorderNetwork());
      } finally {
        await tester.runAsync(() => server.close(force: true));
      }
    },
  );
}
