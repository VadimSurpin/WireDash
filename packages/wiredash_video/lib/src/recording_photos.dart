import 'dart:async';
import 'package:wiredash_plugin_api/wiredash_plugin_api.dart';
import 'hikvision_client.dart';
import 'recording_cache.dart';
import 'recording_event.dart';
import 'recording_picture.dart';
import 'video_config.dart';

/// Optional stored event captures. A video boundary is never a detection time.
class RecordingPhotos {
  RecordingPhotos({
    required this.host,
    required this.config,
    required this.cache,
    this.rangeStart,
    this.rangeEnd,
  });
  final PluginHost host;
  final VideoConfig config;
  final RecordingCache cache;
  final DateTime Function()? rangeStart, rangeEnd;
  HikvisionClient? _client;
  Future<HikvisionClient>? _connecting;
  Future<bool>? _supported;
  bool _closed = false, _forceCapabilities = false;
  DateTime? _refreshAfter;
  int _connectionGeneration = 0;

  Future<HikvisionClient> _connect() {
    final generation = _connectionGeneration;
    return _connecting ??= () async {
      final credentials = VideoCredentials.decode(
        await host.readSecret(config.credentialId),
      );
      if (_closed || generation != _connectionGeneration) {
        throw StateError('Preview browser closed.');
      }
      final network = config.useHomeNetwork
          ? host.network
          : const DirectPluginNetwork();
      return _client = HikvisionClient(
        config: config,
        credentials: credentials,
        http: network.createHttpClient(),
      );
    }();
  }

  Future<bool> _supportsPictures() async {
    final generation = _connectionGeneration;
    if (!_forceCapabilities) {
      final saved = await cache.readJson('picture-capabilities');
      if (saved?['supported'] is bool) return saved!['supported'] as bool;
    }
    if (_closed || generation != _connectionGeneration) {
      throw StateError('Preview interrupted.');
    }
    final supported = await (await _connect()).supportsPictures();
    if (_closed || generation != _connectionGeneration) {
      throw StateError('Preview interrupted.');
    }
    _forceCapabilities = false;
    unawaited(
      cache.writeJson('picture-capabilities', {'supported': supported}),
    );
    return supported;
  }

  void refresh() {
    interrupt();
    _refreshAfter = DateTime.now();
    _forceCapabilities = true;
    _supported = null;
  }

  Future<RecordingPicture?> find(Recording record) async {
    final generation = _connectionGeneration;
    bool active() => !_closed && generation == _connectionGeneration;
    final lower = rangeStart?.call(), upper = rangeEnd?.call();
    final start = lower != null && lower.isAfter(record.start)
        ? lower
        : record.start;
    final end = upper != null && upper.isBefore(record.end)
        ? upper
        : record.end;
    if (!end.isAfter(start)) return null;
    final key =
        'event-picture/${start.toUtc().toIso8601String()}/${end.toUtc().toIso8601String()}/${record.target.name}';
    final saved = await cache.readJson(key);
    if (!active()) return null;
    if (saved?['uri'] is String && saved?['time'] is String) {
      try {
        return RecordingPicture(
          DateTime.parse(saved!['time'] as String),
          HikvisionClient.pictureUri(config, saved['uri'] as String),
          [
            for (final name in saved['events'] as List? ?? [])
              ...RecordingEvent.values.where((e) => e.name == name),
          ],
        );
      } on FormatException {
        // Obsolete metadata is a cache miss.
      }
    }
    final checked = DateTime.tryParse('${saved?['checkedAt']}');
    final historical = end.isBefore(
      DateTime.now().subtract(const Duration(hours: 1)),
    );
    if (checked != null &&
        !DateTime.now().difference(checked).isNegative &&
        (_refreshAfter == null || !checked.isBefore(_refreshAfter!)) &&
        DateTime.now().difference(checked) <
            (historical
                ? const Duration(days: 1)
                : const Duration(minutes: 1))) {
      return null;
    }
    if (!await (_supported ??= _supportsPictures()) || !active()) return null;
    final to = end.difference(start) > const Duration(days: 7)
        ? start.add(const Duration(days: 7))
        : end;
    final pictures = await (await _connect()).pictures(start, to);
    if (!active()) return null;
    final candidates = pictures
        .where(
          (p) =>
              !p.time.isBefore(start) &&
              p.time.isBefore(end) &&
              p.events.any(
                (e) =>
                    e != RecordingEvent.scheduled && e != RecordingEvent.manual,
              ),
        )
        .toList();
    final wanted = switch (record.target) {
      RecordingTarget.human => RecordingEvent.human,
      RecordingTarget.vehicle => RecordingEvent.vehicle,
      RecordingTarget.all => null,
    };
    // Prefer the recorder's explicit classification. A generic motion capture
    // is shown as an event photo, never labelled as a verified target crop.
    final picture =
        candidates
            .where(
              (p) => wanted != null
                  ? p.events.contains(wanted)
                  : p.events.contains(RecordingEvent.human) ||
                        p.events.contains(RecordingEvent.vehicle),
            )
            .firstOrNull ??
        candidates
            .where(
              (p) =>
                  wanted == null ||
                  (!p.events.contains(RecordingEvent.human) &&
                      !p.events.contains(RecordingEvent.vehicle)),
            )
            .firstOrNull;
    unawaited(
      cache.writeJson(key, {
        'checkedAt': DateTime.now().toUtc().toIso8601String(),
        if (picture != null) ...{
          'time': picture.time.toUtc().toIso8601String(),
          'uri': picture.uri.toString(),
          'events': picture.events.map((e) => e.name).toList(),
        },
      }),
    );
    return picture;
  }

  Future<List<int>> bytes(RecordingPicture picture) async {
    final generation = _connectionGeneration;
    final saved = await cache.readPicture(picture);
    if (saved != null) return saved;
    if (_closed || generation != _connectionGeneration) {
      throw StateError('Preview browser closed.');
    }
    final image = await (await _connect()).picture(picture);
    if (!_closed) unawaited(cache.writePicture(picture, image));
    return image;
  }

  void interrupt() {
    _connectionGeneration++;
    _client?.close();
    _client = null;
    _connecting = null;
    _supported = null;
  }

  void dispose() {
    _closed = true;
    _client?.close();
  }
}
