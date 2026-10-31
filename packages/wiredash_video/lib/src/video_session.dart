import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

typedef VideoSessionFactory = VideoSession Function();

/// A transient decoder error is obsolete once playback advances again.
class VideoPlaybackHealth {
  String? error;
  Duration _failedAt = Duration.zero;
  void failed(Duration position) {
    _failedAt = position;
    error =
        'Video unavailable. Check the stream address, login and camera codec.';
  }

  void progress(
    Duration position, {
    required bool playing,
    required bool buffering,
  }) {
    if (playing &&
        !buffering &&
        position > Duration.zero &&
        position != _failedAt) {
      error = null;
    }
  }

  void recovered() => error = null;
}

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
  Future<Uint8List?> captureFrame();
  Future<void> close();
}

class NativeVideoSession extends VideoSession {
  NativeVideoSession({this.preview = false}) {
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
    controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: !preview,
      ),
    );
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
      player.stream.error.listen((message) {
        if (message.trim().isEmpty) return;
        health.failed(player.state.position);
        _changed();
      }),
    );
    subscriptions.add(
      player.stream.position.listen((position) {
        health.progress(position, playing: _playing, buffering: _buffering);
        _changed();
      }),
    );
    subscriptions.add(player.stream.duration.listen((_) => _changed()));
  }
  late final Player player;
  late final VideoController controller;
  final bool preview;
  NativeVideoSession.preview() : this(preview: true);
  final health = VideoPlaybackHealth();
  final subscriptions = <StreamSubscription<dynamic>>[];
  bool _buffering = true, _playing = false, _closed = false;
  @override
  bool get buffering => _buffering;
  @override
  bool get playing => _playing;
  @override
  String? get error => health.error;
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
      if (preview) await platform.setProperty('vf', 'scale=320:-2');
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
      health.recovered();
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
  Future<Uint8List?> captureFrame() async {
    final platform = player.platform;
    if (_closed || platform is! NativePlayer) return null;
    final cache = await getTemporaryDirectory();
    final directory = await cache.createTemp('wiredash-preview-');
    try {
      final file = File('${directory.path}/frame.jpg');
      // The Android screenshot-raw wrapper can return no node data. Use mpv's
      // asynchronous screenshot command and software color conversion instead.
      await platform.setProperty('screenshot-sw', 'yes');
      await platform.setProperty('screenshot-jpeg-quality', '75');
      for (var attempt = 0; attempt < 20 && !_closed; attempt++) {
        await platform.command(['screenshot-to-file', file.path, 'video']);
        if (await file.exists()) {
          final length = await file.length();
          if (length > 0 && length <= 8 * 1024 * 1024) {
            final bytes = await file.readAsBytes();
            return bytes;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return null;
    } finally {
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        /* Cache may already be gone. */
      }
    }
  }

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
