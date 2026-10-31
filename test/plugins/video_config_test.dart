import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash_video/wiredash_video.dart';
import 'package:wiredash/features/panels/models/panel_config.dart';
import 'package:wiredash/data/database/tables/panels.dart';

void main() {
  test('generic RTSP defaults to 554 and preserves stream path and query', () {
    const config = VideoConfig(
      streamUrl: 'rtsp://camera.example/live/track?quality=low',
    );
    expect(config.validate(), isNull);
    expect(config.liveUri.port, 554);
    expect(config.liveUri.path, '/live/track');
    expect(config.liveUri.query, 'quality=low');
  });
  test(
    'Hikvision channels use N02 for live substream and N01 for recordings',
    () {
      const config = VideoConfig(
        recorderUrl: 'https://192.168.1.64',
        channel: 17,
        recordings: true,
      );
      expect(config.validate(), isNull);
      expect(
        config.liveUri.toString(),
        'rtsp://192.168.1.64:554/Streaming/Channels/1702',
      );
      expect(config.recordingTrack, 1701);
    },
  );
  test('stream credentials are stripped from serialized settings', () {
    const config = VideoConfig(
      streamUrl: 'rtsp://admin:p%40ss%3Aword@camera/live',
      credentialId: 'reference',
    );
    final json = jsonEncode(config.toJson());
    expect(json, isNot(contains('admin')));
    expect(json, isNot(contains('p%40ss')));
    expect(config.liveUri.userInfo, isEmpty);
    final uri = const VideoCredentials(
      'user@home',
      'p:@/ ss',
    ).authenticate(config.liveUri);
    expect(Uri.decodeComponent(uri.userInfo.split(':').first), 'user@home');
    expect(
      Uri.decodeComponent(
        uri.userInfo.substring(uri.userInfo.indexOf(':') + 1),
      ),
      'p:@/ ss',
    );
  });
  test('DVR playback uses configured endpoint and exact returned path/query', () {
    const config = VideoConfig(
      streamUrl: 'rtsp://remote.example:8554/Streaming/Channels/102',
    );
    final uri = config.playbackUri(
      'rtsp://leak:secret@10.0.0.4/Streaming/tracks/101?name=file&starttime=20261031T010000Z',
    );
    expect(uri.host, 'remote.example');
    expect(uri.port, 8554);
    expect(uri.userInfo, isEmpty);
    expect(uri.path, '/Streaming/tracks/101');
    expect(uri.queryParameters['name'], 'file');
    expect(
      () => config.playbackUri('https://evil.example/clip'),
      throwsFormatException,
    );
  });
  test(
    'video plugin envelope and unknown plugin settings survive a round trip',
    () {
      const original = PluginPanelConfig(
        pluginId: 'vendor.other',
        settings: {
          'future': [1, 2],
          'version': 9,
        },
      );
      final decoded =
          PanelConfig.decode(PanelType.plugin, original.encode())
              as PluginPanelConfig;
      expect(decoded.pluginId, 'vendor.other');
      expect(decoded.settings, original.settings);
    },
  );
  test(
    'recording configuration rejects credential-bearing HTTP base URLs and invalid channels',
    () {
      expect(
        const VideoConfig(
          recorderUrl: 'http://admin:secret@camera',
          recordings: true,
        ).validate(),
        isNotNull,
      );
      expect(
        const VideoConfig(streamUrl: 'http://camera/live').validate(),
        isNotNull,
      );
      expect(
        const VideoConfig(
          streamUrl: 'rtsp://camera/live',
          channel: 0,
        ).validate(),
        isNotNull,
      );
      expect(
        const VideoConfig(
          streamUrl: 'rtsp://camera/live',
          recordings: true,
        ).validate(),
        isNotNull,
      );
    },
  );
}
