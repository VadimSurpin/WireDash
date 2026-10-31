import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash_video/wiredash_video.dart';
import 'package:xml/xml.dart';

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
            // Emulate strict ISAPI firmware: chunked XML and an unknown
            // recording-type descriptor are rejected before searching.
            final document = XmlDocument.parse(body);
            final descriptor = document.descendants
                .whereType<XmlElement>()
                .where((e) => e.name.local == 'metadataDescriptor')
                .single
                .innerText;
            if (request.headers.chunkedTransferEncoding ||
                request.contentLength != utf8.encode(body).length ||
                descriptor != '//recordType.meta.std-cgi.com') {
              request.response.statusCode = 400;
              request.response.write(
                '<ResponseStatus><statusCode>6</statusCode>'
                '<subStatusCode>badXmlContent</subStatusCode></ResponseStatus>',
              );
              await request.response.close();
              return;
            }
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
            searchId: 'C77384AD-66A0-0001-E7C2-1151F04F90B0',
            position: 0,
          );
          await client.search(
            start: start,
            end: end,
            searchId: 'C77384AD-66A0-0001-E7C2-1151F04F90B0',
            position: 40,
          );
          expect(challenges, 1);
          expect(bodies, hasLength(2));
          expect(
            bodies.every(
              (body) =>
                  body.contains('<trackID>1701</trackID>') &&
                  body.contains(
                    '<searchID>C77384AD-66A0-0001-E7C2-1151F04F90B0</searchID>',
                  ),
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
        final framing = <(int, int, bool)>[];
        server.listen((request) async {
          expect(request.uri.path, '/ISAPI/ContentMgmt/SearchByTargetType');
          expect(request.uri.queryParameters['format'], 'json');
          final body = await utf8.decoder.bind(request).join();
          framing.add((
            request.contentLength,
            utf8.encode(body).length,
            request.headers.chunkedTransferEncoding,
          ));
          requests.add(jsonDecode(body) as Map<String, dynamic>);
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
          expect(framing.single.$1, framing.single.$2);
          expect(framing.single.$3, isFalse);
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
  test(
    'recorder rejections expose XML/JSON protocol codes without echoing private data',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        const privateText =
            'rtsp://viewer:private-password@private-camera/live';
        final cases = [
          (
            400,
            RecordingTarget.all,
            '<ResponseStatus xmlns="http://www.isapi.org/ver20/XMLSchema"><statusCode>6</statusCode><subStatusCode>badXmlContent</subStatusCode><errorMsg>$privateText</errorMsg></ResponseStatus>',
            'badXmlContent',
          ),
          (
            400,
            RecordingTarget.vehicle,
            jsonEncode({
              'ResponseStatus': {
                'subStatusCode': 'badJsonContent',
                'errorMsg': privateText,
              },
            }),
            'badJsonContent',
          ),
          (
            400,
            RecordingTarget.all,
            '<html><body>$privateText</body></html>',
            null,
          ),
          (400, RecordingTarget.all, '', null),
          (400, RecordingTarget.all, '{', null),
          (
            400,
            RecordingTarget.all,
            '<ResponseStatus><subStatusCode>$privateText</subStatusCode></ResponseStatus>',
            null,
          ),
          (
            403,
            RecordingTarget.all,
            '<ResponseStatus><subStatusCode>noPermission</subStatusCode></ResponseStatus>',
            'noPermission',
          ),
        ];
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var index = 0;
        server.listen((request) async {
          final item = cases[index++];
          await request.drain<void>();
          request.response.statusCode = item.$1;
          request.response.write(item.$3);
          await request.response.close();
        });
        final client = HikvisionClient(
          config: VideoConfig(recorderUrl: 'http://127.0.0.1:${server.port}'),
          credentials: const VideoCredentials('viewer', 'private-password'),
        );
        try {
          for (final item in cases) {
            await expectLater(
              client.search(
                start: DateTime.utc(2026, 10, 30),
                end: DateTime.utc(2026, 10, 31),
                target: item.$2,
              ),
              throwsA(
                isA<RecorderException>()
                    .having((e) => e.status, 'HTTP status', item.$1)
                    .having((e) => e.code, 'protocol error code', item.$4)
                    .having(
                      (e) => e.message,
                      'safe message',
                      allOf([
                        if (item.$4 != null) contains(item.$4!),
                        isNot(contains('private-password')),
                        isNot(contains('private-camera')),
                        if (item.$1 == 400)
                          contains(
                            item.$2 == RecordingTarget.all
                                ? 'Recording search'
                                : 'Event search',
                          ),
                        if (item.$1 == 403) contains('permission'),
                      ]),
                    ),
              ),
            );
          }
          expect(index, cases.length);
        } finally {
          client.close();
          await server.close(force: true);
        }
      }, _RealNetwork());
    },
  );
}
