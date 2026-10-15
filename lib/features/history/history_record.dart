import 'dart:convert';

/// History (docs/design/history-2.7.md): the recorder on the hub keeps one
/// retained **day record** per reading per day on
/// `zigdash/history/<ieee>/<attr>/<YYYY-MM-DD>`, holding that day's
/// 15-minute slots as `[slot, avg, min, max]`.

/// Minutes per slot, and slots per day.
const historySlotMinutes = 15;
const historySlotsPerDay = 24 * 60 ~/ historySlotMinutes;

/// How many days the recorder keeps.
const historyKeepDays = 30;

/// The three views of a history sheet. [day] is free; the others are Pro.
enum HistoryRange {
  day(Duration(hours: 24), 2),
  week(Duration(days: 7), 8),
  month(Duration(days: 30), 30);

  const HistoryRange(this.span, this.days);

  /// How far back the view reaches from now.
  final Duration span;

  /// How many day records it reads (today and the days before).
  final int days;

  bool get isPro => this != HistoryRange.day;
}

/// One 15-minute slot of a reading.
class HistoryPoint {
  const HistoryPoint(this.at, this.avg, this.min, this.max);

  /// The slot's start, in the Home's local wall time.
  final DateTime at;
  final double avg;
  final double min;
  final double max;

  @override
  bool operator ==(Object other) =>
      other is HistoryPoint &&
      other.at == at &&
      other.avg == avg &&
      other.min == min &&
      other.max == max;

  @override
  int get hashCode => Object.hash(at, avg, min, max);

  @override
  String toString() => 'HistoryPoint($at, $avg, $min..$max)';
}

/// The topic of the day record of reading ([ieee], [attr]) on [day].
String historyRecordTopic(String ieee, String attr, DateTime day) =>
    'zigdash/history/$ieee/$attr/${historyDate(day)}';

/// `YYYY-MM-DD` of [day] as written by the recorder.
String historyDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// The recorder's `attr` for a value path: anything but letters, digits,
/// `_` and `-` becomes `_`.
String historyAttr(String path) =>
    path.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

/// Parses the day record of [day]; null for an empty (cleared) or broken
/// payload. Slots outside the day and non-numbers are skipped.
List<HistoryPoint>? parseDayRecord(String payload, DateTime day) {
  if (payload.trim().isEmpty) return null;
  final Object? j;
  try {
    j = jsonDecode(payload);
  } on FormatException {
    return null;
  }
  if (j is! Map || j['b'] is! List) return null;
  final start = DateTime(day.year, day.month, day.day);
  final out = <HistoryPoint>[];
  for (final b in j['b'] as List) {
    if (b is! List || b.length < 4) continue;
    final [slot, avg, min, max, ...] = b;
    if (slot is! num || avg is! num || min is! num || max is! num) continue;
    final s = slot.toInt();
    if (s < 0 || s >= historySlotsPerDay) continue;
    out.add(
      HistoryPoint(
        start.add(Duration(minutes: s * historySlotMinutes)),
        avg.toDouble(),
        min.toDouble(),
        max.toDouble(),
      ),
    );
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

/// The days a [range] reads, oldest first, ending today ([now]'s date).
List<DateTime> historyDays(HistoryRange range, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return [
    for (var i = range.days - 1; i >= 0; i--)
      DateTime(today.year, today.month, today.day - i),
  ];
}

/// The points of [range] ending at [now], from the parsed day records in
/// [days] (keyed by date; missing days are gaps). For 7 and 30 days the
/// slots are folded into hours and days respectively, so a graph draws a
/// few hundred points, not thousands.
List<HistoryPoint> historySeries(
  HistoryRange range,
  DateTime now,
  Map<String, List<HistoryPoint>> days,
) {
  final from = now.subtract(range.span);
  final points = [
    for (final d in historyDays(range, now)) ...?days[historyDate(d)],
  ].where((p) => !p.at.isBefore(from) && !p.at.isAfter(now)).toList();
  return switch (range) {
    HistoryRange.day => points,
    HistoryRange.week => _fold(
      points,
      (t) => DateTime(t.year, t.month, t.day, t.hour),
    ),
    HistoryRange.month => _fold(
      points,
      (t) => DateTime(t.year, t.month, t.day),
    ),
  };
}

List<HistoryPoint> _fold(
  List<HistoryPoint> points,
  DateTime Function(DateTime) bucket,
) {
  final groups = <DateTime, List<HistoryPoint>>{};
  for (final p in points) {
    (groups[bucket(p.at)] ??= []).add(p);
  }
  return [
    for (final e in groups.entries)
      HistoryPoint(
        e.key,
        e.value.map((p) => p.avg).reduce((a, b) => a + b) / e.value.length,
        e.value.map((p) => p.min).reduce((a, b) => a < b ? a : b),
        e.value.map((p) => p.max).reduce((a, b) => a > b ? a : b),
      ),
  ]..sort((a, b) => a.at.compareTo(b.at));
}
