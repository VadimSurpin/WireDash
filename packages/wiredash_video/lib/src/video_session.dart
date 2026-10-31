import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

typedef VideoSessionFactory = VideoSession Function();

abstract class VideoSession extends ChangeNotifier {
  bool get buffering;
  bool get playing;
  String? get error;
  Widget buildView();
  Future<void> open(Uri uri, {required bool muted});
  Future<void> setMuted(bool muted);
  Future<void> close();
}

class NativeVideoSession extends VideoSession {
  NativeVideoSession() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError(
        'Native RTSP playback is currently bundled for Android.',
      );
    }
    MediaKit.ensureInitialized();
    player = Player(
      configuration: const PlayerConfiguration(
        title: 'WireDash video',
        bufferSize: 8 * 1024 * 1024,
        protocolWhitelist: [
          'rtsp',
          'rtsps',
          'rtp',
          'tcp',
          'udp',
          'tls',
          'crypto',
          'data',
        ],
      ),
    );
    controller = VideoController(player);
    subscriptions.add(
      player.stream.buffering.listen((value) {
        _buffering = value;
        _changed();
      }),
    );
    subscriptions.add(
      player.stream.playing.listen((value) {
        _playing = value;
        _changed();
      }),
    );
    subscriptions.add(
      player.stream.error.listen((_) {
        _error =
            'Video unavailable. Check the stream address, login and camera codec.';
        _changed();
      }),
    );
  }
  late final Player player;
  late final VideoController controller;
  final subscriptions = <StreamSubscription<dynamic>>[];
  bool _buffering = true, _playing = false, _closed = false;
  String? _error;
  @override
  bool get buffering => _buffering;
  @override
  bool get playing => _playing;
  @override
  String? get error => _error;
  void _changed() {
    if (!_closed) notifyListeners();
  }

  @override
  Widget buildView() => Video(
    controller: controller,
    fit: BoxFit.contain,
    resumeUponEnteringForegroundMode: false,
  );
  @override
  Future<void> open(Uri uri, {required bool muted}) async {
    final platform = player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('rtsp-transport', 'tcp');
      await platform.setProperty('msg-level', 'all=no');
      await platform.setProperty('force-media-title', 'WireDash video');
    }
    await player.setVolume(muted ? 0 : 100);
    await player.open(
      Media(uri.toString(), extras: const {'title': 'WireDash video'}),
    );
  }

  @override
  Future<void> setMuted(bool muted) => player.setVolume(muted ? 0 : 100);
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await player.dispose();
    super.dispose();
  }
}
