import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';
import 'digest_auth.dart';
import 'video_config.dart';
import 'recording_event.dart';
import 'recording_picture.dart';

class RecorderException implements Exception {
  const RecorderException(this.message, {this.status, this.code});
  final String message;
  final int? status;
  final String? code;
  @override
  String toString() => message;
}

class Recording {
  const Recording({
    required this.start,
    required this.end,
    required this.playback,
    this.target = RecordingTarget.all,
    this.eventTypes = const [],
    this.selectedTime,
  });
  final DateTime start, end;
  final DateTime? selectedTime;
  DateTime get playbackTime => selectedTime ?? start;
  Recording at(DateTime time) => Recording(
    start: start,
    end: end,
    playback: playback,
    target: target,
    eventTypes: eventTypes,
    selectedTime: time,
  );
  final Uri playback;
  final RecordingTarget target;
  final List<RecordingEvent> eventTypes;
  List<RecordingEvent> get events => {
    ...eventTypes,
    if (target == RecordingTarget.human) RecordingEvent.human,
    if (target == RecordingTarget.vehicle) RecordingEvent.vehicle,
  }.toList();
  String get identity => '$start/$end/$playback';
}

class RecordingPage {
  const RecordingPage(
    this.records, {
    required this.nextPosition,
    required this.hasMore,
  });
  final List<Recording> records;
  final int nextPosition;
  final bool hasMore;
}

class RecorderCapabilities {
  const RecorderCapabilities(this.targets);
  final Set<RecordingTarget> targets;
}

class HikvisionClient {
  HikvisionClient({
    required this.config,
    required VideoCredentials credentials,
    HttpClient? http,
  }) : http = http ?? HttpClient(),
       auth = DigestAuth(credentials);
  final VideoConfig config;
  final HttpClient http;
  final DigestAuth auth;
  static const timeout = Duration(seconds: 20);
  bool _closed = false;
  String? _challenge;
  void close() {
    _closed = true;
    http.close(force: true);
  }

  Future<String> _request(
    String method,
    String path, {
    String body = '',
    bool json = false,
  }) async =>
      utf8.decode(await _requestBytes(method, path, body: body, json: json));

