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
  Duration get position;
  Duration get duration;
  Widget buildView();
  Future<void> open(Uri uri, {required bool muted});
  Future<void> setMuted(bool muted);
  Future<void> playOrPause();
  Future<void> seek(Duration position);
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
    subscriptions.add(player.stream.position.listen((_) => _changed()));
    subscriptions.add(player.stream.duration.listen((_) => _changed()));
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
  @override
  Duration get position => player.state.position;
  @override
  Duration get duration => player.state.duration;
  void _changed() {
    if (!_closed) notifyListeners();
  }

  @override
  Widget buildView() => Video(
    controller: controller,
    fit: BoxFit.contain,
    controls: NoVideoControls,
    resumeUponEnteringForegroundMode: false,
  );
  @override
  Future<void> open(Uri uri, {required bool muted}) async {
    final platform = player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('rtsp-transport', 'tcp');
      await platform.setProperty('force-media-title', 'WireDash video');
    }
    await player.setVolume(muted ? 0 : 100);
    await player.open(
      Media(uri.toString(), extras: const {'title': 'WireDash video'}),
    );
    // Opening a demuxer alone does not prove that the stream can be decoded.
    // Bound the loading state and let the pane release a failed connection.
    await controller.waitUntilFirstFrameRendered.timeout(
      const Duration(seconds: 20),
    );
    if (!_closed) {
      _error = null;
      _buffering = false;
      _changed();
    }
  }

  @override
  Future<void> setMuted(bool muted) => player.setVolume(muted ? 0 : 100);
  @override
  Future<void> playOrPause() => player.playOrPause();
  @override
  Future<void> seek(Duration position) => player.seek(position);
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
