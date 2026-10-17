import 'dart:convert';

import 'history_config.dart';
import 'history_record.dart';

/// History without Node-RED (2.9.1): ZigDash records on one device the user
/// picks, typically a wall tablet that stays open. The same logic as the
/// Node-RED recorder (node-red/history-flow.json, "record" and "tick"), so
/// both write identical day records and a Home can move from one to the
/// other without losing anything.
///
/// Pure: the caller feeds it state messages and the clock, and publishes
/// what it returns.
class HistoryFolder {
  HistoryFolder({this.keepDays = historyKeepDays});

  final int keepDays;

  /// Device state topic → the readings recorded from it.
  Map<String, List<HistoryReading>> _index = const {};

  /// `ieee/attr` → today's slots: slot → [count, sum, min, max].
  final _mem = <String, _Day>{};

  /// Days that ended before [tick] published them.
  final _done = <(String, _Day)>[];

  String? _cleanedFor;

  /// The readings to record (the retained config's list, at most 50).
  void configure(List<HistoryReading> readings) {
    final index = <String, List<HistoryReading>>{};
    final keys = <String>{};
    for (final r in readings.take(50)) {
      if (r.topic.isEmpty || r.ieee.isEmpty || r.path.isEmpty) continue;
      keys.add(_key(r));
      (index[r.topic] ??= []).add(r);
    }
    // New readings get their old records cleared too, on the next tick.
    final before = {
      for (final rs in _index.values)
        for (final r in rs) _key(r),
    };
    if (!before.containsAll(keys)) _cleanedFor = null;
    _index = index;
    _mem.removeWhere((k, _) => !keys.contains(k));
  }

  /// Whether [topic] carries a recorded reading.
  bool records(String topic) => _index.containsKey(topic);

  /// Folds a device state message into today's slot at [now].
  void record(String topic, Map<String, Object?> state, DateTime now) {
    final readings = _index[topic];
    if (readings == null) return;
    final date = historyDate(now);
    final slot = _slotOf(now);
    for (final r in readings) {
      Object? v = state;
      for (final seg in r.path.split('.')) {
        v = v is Map ? v[seg] : null;
      }
      final n = v is num
          ? v.toDouble()
          : (v is String && v.trim().isNotEmpty ? double.tryParse(v) : null);
      if (n == null || !n.isFinite) continue;
      final key = _key(r);
      var day = _mem[key];
      if (day == null || day.date != date) {
        if (day != null) _done.add((key, day));
        day = _Day(date, r.unit ?? '');
        _mem[key] = day;
      }
      day.unit = r.unit ?? day.unit;
      final s = day.slots[slot];
      day.slots[slot] = s == null
          ? [1, n, n, n]
          : [s[0] + 1, s[1] + n, s[2] < n ? s[2] : n, s[3] > n ? s[3] : n];
    }
  }

  /// Takes back today's record from the broker after a restart; slots
  /// already in memory win (they hold exact sums, the record averages).
  void restore(String ieee, String attr, String date, String payload) {
    if (payload.trim().isEmpty) return;
    final Object? j;
    try {
      j = jsonDecode(payload);
    } on FormatException {
      return;
    }
    if (j is! Map || j['b'] is! List) return;
    final key = '$ieee/$attr';
    final day = _mem[key]?.date == date
        ? _mem[key]!
        : (_Day(date, '${j['unit'] ?? ''}'));
    if (_mem[key]?.date != date) _mem[key] = day;
    for (final b in j['b'] as List) {
      if (b is! List || b.length < 4) continue;
      final [slot, avg, min, max, ...] = b;
      if (slot is! num || avg is! num || min is! num || max is! num) continue;
      day.slots.putIfAbsent(
        slot.toInt(),
        () => [1, avg.toDouble(), min.toDouble(), max.toDouble()],
      );
    }
  }

  /// Once a minute: the day records to publish retained (closed slots of
  /// today, finished days), and on a new day the old records to clear (an
  /// empty retained payload). Returns topic → payload.
  Map<String, String> tick(DateTime now) {
    final out = <String, String>{};
    final date = historyDate(now);
    final slot = _slotOf(now);
    for (final (key, day) in _done) {
      out[_topic(key, day)] = day.encode(historySlotsPerDay);
    }
    _done.clear();
    for (final e in _mem.entries.toList()) {
      final day = e.value;
      if (day.date != date) {
        out[_topic(e.key, day)] = day.encode(historySlotsPerDay);
        _mem[e.key] = _Day(date, day.unit);
        continue;
      }
      if (day.published != slot && day.slots.keys.any((s) => s < slot)) {
        out[_topic(e.key, day)] = day.encode(slot);
        day.published = slot;
      }
    }
    if (_cleanedFor != date) {
      _cleanedFor = date;
      final today = DateTime(now.year, now.month, now.day);
      final keys = {
        for (final rs in _index.values)
          for (final r in rs) _key(r),
      };
      // A week of dates beyond the window, so a recorder that was off for
      // days still cleans up (as the Node-RED one does).
      for (var d = keepDays; d < keepDays + 7; d++) {
        final old = historyDate(today.subtract(Duration(days: d)));
        for (final k in keys) {
          out.putIfAbsent('zigdash/history/$k/$old', () => '');
        }
      }
    }
    return out;
  }

  static String _key(HistoryReading r) => '${r.ieee}/${r.attr}';

  static String _topic(String key, _Day day) =>
      'zigdash/history/$key/${day.date}';

  static int _slotOf(DateTime t) =>
      (t.hour * 60 + t.minute) ~/ historySlotMinutes;
}

class _Day {
  _Day(this.date, this.unit);

  final String date;
  String unit;

  /// The last slot a record was published for, -1 for none.
  int published = -1;
  final slots = <int, List<double>>{};

  String encode(int upTo) {
    double round(double x) => (x * 100).roundToDouble() / 100;
    final b = [
      for (final s in (slots.keys.where((s) => s < upTo).toList()..sort()))
        [
          s,
          round(slots[s]![1] / slots[s]![0]),
          round(slots[s]![2]),
          round(slots[s]![3]),
        ],
    ];
    return jsonEncode({'v': 1, 'unit': unit, 'b': b});
  }
}
