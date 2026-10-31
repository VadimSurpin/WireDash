import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash_video/wiredash_video.dart';

class _RealNetwork extends HttpOverrides {}

void main() {
  test(
    'DVR HTTP uses Digest, the exact recording track, and stable page search ID',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final bodies = <String>[];
        var challenges = 0;
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          final authorization = request.headers.value(
            HttpHeaders.authorizationHeader,
          );
          if (authorization == null) {
            challenges++;
            request.response.statusCode = 401;
            request.response.headers.set(
              HttpHeaders.wwwAuthenticateHeader,
              'Digest realm="Hikvision", nonce="recorder-nonce", qop="auth", algorithm=MD5',
            );
          } else {
            expect(authorization, contains('Digest username="viewer"'));
            expect(authorization, contains('uri="/ISAPI/ContentMgmt/search"'));
            expect(authorization, isNot(contains('password')));
            bodies.add(body);
            request.response.headers.contentType = ContentType(
              'application',
              'xml',
            );
            request.response.write(
              '<CMSearchResult><responseStatus>true</responseStatus><responseStatusStrg>NO MATCHES</responseStatusStrg></CMSearchResult>',
            );
          }
          await request.response.close();
        });
        final client = HikvisionClient(
          config: VideoConfig(
            recorderUrl: 'http://127.0.0.1:${server.port}',
            channel: 17,
          ),
          credentials: const VideoCredentials('viewer', 'password'),
        );
        try {
          final start = DateTime.utc(2026, 10, 30),
              end = DateTime.utc(2026, 10, 31);
          await client.search(
            start: start,
            end: end,
            searchId: 'same-search',
            position: 0,
          );
          await client.search(
            start: start,
            end: end,
            searchId: 'same-search',
            position: 40,
          );
          expect(challenges, 1);
          expect(bodies, hasLength(2));
          expect(
            bodies.every(
              (body) =>
                  body.contains('<trackID>1701</trackID>') &&
                  body.contains('<searchID>same-search</searchID>'),
            ),
            isTrue,
          );
          expect(
            bodies.last,
            contains('<searchResultPostion>40</searchResultPostion>'),
          );
        } finally {
          client.close();
          await server.close(force: true);
        }
      }, _RealNetwork());
    },
  );
  test(
    'target search sends human/vehicle conditions and pages the recorder response',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requests = <Map<String, dynamic>>[];
        server.listen((request) async {
          expect(request.uri.path, '/ISAPI/ContentMgmt/SearchByTargetType');
          expect(request.uri.queryParameters['format'], 'json');
          requests.add(
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>,
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'SearchResult': {
                'numOfMatches': 1,
                'totalMatches': 1,
                'matchList': [
                  {
                    'channelID': 3,
                    'targetTypes': ['vehicle'],
                    'RecordInfoList': [
                      {
                        'RecordTime': {
                          'startTime': '2026-10-30T12:00:00Z',
                          'endTime': '2026-10-30T12:01:00Z',
                        },
                      },
                    ],
                  },
                ],
              },
            }),
          );
          await request.response.close();
        });
        final client = HikvisionClient(
          config: VideoConfig(
            recorderUrl: 'http://127.0.0.1:${server.port}',
            channel: 3,
          ),
          credentials: const VideoCredentials('', ''),
        );
        try {
          final page = await client.search(
            start: DateTime.utc(2026, 10, 30),
            end: DateTime.utc(2026, 10, 31),
            target: RecordingTarget.vehicle,
          );
          final condition =
              (requests.single['SearchDescription'] as Map)['SearchCondList'][0]
                  as Map;
          expect(condition['channelID'], 3);
          expect(condition['targetTypes'], ['vehicle']);
          expect(page.records.single.target, RecordingTarget.vehicle);
          expect(page.hasMore, isFalse);
        } finally {
          client.close();
          await server.close(force: true);
        }
      }, _RealNetwork());
    },
  );
  test(
    'unsupported target filters keep time search available; redirects never receive credentials',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var requests = 0;
        server.listen((request) async {
          requests++;
          await request.drain<void>();
          request.response.statusCode =
              request.uri.path.contains('capabilities') ? 404 : 302;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            'http://other-recorder.example/private',
          );
          await request.response.close();
        });
        final client = HikvisionClient(
          config: VideoConfig(recorderUrl: 'http://127.0.0.1:${server.port}'),
          credentials: const VideoCredentials('viewer', 'secret'),
        );
        try {
          expect((await client.capabilities()).targets, {RecordingTarget.all});
          await expectLater(
            client.search(
              start: DateTime.utc(2026, 10, 30),
              end: DateTime.utc(2026, 10, 31),
            ),
            throwsA(
              isA<RecorderException>().having((e) => e.status, 'status', 302),
            ),
          );
          expect(requests, 2);
        } finally {
          client.close();
          await server.close(force: true);
        }
      }, _RealNetwork());
    },
  );
}
