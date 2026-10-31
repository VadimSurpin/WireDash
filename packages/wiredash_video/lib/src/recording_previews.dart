import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:wiredash_plugin_api/wiredash_plugin_api.dart';
import 'hikvision_client.dart';
import 'video_config.dart';
import 'video_session.dart';

class RecordingPreviewTicket {
  RecordingPreviewTicket(this.image, this._release);
  final Future<Uint8List?> image;
  final void Function() _release;
  bool _released = false;
  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}

class _Capture {
  _Capture(this.record);
  final Recording record;
  final result = Completer<Uint8List?>();
  final cancellation = Completer<Uint8List?>();
  int users = 1;
  bool cancelled = false;
  VideoSession? session;
  PluginStreamLease? lease;
  Future<void>? _closing;
  Future<void> close() => _closing ??= () async {
    final route = lease, player = session;
    lease = null;
    session = null;
    try {
      await route?.close();
    } finally {
      await player?.close();
    }
  }();
  Future<void> cancel() async {
    cancelled = true;
    if (!cancellation.isCompleted) cancellation.complete(null);
    if (!result.isCompleted) result.complete(null);
    try {
      await close();
    } catch (_) {
      /* Socket/player already interrupted. */
    }
  }
}

/// Short, muted connections to saved clips, serialized to avoid exhausting DVR
/// sessions. Photos live only in this browser's bounded memory cache.
class RecordingPreviews {
  RecordingPreviews({
    required this.host,
    required this.config,
    this.sessionFactory = NativeVideoSession.preview,
    this.maxEntries = 48,
    this.maxBytes = 8 * 1024 * 1024,
  });
  final PluginHost host;
  final VideoConfig config;
  final VideoSessionFactory sessionFactory;
  final int maxEntries, maxBytes;
  final _cache = <String, Uint8List>{};
  final _jobs = <String, _Capture>{};
  Future<void> _tail = Future.value();
  Future<VideoCredentials>? _credentials;
  bool _paused = false, _disposed = false;
  int _bytes = 0;

  RecordingPreviewTicket request(Recording record) {
    final key = record.identity;
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return RecordingPreviewTicket(Future.value(cached), () {});
    }
    if (_disposed || _paused) {
      return RecordingPreviewTicket(Future.value(null), () {});
    }
    var job = _jobs[key];
    if (job != null) {
      job.users++;
    } else {
      job = _Capture(record);
      _jobs[key] = job;
      final task = job;
      _tail = _tail.then((_) => _capture(key, task));
    }
    final task = job;
    return RecordingPreviewTicket(task.result.future, () {
      if (--task.users == 0 && identical(_jobs[key], task)) {
        _jobs.remove(key);
        unawaited(task.cancel());
      }
    });
  }

  Future<void> _capture(String key, _Capture task) async {
    Uint8List? image;
    try {
      if (task.cancelled || _paused || _disposed) return;
      image = await Future.any([_produce(task), task.cancellation.future]);
      if (image != null && (image.isEmpty || image.length > maxBytes)) {
        image = null;
      }
      if (!task.cancelled &&
          image != null &&
          image.isNotEmpty &&
          image.length <= maxBytes) {
        _cache[key] = image;
        _bytes += image.length;
        while (_cache.length > maxEntries || _bytes > maxBytes) {
          _bytes -= _cache.remove(_cache.keys.first)!.length;
        }
      }
    } catch (_) {
      _credentials = null;
      // A failed historical frame remains a retryable placeholder. It must
      // never substitute a live snapshot or hide the recording itself.
    } finally {
      try {
        await task.close();
      } catch (_) {
        /* Already interrupted. */
      }
      if (!task.result.isCompleted) task.result.complete(image);
      if (identical(_jobs[key], task)) _jobs.remove(key);
    }
  }

  Future<Uint8List?> _produce(_Capture task) async {
    final credentials = await (_credentials ??= host
        .readSecret(config.credentialId)
        .then(VideoCredentials.decode));
    if (task.cancelled) return null;
    final network = config.useHomeNetwork
        ? host.network
        : const DirectPluginNetwork();
    final route = await network.openStream(
      credentials.authenticate(task.record.playback),
    );
    if (task.cancelled) {
      await route.close();
      return null;
    }
    task.lease = route;
    final player = task.session = sessionFactory();
    // VideoController initializes after a frame even when its texture is not
    // attached to a visible Video widget.
    WidgetsBinding.instance.scheduleFrame();
    await player.open(route.uri, muted: true);
    return task.cancelled ? null : player.captureFrame();
  }

  Future<void> setPaused(bool paused) async {
    _paused = paused;
    if (!paused) return;
    final jobs = _jobs.values.toList();
    _jobs.clear();
    await Future.wait(jobs.map((job) => job.cancel()));
  }

  void dispose() {
    _disposed = true;
    unawaited(setPaused(true));
    _cache.clear();
    _bytes = 0;
  }
}
