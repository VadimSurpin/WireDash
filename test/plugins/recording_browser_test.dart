import 'dart:io';
import 'dart:convert';
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
        await tester.pump();
        for (var attempt = 0; attempt < 100; attempt++) {
          final viewer = tester.widget<VideoPane>(find.byType(VideoPane));
          if (viewer.archive?.loading != true) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(sessions.single.opened!.path, '/Streaming/tracks/101');
        final query = sessions.single.opened!.queryParameters;
        expect(query.keys, ['starttime', 'endtime']);
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

  testWidgets(
    'event filter chips add results, merge classifications, and survive reopening',
    (tester) async {
      late HttpServer server;
      var searchCalls = 0;
      await tester.runAsync(() async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          if (request.method == 'POST') searchCalls++;
          final body = await utf8.decoder.bind(request).join();
          if (request.uri.path == '/ISAPI/System/capabilities') {
            request.response.write(
              '<DeviceCap><isSupportTimeTypeSTD>true</isSupportTimeTypeSTD></DeviceCap>',
            );
          } else if (request.uri.path.contains(
            'SearchByTargetType/capabilities',
          )) {
            request.response.write('{"targetTypes":["human","vehicle"]}');
          } else if (request.uri.path.endsWith('capabilities')) {
            request.response.statusCode = 404;
          } else if (request.uri.path.contains('SearchByTargetType')) {
            final data = jsonDecode(body) as Map;
            final kind =
                data['SearchDescription']['SearchCondList'][0]['targetTypes'][0]
                    as String;
            final minute = kind == 'human' ? '00' : '01';
            request.response.write(
              jsonEncode({
                'SearchResult': {
                  'numOfMatches': 1,
                  'totalMatches': 1,
                  'matchList': [
                    {
                      'channelID': 1,
                      'targetTypes': [kind],
                      'RecordInfoList': [
                        {
                          'RecordTime': {
                            'startTime': '2026-10-31T10:$minute:00Z',
                            'endTime': '2026-10-31T10:$minute:06Z',
                          },
                        },
                      ],
                    },
                  ],
                },
              }),
            );
          } else {
            request.response.write(
              '<CMSearchResult><responseStatusStrg>OK</responseStatusStrg><matchList>',
            );
            for (final entry in [(0, 'motion'), (2, 'alarm'), (3, 'timing')]) {
              final minute = entry.$1.toString().padLeft(2, '0');
              request.response.write(
                '<searchMatchItem><trackID>101</trackID><timeSpan><startTime>2026-10-31T10:$minute:00Z</startTime>'
                '<endTime>2026-10-31T10:$minute:06Z</endTime></timeSpan>'
                '<playbackURI>rtsp://recorder/Streaming/tracks/101?name=file$minute&amp;size=100</playbackURI>'
                '<metadataDescriptor>recordType.meta.isapi.com/${entry.$2}</metadataDescriptor></searchMatchItem>',
              );
            }
            request.response.write('</matchList></CMSearchResult>');
          }
          await request.response.close();
        });
      });
      final cache = RecordingCache(namespace: 'filter-chips', memoryOnly: true);
      Future<void> settled() async {
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          if (find.byType(RecordingTimeline).evaluate().isNotEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty) {
            break;
          }
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }

      Future<void> show({bool events = false}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: RecordingBrowser(
              events: events,
              cache: cache,
              context: PluginTileContext(
                id: 'filters',
                title: 'Camera',
                host: MemoryHost(),
                settings: VideoConfig(
                  streamUrl: 'rtsp://recorder/live',
                  recorderUrl: 'http://127.0.0.1:${server.port}',
                  recordings: true,
                ).toJson(),
              ),
              previewFactory: FakeSession.new,
              sessionFactory: FakeSession.new,
            ),
          ),
        );
        await settled();
      }

      bool checked(String title) => tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, title))
          .selected;
      List<Recording> results() => tester
          .widget<RecordingTimeline>(find.byType(RecordingTimeline))
          .records;
      Future<void> toggle(String title) async {
        await tester.tap(find.widgetWithText(FilterChip, title));
        await settled();
      }

      try {
        await HttpOverrides.runWithHttpOverrides(() async {
          await show();
          await toggle('People');
          expect(checked('People'), isTrue);
          await toggle('Motion detected');
          expect(checked('People'), isTrue);
          expect(checked('Motion detected'), isTrue);
          expect(results(), hasLength(1));
          expect(results().first.events.toSet(), {
            RecordingEvent.motion,
            RecordingEvent.human,
          });
          await toggle('Vehicles');
          expect(checked('People'), isTrue);
          expect(checked('Vehicles'), isTrue);
          expect(checked('Motion detected'), isTrue);
          expect(results(), hasLength(2));
          await toggle('People');
          expect(checked('People'), isFalse);
          expect(checked('Vehicles'), isTrue);
          expect(checked('Motion detected'), isTrue);
          expect(results().first.events, [RecordingEvent.motion]);
          final before = searchCalls;
          await tester.pumpWidget(const SizedBox.shrink());
          await show();
          expect(searchCalls, before);
          expect(checked('Vehicles'), isTrue);
          expect(checked('Motion detected'), isTrue);
          expect(checked('People'), isFalse);
          await toggle('All recordings');
          expect(checked('All recordings'), isTrue);
          expect(
            results().any((r) => r.events.contains(RecordingEvent.scheduled)),
            isTrue,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await show(events: true);
          expect(checked('Motion detected'), isTrue);
          expect(checked('People'), isTrue);
          expect(
            results().any((r) => r.events.contains(RecordingEvent.alarm)),
            isTrue,
          );
          expect(
            results().any((r) => r.events.contains(RecordingEvent.scheduled)),
            isFalse,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }, _RecorderNetwork());
      } finally {
        await tester.runAsync(() => server.close(force: true));
      }
    },
  );
}
