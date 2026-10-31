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

  /// Returns an encoded still for preview sessions; ordinary playback may
  /// return null rather than interrupting its visible output.
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
    if (!preview) controller = VideoController(player);
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
  Directory? _previewDirectory;
  Uint8List? _previewFrame;
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
  Widget buildView() => preview
      ? const SizedBox.shrink()
      : Video(
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
      if (preview) {
        final cache = await getTemporaryDirectory();
        final directory = await cache.createTemp('wiredash-preview-');
        if (_closed) {
          await directory.delete(recursive: true);
          throw StateError('Preview closed.');
        }
        _previewDirectory = directory;
        await platform.setProperty('vo-image-outdir', directory.path);
        await platform.setProperty('vo-image-format', 'jpg');
        await platform.setProperty('vo-image-jpeg-quality', '75');
        await platform.setProperty('vo', 'image');
        await platform.setProperty('vid', 'auto');
        await platform.setProperty('aid', 'no');
        await platform.setProperty('hwdec', 'no');
        await platform.setProperty('frames', '1');
        await platform.setProperty('vf', 'scale=320:-2');
      }
    }
    await player.setVolume(muted ? 0 : 100);
    await player.open(
      Media(uri.toString(), extras: const {'title': 'WireDash video'}),
    );
    // Opening a demuxer alone does not prove that the stream can be decoded.
    // Bound the loading state and let the pane release a failed connection.
    if (preview) {
      for (var attempt = 0; attempt < 200 && !_closed; attempt++) {
        _previewFrame = await _readPreview();
        if (_previewFrame != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (_previewFrame == null) {
        throw TimeoutException('Preview frame unavailable.');
      }
    } else {
      await controller.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 20),
      );
    }
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
  Future<Uint8List?> captureFrame() async => _closed ? null : _previewFrame;

  Future<Uint8List?> _readPreview() async {
    final directory = _previewDirectory;
    if (directory == null || _closed) return null;
    try {
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is File && entry.path.endsWith('.jpg')) {
          final length = await entry.length();
          if (length >= 4 && length <= 8 * 1024 * 1024) {
            final bytes = await entry.readAsBytes();
            // The output file can appear before its last packet is written.
            if (bytes[0] != 0xff ||
                bytes[1] != 0xd8 ||
                bytes[bytes.length - 2] != 0xff ||
                bytes.last != 0xd9) {
              continue;
            }
            return bytes;
          }
        }
      }
      return null;
    } on FileSystemException {
      if (_closed) return null;
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    try {
      await player.dispose();
    } finally {
      final directory = _previewDirectory;
      _previewDirectory = null;
      _previewFrame = null;
      if (directory != null) {
        try {
          await directory.delete(recursive: true);
        } on FileSystemException {
          /* Already removed. */
        }
      }
      super.dispose();
    }
  }
}
