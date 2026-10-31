import 'dart:async';
import 'dart:typed_data';
import 'package:wiredash_plugin_api/wiredash_plugin_api.dart';
import 'hikvision_client.dart';
import 'video_config.dart';
import 'video_session.dart';
import 'recording_cache.dart';
import 'recording_photos.dart';
import 'recording_event.dart';

class RecordingPreviewData {
  const RecordingPreviewData(
    this.bytes,
    this.time, {
    this.eventPhoto = false,
    this.events = const [],
  });
  final Uint8List bytes;
  final DateTime time;
  final bool eventPhoto;
  final List<RecordingEvent> events;
}

class RecordingPreviewTicket {
  RecordingPreviewTicket(this.preview, this._release);
  final Future<RecordingPreviewData?> preview;
  Future<Uint8List?> get image => preview.then((value) => value?.bytes);
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
  final result = Completer<RecordingPreviewData?>();
  final cancellation = Completer<RecordingPreviewData?>();
  int users = 1;
  bool cancelled = false;
  void Function()? interrupt;
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
    interrupt?.call();
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
/// sessions. Stored event photos and fallback frames use a bounded private cache.
class RecordingPreviews {
  RecordingPreviews({
    required this.host,
    required this.config,
    this.sessionFactory = NativeVideoSession.preview,
    this.maxEntries = 48,
    this.maxBytes = 8 * 1024 * 1024,
    this.cache,
    this.photos,
  });
  final PluginHost host;
  final VideoConfig config;
  final VideoSessionFactory sessionFactory;
  final int maxEntries, maxBytes;
  final RecordingCache? cache;
  final RecordingPhotos? photos;
  final _cache = <String, RecordingPreviewData>{};
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
    RecordingPreviewData? image;
    try {
      if (task.cancelled || _paused || _disposed) return;
      task.interrupt = photos?.interrupt;
      image = await Future.any([_produce(task), task.cancellation.future]);
      if (image != null &&
          (image.bytes.isEmpty || image.bytes.length > maxBytes)) {
        image = null;
      }
      if (!task.cancelled &&
          image != null &&
          image.bytes.isNotEmpty &&
          image.bytes.length <= maxBytes) {
        _cache[key] = image;
        _bytes += image.bytes.length;
        while (_cache.length > maxEntries || _bytes > maxBytes) {
          _bytes -= _cache.remove(_cache.keys.first)!.bytes.length;
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

  Future<RecordingPreviewData?> _produce(_Capture task) async {
    try {
      final photo = await photos?.find(task.record);
      if (task.cancelled) return null;
      if (photo != null) {
        final bytes = await photos!.bytes(photo);
        if (task.cancelled) return null;
        return RecordingPreviewData(
          Uint8List.fromList(bytes),
          photo.time,
          eventPhoto: true,
          events: photo.events,
        );
      }
    } catch (_) {
      // Stored captures are optional; never hide playable video on a recorder
      // without captures or on firmware that rejects picture search.
    }
    if (task.cancelled) return null;
    final saved = await cache?.readImage(task.record);
    if (task.cancelled) return null;
    if (saved != null) return RecordingPreviewData(saved, task.record.start);
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
    await player.open(route.uri, muted: true);
    if (task.cancelled) return null;
    final image = await player.captureFrame();
    if (!task.cancelled &&
        image != null &&
        image.isNotEmpty &&
        image.length <= maxBytes) {
      unawaited(cache?.writeImage(task.record, image) ?? Future<void>.value());
    }
    return image == null
        ? null
        : RecordingPreviewData(image, task.record.start);
  }

  void refresh() {
    final pending = _jobs.values.toList();
    _jobs.clear();
    for (final job in pending) {
      unawaited(job.cancel());
    }
    _cache.clear();
    _bytes = 0;
    photos?.refresh();
  }

  Future<void> setPaused(bool paused) async {
    _paused = paused;
    if (!paused) return;
    photos?.interrupt();
    final jobs = _jobs.values.toList();
    _jobs.clear();
    await Future.wait(jobs.map((job) => job.cancel()));
  }

  void dispose() {
    _disposed = true;
    photos?.dispose();
    unawaited(setPaused(true));
    _cache.clear();
    _bytes = 0;
  }
}