  Future<Uint8List> _requestBytes(
    String method,
    String path, {
    String body = '',
    bool json = false,
    bool picture = false,
  }) async {
    if (_closed) throw const RecorderException('Recording browser was closed.');
    final base = Uri.parse(config.recorderUrl);
    final uri = base.resolve(path);
    final payload = utf8.encode(body);
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        final request = await http.openUrl(method, uri).timeout(timeout);
        request.followRedirects = false;
        if (picture) {
          request.headers.set(HttpHeaders.acceptHeader, 'image/jpeg');
        }
        request.headers.contentType = json
            ? ContentType.json
            : ContentType('application', 'xml', charset: 'utf-8');
        // Embedded ISAPI servers may reject chunked XML/JSON uploads. Use the
        // UTF-8 byte length on every attempt, including Digest retries.
        request.contentLength = payload.length;
        final challenge = _challenge;
        if (challenge != null) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            auth.authorization(challenge, method, uri, body),
          );
        }
        if (payload.isNotEmpty) request.add(payload);
        final response = await request.close().timeout(timeout);
        final bytes = <int>[];
        await for (final chunk in response.timeout(timeout)) {
          if (bytes.length + chunk.length > (picture ? 4 : 2) * 1024 * 1024) {
            throw const RecorderException(
              'The recorder response is too large.',
            );
          }
          bytes.addAll(chunk);
        }
        if (response.statusCode == 401) {
          final challenges =
              response.headers[HttpHeaders.wwwAuthenticateHeader] ?? [];
          _challenge =
              challenges
                  .where((s) => s.toLowerCase().startsWith('digest '))
                  .firstOrNull ??
              challenges.firstOrNull;
          if (_challenge != null && attempt < 2) continue;
          throw const RecorderException(
            'Recorder login failed. Check the username, password and permissions.',
            status: 401,
          );
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw _rejection(
            response.statusCode,
            utf8.decode(bytes, allowMalformed: true),
            path,
          );
        }
        return Uint8List.fromList(bytes);
      }
    } on RecorderException {
      rethrow;
    } on TimeoutException {
      throw const RecorderException(
        'The recorder did not respond. Check its address and network route.',
      );
    } on HandshakeException {
      throw const RecorderException(
        'The recorder TLS certificate could not be verified.',
      );
    } on SocketException {
      throw const RecorderException(
        'Could not reach the recorder. Check its address and network route.',
      );
    } on FormatException {
      throw const RecorderException(
        'The recorder returned an unsupported response.',
      );
    }
    throw const RecorderException('Recorder login failed.');
  }

  static RecorderException _rejection(int status, String body, String path) {
    String? code;
    try {
      Object? value;
      if (body.trimLeft().startsWith('{')) {
        final root = jsonDecode(body);
        if (root is Map) {
          final details = root['ResponseStatus'] is Map
              ? root['ResponseStatus'] as Map
              : root;
          value = details['subStatusCode'];
        }
      } else {
        value = _text(_xml(body), 'subStatusCode');
      }
      // Return only a short protocol code, never raw errorMsg/statusString
      // fields, which some recorders fill with URLs or echoed request data.
      if (value is String &&
          RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,63}$').hasMatch(value)) {
        code = value;
      }
    } on FormatException {
      // Proxies and older firmware can return HTML or an empty error body.
    }
    final operation = path.contains('SearchByTargetType')
        ? 'Event search'
        : 'Recording search';
    return RecorderException(
      status == 403
          ? 'Recorder access denied. Enable recording playback permission${code == null ? '.' : ' ($code).'}'
          : '$operation rejected by the recorder ($status${code == null ? '' : ', $code'}).',
      status: status,
      code: code,
    );
  }

  Future<RecorderCapabilities> capabilities() async {
    try {
      final body = await _request(
        'GET',
        '/ISAPI/ContentMgmt/SearchByTargetType/capabilities?format=json',
        json: true,
      );
      return parseCapabilities(body);
    } on RecorderException catch (e) {
      if ([400, 403, 404, 405, 501].contains(e.status)) {
        return const RecorderCapabilities({RecordingTarget.all});
      }
      rethrow;
    } on FormatException {
      // Older DVRs may report an unsupported JSON endpoint with XML and HTTP
      // 200. Optional target filtering must not block ordinary video search.
      return const RecorderCapabilities({RecordingTarget.all});
    }
  }

  static RecorderCapabilities parseCapabilities(String raw) {
    final decoded = jsonDecode(raw);
    final targets = <RecordingTarget>{RecordingTarget.all};
    void walk(Object? node, {bool targetField = false}) {
      if (node is Map) {
        for (final entry in node.entries) {
          walk(
            entry.value,
            targetField:
                targetField ||
                entry.key.toString().toLowerCase().contains('targettype'),
          );
        }
      } else if (node is List) {
        for (final entry in node) {
          walk(entry, targetField: targetField);
        }
      } else if (targetField && node is String) {
        for (final token in node.split(RegExp(r'[,\s]+'))) {
          if (token.toLowerCase() == 'human') {
            targets.add(RecordingTarget.human);
          }
          if (token.toLowerCase() == 'vehicle') {
            targets.add(RecordingTarget.vehicle);
          }
        }
      }
    }

    walk(decoded);
    return RecorderCapabilities(targets);
  }

  Future<RecordingPage> search({
    required DateTime start,
    required DateTime end,
    RecordingTarget target = RecordingTarget.all,
    int position = 0,
    String? searchId,
  }) async {
    if (!end.isAfter(start) ||
        end.difference(start) > const Duration(days: 7) ||
        position < 0) {
      throw const RecorderException('Choose a time range of up to seven days.');
    }
    final id = searchId ?? const Uuid().v4();
    if (target == RecordingTarget.all) {
      final builder = XmlBuilder();
      builder.processing('xml', 'version="1.0" encoding="utf-8"');
      builder.element(
        'CMSearchDescription',
        nest: () {
          builder.element('searchID', nest: id);
          builder.element(
            'trackIDList',
            nest: () => builder.element('trackID', nest: config.recordingTrack),
          );
          builder.element(
            'timeSpanList',
            nest: () => builder.element(
              'timeSpan',
              nest: () {
                builder.element('startTime', nest: isoTime(start));
                builder.element('endTime', nest: isoTime(end));
              },
            ),
          );
          builder.element('maxResults', nest: 40);
          // The misspelling is part of Hikvision's published recording schema.
          builder.element('searchResultPostion', nest: position);
          builder.element(
            'metadataList',
            nest: () => builder.element(
              'metadataDescriptor',
              nest: '//recordType.meta.std-cgi.com',
            ),
          );
        },
      );
      final raw = await _request(
        'POST',
        '/ISAPI/ContentMgmt/search',
        body: builder.buildDocument().toXmlString(),
      );
      return parseRecordings(raw, config, position);
    }
    final raw = await _request(
      'POST',
      '/ISAPI/ContentMgmt/SearchByTargetType?format=json',
      json: true,
      body: jsonEncode({
        'SearchDescription': {
          'searchID': id,
          'searchResultPosition': position,
          'maxResults': 40,
          'SearchCondList': [
            {
              'channelID': config.channel,
              'targetTypes': [target.name],
              'searchTimeList': [
                {
                  'searchTime': {
                    'startTime': isoTime(start),
                    'endTime': isoTime(end),
                  },
                },
              ],
            },
          ],
        },
      }),
    );
    return parseTargetRecordings(raw, config, position, target);
  }

  static String isoTime(DateTime time) =>
      '${time.toUtc().toIso8601String().split('.').first}Z';

  Future<bool> supportsPictures() async {
    try {
      final document = _xml(
        await _request('GET', '/ISAPI/ContentMgmt/capabilities'),
      );
      return document.descendants.whereType<XmlElement>().any(
        (e) =>
            e.name.local == 'pictureSearchType' &&
            (e.innerText.trim().isNotEmpty ||
                (e.getAttribute('opt')?.isNotEmpty ?? false)),
      );
    } on RecorderException catch (e) {
      if ([400, 403, 404, 405, 501].contains(e.status)) return false;
      rethrow;
    } on FormatException {
      return false;
    }
  }

  /// Picture track xx3 returns capture times, rather than video file boundaries.
  Future<List<RecordingPicture>> pictures(DateTime start, DateTime end) async {
    final builder = XmlBuilder();
    builder.element(
      'CMSearchDescription',
      nest: () {
        builder.element('searchID', nest: const Uuid().v4());
        builder.element(
          'trackIDList',
          nest: () =>
              builder.element('trackID', nest: config.channel * 100 + 3),
        );
        builder.element(
          'timeSpanList',
          nest: () => builder.element(
            'timeSpan',
            nest: () {
              builder.element('startTime', nest: isoTime(start));
              builder.element('endTime', nest: isoTime(end));
            },
          ),
        );
        builder.element('maxResults', nest: 40);
        builder.element('searchResultPostion', nest: 0);
        builder.element(
          'metadataList',
          nest: () => builder.element(
            'metadataDescriptor',
            nest: '//recordType.meta.std-cgi.com',
          ),
        );
      },
    );
    return parsePictures(
      await _request(
        'POST',
        '/ISAPI/ContentMgmt/search',
        body: builder.buildDocument().toXmlString(),
      ),
      config,
    );
  }

  static Uri pictureUri(VideoConfig config, String value) {
    final source = Uri.parse(value);
    final track = config.channel * 100 + 3;
    var path = source.path;
    if (path.startsWith('/Streaming/')) path = '/ISAPI$path';
    if (!RegExp('^/ISAPI/Streaming/tracks/$track/?\$').hasMatch(path) ||
        (source.hasScheme &&
            !['http', 'https', 'rtsp', 'rtsps'].contains(source.scheme))) {
      throw const FormatException('Unsupported stored picture address.');
    }
    // Keep Digest authentication and private routing on the configured recorder.
    final base = Uri.parse(config.recorderUrl);
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: path,
      query: source.hasQuery ? source.query : null,
    );
  }

  static List<RecordingPicture> parsePictures(String raw, VideoConfig config) {
    final document = _xml(raw);
    final status = _text(document, 'responseStatusStrg')?.toUpperCase();
    if (status == 'NO MATCHES') return [];
    if (!['OK', 'MORE'].contains(status) ||
        _text(document, 'responseStatus') == 'false') {
      throw const RecorderException(
        'The recorder could not search stored pictures.',
      );
    }
    final pictures = <RecordingPicture>[];
    for (final item in document.descendants.whereType<XmlElement>().where(
      (e) => ['searchMatchItem', 'matchElement'].contains(e.name.local),
    )) {
      if (int.tryParse(_text(item, 'trackID') ?? '') !=
          config.channel * 100 + 3) {
        continue;
      }
      final time = DateTime.tryParse(_text(item, 'startTime') ?? '');
      final uri = _text(item, 'playbackURI');
      if (time == null || uri == null) continue;
      try {
        pictures.add(
          RecordingPicture(
            time,
            pictureUri(config, uri),
            item.descendants
                .whereType<XmlElement>()
                .where((e) => e.name.local == 'metadataDescriptor')
                .map((e) => RecordingEvent.fromDescriptor(e.innerText))
                .whereType<RecordingEvent>()
                .toSet()
                .toList(),
          ),
        );
      } on FormatException {
        // An unrecognized picture URL must never receive recorder credentials.
      }
    }
    pictures.sort((a, b) => a.time.compareTo(b.time));
    return pictures;
  }

  Future<Uint8List> picture(RecordingPicture picture) async {
    final uri = pictureUri(config, picture.uri.toString());
    final bytes = await _requestBytes(
      'GET',
      Uri(path: uri.path, query: uri.hasQuery ? uri.query : null).toString(),
      picture: true,
    );
    if (bytes.length < 4 ||
        bytes[0] != 0xff ||
        bytes[1] != 0xd8 ||
        bytes[bytes.length - 2] != 0xff ||
        bytes.last != 0xd9) {
      throw const RecorderException(
        'The recorder did not return a JPEG event picture.',
      );
    }
    return bytes;
  }

  static XmlDocument _xml(String raw) {
    if (raw.toUpperCase().contains('<!DOCTYPE')) {
      throw const FormatException('Unsupported XML document.');
    }
    return XmlDocument.parse(raw);
  }

  static String? _text(XmlNode node, String name) => node.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == name)
      .firstOrNull
      ?.innerText
      .trim();
  static RecordingPage parseRecordings(
    String raw,
    VideoConfig config,
    int position,
  ) {
    final document = _xml(raw);
    final status = _text(document, 'responseStatusStrg')?.toUpperCase();
    if (status == 'NO MATCHES') {
      return RecordingPage(const [], nextPosition: position, hasMore: false);
    }
    if (!['OK', 'MORE'].contains(status) ||
        _text(document, 'responseStatus') == 'false') {
      throw const RecorderException(
        'The recorder could not search recordings.',
      );
    }
    final records = <Recording>[];
    final matches = document.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'searchMatchItem')
        .toList();
    for (final item in matches) {
      final track = int.tryParse(_text(item, 'trackID') ?? '');
      if (track != null && track != config.recordingTrack) continue;
      final start = DateTime.tryParse(_text(item, 'startTime') ?? ''),
          end = DateTime.tryParse(_text(item, 'endTime') ?? '');
      final uri = _text(item, 'playbackURI');
      if (start == null || end == null || !end.isAfter(start) || uri == null) {
        continue;
      }
      records.add(
        Recording(
          start: start,
          end: end,
          playback: config.playbackUri(uri),
          eventTypes: item.descendants
              .whereType<XmlElement>()
              .where((e) => e.name.local == 'metadataDescriptor')
              .map((e) => RecordingEvent.fromDescriptor(e.innerText))
              .whereType<RecordingEvent>()
              .toSet()
              .toList(),
        ),
      );
    }
    return RecordingPage(
      records,
      nextPosition: position + matches.length,
      hasMore: status == 'MORE' && matches.isNotEmpty,
    );
  }

  static RecordingPage parseTargetRecordings(
    String raw,
    VideoConfig config,
    int position,
    RecordingTarget target,
  ) {
    final root = jsonDecode(raw) as Map<String, dynamic>;
    final result = root['SearchResult'] as Map<String, dynamic>?;
    if (result == null) {
      throw const RecorderException(
        'Target search is unsupported by this recorder firmware.',
      );
    }
    final matches = result['matchList'] as List? ?? [];
    final records = <Recording>[];
    for (final entry in matches.whereType<Map>()) {
      if (entry['channelID'] != null &&
          '${entry['channelID']}' != '${config.channel}') {
        continue;
      }
      final types = (entry['targetTypes'] as List? ?? [])
          .map((value) => value.toString().toLowerCase())
          .toSet();
      if (types.isNotEmpty && !types.contains(target.name)) {
        continue;
      }
      for (final record
          in (entry['RecordInfoList'] as List? ?? []).whereType<Map>()) {
        final span = record['RecordTime'] as Map?;
        final start = DateTime.tryParse('${span?['startTime']}'),
            end = DateTime.tryParse('${span?['endTime']}');
        if (start == null || end == null || !end.isAfter(start)) continue;
        final playback = record['playbackURI'] as String?;
        records.add(
          Recording(
            start: start,
            end: end,
            target: target,
            playback: playback == null
                ? boundedPlayback(config, start, end)
                : config.playbackUri(playback),
          ),
        );
      }
    }
    final count = (result['numOfMatches'] as num?)?.toInt() ?? matches.length;
    final total = (result['totalMatches'] as num?)?.toInt();
    final more =
        result['responseStatusStrg'] == 'MORE' ||
        (total != null && position + count < total);
    return RecordingPage(
      records,
      nextPosition: position + count,
      hasMore: more && count > 0,
    );
  }

  static Uri boundedPlayback(VideoConfig config, DateTime start, DateTime end) {
    String stamp(DateTime t) =>
        isoTime(t).replaceAll('-', '').replaceAll(':', '');
    return config.liveUri.replace(
      path: '/Streaming/tracks/${config.recordingTrack}',
      queryParameters: {'starttime': stamp(start), 'endtime': stamp(end)},
    );
  }

  /// Ordinary recording playback, starting at the selected timestamp. Hikvision
  /// documents endtime as optional; omit file name/size and event end limits so
  /// playback can continue through subsequent footage on this track.
  static Uri continuousPlayback(VideoConfig config, DateTime start) =>
      config.liveUri.replace(
        path: '/Streaming/tracks/${config.recordingTrack}',
        queryParameters: {
          'starttime': isoTime(start).replaceAll('-', '').replaceAll(':', ''),
        },
      );
}
