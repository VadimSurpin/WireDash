import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash_video/wiredash_video.dart';

class _RealNetwork extends HttpOverrides {}

void main() {
  test(
    'legacy DVR local Z timestamps use recorder POSIX offset rather than phone timezone',
    () {
      const clock = RecorderClock(local: true, zone: 'CST-3:00:00');
      final instant = DateTime.utc(2026, 10, 31, 7, 15, 30);
      expect(clock.parse('2026-10-31T10:15:30Z'), instant);
      expect(clock.parse('2026-10-31T10:15:30'), instant);
      expect(clock.parse('2026-10-31T10:15:30+03:00'), instant);
      expect(clock.format(instant), '2026-10-31T10:15:30');
      expect(
        clock.rtsp(
          instant,
          template: Uri.parse(
            'rtsp://dvr/Streaming/tracks/101?starttime=20261031T101530Z',
          ),
        ),
        '20261031T101530Z',
      );
      final record = Recording(
        start: instant,
        end: instant.add(const Duration(minutes: 10)),
        playback: Uri.parse(
          'rtsp://internal/Streaming/tracks/101?name=file&size=100&starttime=20261031T101530Z',
        ),
        clock: clock,
      );
      final restored = RecordingCache.decodeRecord(
        RecordingCache.encodeRecord(record),
        const VideoConfig(streamUrl: 'rtsp://public/live'),
      );
      final file = HikvisionClient.filePlayback(
        const VideoConfig(streamUrl: 'rtsp://public/live'),
        restored,
        instant.add(const Duration(seconds: 10)),
      );
      expect(file.queryParameters['starttime'], '20261031T101540Z');
      expect(file.queryParameters['endtime'], '20261031T102530Z');
      expect(file.queryParameters['name'], 'file');
      expect(file.host, 'public');
    },
  );

  test(
    'legacy archive offsets follow recorder daylight saving rules across the search week',
    () {
      const clock = RecorderClock(
        local: true,
        zone: 'CST-1:00:00DST01:00:00,M3.5.0/02:00:00,M10.5.0/03:00:00',
      );
      expect(
        clock.parse('2026-10-24T12:00:00Z'),
        DateTime.utc(2026, 10, 24, 10),
      );
      expect(
        clock.parse('2026-10-26T12:00:00Z'),
        DateTime.utc(2026, 10, 26, 11),
      );
      expect(
        clock.format(DateTime.utc(2026, 10, 24, 10)),
        '2026-10-24T12:00:00',
      );
      expect(
        clock.format(DateTime.utc(2026, 10, 26, 11)),
        '2026-10-26T12:00:00',
      );
    },
  );

  for (final standard in [true, false]) {
    test(
      'real HTTP archive search negotiates ${standard ? 'STD UTC' : 'legacy local'} time and preserves the playback basis',
      () async {
        await HttpOverrides.runWithHttpOverrides(() async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          final searches = <String>[];
          server.listen((request) async {
            final body = await utf8.decoder.bind(request).join();
            if (request.uri.path == '/ISAPI/System/capabilities') {
              request.response.write(
                '<DeviceCap><isSupportTimeTypeSTD>$standard</isSupportTimeTypeSTD></DeviceCap>',
              );
            } else if (request.uri.path == '/ISAPI/System/time/timeType') {
              request.response.write('{"TimeType":{"type":"local"}}');
            } else if (request.uri.path == '/ISAPI/System/time') {
              request.response.write(
                '<Time><localTime>2026-10-31T12:00:00+03:00</localTime><timeZone>CST-3:00:00</timeZone></Time>',
              );
            } else {
              searches.add(body);
              expect(
                request.uri.queryParameters['timeType'],
                standard ? 'STD' : null,
              );
              final hour = standard ? '07' : '10';
              request.response.write(
                '<CMSearchResult><responseStatusStrg>OK</responseStatusStrg><matchList>'
                '<searchMatchItem><trackID>101</trackID><timeSpan><startTime>2026-10-31T$hour:15:30Z</startTime><endTime>2026-10-31T$hour:16:30Z</endTime></timeSpan>'
                '<playbackURI>rtsp://internal/Streaming/tracks/101?name=file&amp;size=100&amp;starttime=20261031T${hour}1530Z&amp;endtime=20261031T${hour}1630Z</playbackURI>'
                '</searchMatchItem></matchList></CMSearchResult>',
              );
            }
            await request.response.close();
          });
          final client = HikvisionClient(
            config: VideoConfig(
              streamUrl: 'rtsp://dvr/live',
              recorderUrl: 'http://127.0.0.1:${server.port}',
            ),
            credentials: const VideoCredentials('', ''),
          );
          try {
            await client.discoverClock();
            final start = DateTime.utc(2026, 10, 31, 7, 15, 30);
            final page = await client.search(
              start: start,
              end: start.add(const Duration(minutes: 1)),
            );
            expect(
              searches.single,
              contains(
                standard
                    ? '<startTime>2026-10-31T07:15:30Z</startTime>'
                    : '<startTime>2026-10-31T10:15:30</startTime>',
              ),
            );
            final record = page.records.single;
            expect(record.start, start);
            final playback = HikvisionClient.continuousPlayback(
              client.config,
              record.start,
              source: record.playback,
              clock: record.clock,
            );
            expect(
              playback.queryParameters['starttime'],
              standard ? '20261031T071530Z' : '20261031T101530Z',
            );
            expect(
              playback.queryParameters['timeType'],
              standard ? 'STD' : null,
            );
          } finally {
            client.close();
            await server.close(force: true);
          }
        }, _RealNetwork());
      },
    );
  }
}
