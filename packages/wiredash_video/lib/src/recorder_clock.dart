/// Search/playback time semantics advertised by the recorder, never the phone's
/// timezone. Older DVRs can append Z to values that still represent local time.
class RecorderClock {
  const RecorderClock({
    this.standard = false,
    this.local = false,
    this.zone = '',
    this.offsetMinutes = 0,
    this.playbackLocal,
    this.forcePlaybackLocal,
  });
  final bool standard, local;
  final bool? playbackLocal, forcePlaybackLocal;
  bool get localPlayback => playbackLocal ?? local;
  final String zone;
  final int offsetMinutes;
  Map<String, dynamic> toJson() => {
    'standard': standard,
    'local': local,
    'zone': zone,
    'offsetMinutes': offsetMinutes,
    'playbackLocal': playbackLocal,
    'forcePlaybackLocal': forcePlaybackLocal,
  };
  factory RecorderClock.fromJson(Map<String, dynamic> value) => RecorderClock(
    standard: value['standard'] == true,
    local: value['local'] == true,
    zone: value['zone'] as String? ?? '',
    offsetMinutes: (value['offsetMinutes'] as num?)?.toInt() ?? 0,
    playbackLocal: value['playbackLocal'] as bool?,
    forcePlaybackLocal: value['forcePlaybackLocal'] as bool?,
  );

  static Duration? explicitOffset(String value) {
    final match = RegExp(r'([+-])(\d{2}):?(\d{2})$').firstMatch(value);
    if (match == null) return null;
    return Duration(
      minutes:
          (int.parse(match[2]!) * 60 + int.parse(match[3]!)) *
          (match[1] == '-' ? -1 : 1),
    );
  }

  Duration _duration(String value) {
    final parts = value.split(':').map(int.parse).toList();
    return Duration(
      hours: parts[0],
      minutes: parts.length > 1 ? parts[1] : 0,
      seconds: parts.length > 2 ? parts[2] : 0,
    );
  }

  Duration get baseOffset {
    final match = RegExp(
      r'^[A-Za-z]+([+-]?)(\d{1,2}(?::\d{2}){0,2})',
    ).firstMatch(zone);
    if (match == null) return Duration(minutes: offsetMinutes);
    // POSIX signs are the opposite of ISO 8601 signs.
    return _duration(match[2]!) * (match[1] == '-' ? 1 : -1);
  }

  DateTime _transition(String rule, int year) {
    final parts = rule.split('/');
    final date = parts[0].substring(1).split('.').map(int.parse).toList();
    final month = date[0], week = date[1], weekday = date[2];
    final first = DateTime.utc(year, month, 1);
    var day = 1 + (weekday - first.weekday % 7 + 7) % 7 + 7 * (week - 1);
    final last = DateTime.utc(year, month + 1, 0).day;
    if (day > last) day -= 7;
    return DateTime.utc(
      year,
      month,
      day,
    ).add(_duration(parts.length > 1 ? parts[1] : '2'));
  }

  Duration offsetAt(DateTime utc) {
    final base = baseOffset;
    final dst = RegExp(
      r'DST(\d{1,2}(?::\d{2}){0,2}),?(M\d{1,2}\.\d\.\d(?:/\d{1,2}(?::\d{2}){0,2})?),(M\d{1,2}\.\d\.\d(?:/\d{1,2}(?::\d{2}){0,2})?)',
    ).firstMatch(zone);
    if (dst == null) return base;
    try {
      final shift = _duration(dst[1]!);
      final year = utc.toUtc().add(base).year;
      final from = _transition(dst[2]!, year).subtract(base);
      final to = _transition(dst[3]!, year).subtract(base + shift);
      final summer = from.isBefore(to)
          ? !utc.isBefore(from) && utc.isBefore(to)
          : !utc.isBefore(from) || utc.isBefore(to);
      return summer ? base + shift : base;
    } on ArgumentError {
      return base;
    }
  }

  DateTime? parse(String value) {
    try {
      if (explicitOffset(value) != null) return DateTime.parse(value).toUtc();
      final bare = value.replaceFirst(RegExp(r'[zZ]$'), '');
      final fields = DateTime.parse('${bare}Z').toUtc();
      if (!local) return fields;
      final guess = fields.subtract(baseOffset);
      return fields.subtract(offsetAt(guess));
    } on FormatException {
      return null;
    }
  }

  String format(DateTime time) {
    final utc = time.toUtc();
    final fields = local ? utc.add(offsetAt(utc)) : utc;
    final value = fields.toIso8601String().split('.').first;
    return local ? value : '${value}Z';
  }

  /// HTTP's STD capability does not establish RTSP's default time type. Only
  /// an explicit flag in the recorder-returned RTSP URI requests STD playback.
  RecorderClock playbackClock(Uri? template) {
    if (forcePlaybackLocal != null) {
      return RecorderClock(
        local: forcePlaybackLocal!,
        zone: zone,
        offsetMinutes: offsetMinutes,
      );
    }
    return template?.queryParameters['timeType']?.toUpperCase() == 'STD'
        ? const RecorderClock(standard: true)
        : RecorderClock(
            local: localPlayback,
            zone: zone,
            offsetMinutes: offsetMinutes,
          );
  }

  Map<String, String> playbackQuery(Map<String, String> original) {
    final query = Map<String, String>.from(original);
    if (forcePlaybackLocal == true) {
      query.removeWhere((key, _) => key.toLowerCase() == 'timetype');
    }
    if (forcePlaybackLocal == false && standard) query['timeType'] = 'STD';
    return query;
  }

  DateTime? parsePlayback(String value, {Uri? template}) =>
      playbackClock(template).parse(value);

  String rtsp(DateTime time, {Uri? template}) {
    final basis = playbackClock(template);
    final value = basis.format(time).replaceAll('-', '').replaceAll(':', '');
    return basis.local &&
            (template?.queryParameters['starttime']?.toUpperCase().endsWith(
                  'Z',
                ) ??
                false)
        ? '${value}Z'
        : value;
  }

  String path(String path) {
    if (!standard) return path;
    final uri = Uri.parse(path);
    return uri
        .replace(queryParameters: {...uri.queryParameters, 'timeType': 'STD'})
        .toString();
  }
}
