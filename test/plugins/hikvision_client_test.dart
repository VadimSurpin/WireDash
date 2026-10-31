import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash_video/wiredash_video.dart';
import 'package:wiredash_video/src/digest_auth.dart';

void main() {
  test(
    'timeline labels use recorder metadata without inventing presence classifications',
    () {
      const raw =
          '''<CMSearchResult><responseStatus>true</responseStatus><responseStatusStrg>OK</responseStatusStrg>
      <matchList><searchMatchItem><trackID>101</trackID><timeSpan>
      <startTime>2026-10-31T10:00:00Z</startTime><endTime>2026-10-31T10:01:00Z</endTime></timeSpan>
      <playbackURI>rtsp://dvr/Streaming/tracks/101?name=clip</playbackURI>
      <metadataMatches><metadataDescriptor>recordType.meta.isapi.com/timing</metadataDescriptor>
      <metadataDescriptor>recordType.meta.isapi.com/motion</metadataDescriptor></metadataMatches>
      </searchMatchItem></matchList></CMSearchResult>''';
      final record = HikvisionClient.parseRecordings(
        raw,
        const VideoConfig(streamUrl: 'rtsp://dvr/live'),
        0,
      ).records.single;
      expect(record.events, [RecordingEvent.scheduled, RecordingEvent.motion]);
      expect(record.events, isNot(contains(RecordingEvent.human)));
      expect(
        RecordingEvent.fromDescriptor('recordType.meta.isapi.com/unknown'),
        isNull,
      );
      expect(
        Recording(
          start: record.start,
          end: record.end,
          playback: record.playback,
          target: RecordingTarget.vehicle,
        ).events,
        [RecordingEvent.vehicle],
      );
    },
  );
  test('Digest matches the RFC 2617 MD5 auth example', () {
    final auth = DigestAuth(
      const VideoCredentials('Mufasa', 'Circle Of Life'),
      cnonce: () => '0a4f113b',
    );
    final header = auth.authorization(
      'Digest realm="testrealm@host.com", qop="auth,auth-int", nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093", opaque="5ccc069c403ebaf9f0171e9517f40e41"',
      'GET',
      Uri.parse('http://example.com/dir/index.html'),
      '',
    );
    expect(header, contains('response="6629fae49393a05397450978507c4ef1"'));
    expect(header, contains('qop=auth'));
    expect(header, contains('nc=00000001'));
    expect(header, isNot(contains('Circle Of Life')));
  });
  test(
    'SHA-256 digest uses query, increments nc and resets for a fresh nonce',
    () {
      final auth = DigestAuth(
        const VideoCredentials('viewer', 'secret'),
        cnonce: () => 'client',
      );
      const challenge =
          'Digest realm="camera", nonce="first", algorithm=SHA-256, qop="auth"';
      final uri = Uri.parse(
        'http://camera/ISAPI/ContentMgmt/SearchByTargetType?format=json',
      );
      final first = auth.authorization(challenge, 'POST', uri, '{}');
      expect(first, contains('algorithm=SHA-256'));
      expect(
        first,
        contains('uri="/ISAPI/ContentMgmt/SearchByTargetType?format=json"'),
      );
      expect(
        auth.authorization(challenge, 'POST', uri, '{}'),
        contains('nc=00000002'),
      );
      expect(
        auth.authorization(
          challenge.replaceAll('first', 'second'),
          'POST',
          uri,
          '{}',
        ),
        contains('nc=00000001'),
      );
      expect(
        () => auth.authorization(
          'Digest realm="x", nonce="n", qop="unknown"',
          'GET',
          uri,
          '',
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'target search capability reads advertised options rather than unrelated words',
    () {
      final cap = HikvisionClient.parseCapabilities(
        jsonEncode({
          'SearchDescription': {
            'SearchCondList': [
              {
                'targetTypes': {
                  '@opt': ['human', 'vehicle'],
                },
                'description': 'other',
              },
            ],
          },
          'note': 'human vehicle',
        }),
      );
      expect(cap.targets, {
        RecordingTarget.all,
        RecordingTarget.human,
        RecordingTarget.vehicle,
      });
      expect(
        HikvisionClient.parseCapabilities('{"note":"human vehicle"}').targets,
        {RecordingTarget.all},
      );
    },
  );
  test(
    'recording XML handles namespaces, escaped playback queries and MORE paging',
    () {
      const raw =
          '''<CMSearchResult xmlns="http://www.hikvision.com/ver20/XMLSchema">
      <responseStatus>true</responseStatus><responseStatusStrg>MORE</responseStatusStrg>
      <matchList><searchMatchItem><trackID>101</trackID><timeSpan>
        <startTime>2026-10-31T10:00:00+03:00</startTime><endTime>2026-10-31T10:10:00+03:00</endTime></timeSpan>
        <mediaSegmentDescriptor><playbackURI>rtsp://192.168.0.5/Streaming/tracks/101?name=clip&amp;size=123</playbackURI></mediaSegmentDescriptor>
      </searchMatchItem></matchList></CMSearchResult>''';
      final page = HikvisionClient.parseRecordings(
        raw,
        const VideoConfig(streamUrl: 'rtsp://dvr:8554/live'),
        40,
      );
      expect(page.hasMore, isTrue);
      expect(page.nextPosition, 41);
      expect(page.records.single.start.toUtc(), DateTime.utc(2026, 10, 31, 7));
      expect(page.records.single.playback.host, 'dvr');
      expect(page.records.single.playback.queryParameters['name'], 'clip');
    },
  );
  test(
    'failed search XML is reported instead of pretending no recordings exist',
    () {
      expect(
        () => HikvisionClient.parseRecordings(
          '<ResponseStatus><statusCode>4</statusCode></ResponseStatus>',
          const VideoConfig(),
          0,
        ),
        throwsA(isA<RecorderException>()),
      );
      final empty = HikvisionClient.parseRecordings(
        '<CMSearchResult><responseStatusStrg>NO MATCHES</responseStatusStrg></CMSearchResult>',
        const VideoConfig(),
        0,
      );
      expect(empty.records, isEmpty);
      expect(empty.hasMore, isFalse);
    },
  );
  test(
    'human/vehicle matches become bounded RTSP recordings for the right channel',
    () {
      final raw = jsonEncode({
        'SearchResult': {
          'numOfMatches': 1,
          'totalMatches': 3,
          'matchList': [
            {
              'channelID': 2,
              'targetTypes': ['human'],
              'RecordInfoList': [
                {
                  'RecordTime': {
                    'startTime': '2026-10-31T10:00:00Z',
                    'endTime': '2026-10-31T10:01:00Z',
                  },
                },
              ],
            },
          ],
        },
      });
      final page = HikvisionClient.parseTargetRecordings(
        raw,
        const VideoConfig(recorderUrl: 'http://dvr', channel: 2),
        0,
        RecordingTarget.human,
      );
      expect(page.hasMore, isTrue);
      expect(page.nextPosition, 1);
      final record = page.records.single;
      expect(record.target, RecordingTarget.human);
      expect(record.playback.path, '/Streaming/tracks/201');
      expect(record.playback.queryParameters, {
        'starttime': '20261031T100000Z',
        'endtime': '20261031T100100Z',
      });
    },
  );
}
