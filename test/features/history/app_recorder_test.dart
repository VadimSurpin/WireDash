import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/features/history/app_recorder.dart';
import 'package:wiredash/features/history/history_config.dart';
import 'package:wiredash/features/history/history_record.dart';

const _temp = HistoryReading(
  ieee: '0xa1',
  path: 'temperature',
  topic: 'zigbee2mqtt/Living room',
  unit: '°C',
);

Map<String, Object?> _record(String payload) =>
    jsonDecode(payload) as Map<String, Object?>;

void main() {
  test('folds values into 15-minute slots and publishes closed slots', () {
    final f = HistoryFolder()..configure([_temp]);
    f.record('zigbee2mqtt/Living room', {
      'temperature': 21.0,
    }, DateTime(2026, 10, 17, 10, 1));
    f.record('zigbee2mqtt/Living room', {
      'temperature': 22.0,
    }, DateTime(2026, 10, 17, 10, 7));
    f.record('zigbee2mqtt/Other', {
      'temperature': 99.0,
    }, DateTime(2026, 10, 17, 10, 8));

    // Slot 40 (10:00–10:15) is still open: only the old-record cleanup.
    final early = f.tick(DateTime(2026, 10, 17, 10, 10));
    expect(early.values.where((p) => p.isNotEmpty), isEmpty);

    final out = f.tick(DateTime(2026, 10, 17, 10, 15));
    final topic = 'zigdash/history/0xa1/temperature/2026-10-17';
    expect(_record(out[topic]!), {
      'v': 1,
      'unit': '°C',
      'b': [
        [40, 21.5, 21.0, 22.0],
      ],
    });
    // The same slot isn't published again until another one closes.
    expect(f.tick(DateTime(2026, 10, 17, 10, 16)).containsKey(topic), isFalse);

    // The record parses as the history sheet reads it.
    final points = parseDayRecord(out[topic]!, DateTime(2026, 10, 17))!;
    expect(points.single.at, DateTime(2026, 10, 17, 10));
    expect(points.single.avg, 21.5);
  });

  test('a new day publishes the full old day', () {
    final f = HistoryFolder()..configure([_temp]);
    f.record('zigbee2mqtt/Living room', {
      'temperature': 20,
    }, DateTime(2026, 10, 17, 23, 50));
    final out = f.tick(DateTime(2026, 10, 18, 0, 1));
    final b = _record(out['zigdash/history/0xa1/temperature/2026-10-17']!)['b'];
    expect(b, [
      [95, 20.0, 20.0, 20.0],
    ]);
  });

  test('clears records that left the 30-day window, once a day', () {
    final f = HistoryFolder()..configure([_temp]);
    final out = f.tick(DateTime(2026, 10, 17, 9));
    expect(out['zigdash/history/0xa1/temperature/2026-09-17'], '');
    expect(out['zigdash/history/0xa1/temperature/2026-09-11'], '');
    expect(
      out.containsKey('zigdash/history/0xa1/temperature/2026-09-18'),
      isFalse,
    );
    expect(
      f
          .tick(DateTime(2026, 10, 17, 9, 1))
          .containsKey('zigdash/history/0xa1/temperature/2026-09-17'),
      isFalse,
    );
  });

  test("after a restart today's record comes back; memory wins", () {
    final f = HistoryFolder()..configure([_temp]);
    f.restore(
      '0xa1',
      'temperature',
      '2026-10-17',
      jsonEncode({
        'v': 1,
        'unit': '°C',
        'b': [
          [30, 19.0, 18.5, 19.5],
          [40, 1.0, 1.0, 1.0],
        ],
      }),
    );
    f.record('zigbee2mqtt/Living room', {
      'temperature': 21,
    }, DateTime(2026, 10, 17, 10, 2));
    f.restore(
      '0xa1',
      'temperature',
      '2026-10-17',
      jsonEncode({
        'b': [
          [40, 1.0, 1.0, 1.0],
        ],
      }),
    );
    final out = f.tick(DateTime(2026, 10, 17, 10, 20));
    final b = _record(out['zigdash/history/0xa1/temperature/2026-10-17']!)['b'];
    expect(
      b,
      [
        [30, 19.0, 18.5, 19.5],
        [40, 11.0, 1.0, 21.0],
      ],
      reason:
          'the restored slot counts as one value and the live 21 folds in, '
          'as in the Node-RED recorder; the second restore changes nothing',
    );
  });

  test('nested paths and numbers sent as text', () {
    const r = HistoryReading(
      ieee: '0xb2',
      path: 'energy.power',
      topic: 'zigbee2mqtt/Plug',
      unit: 'W',
    );
    final f = HistoryFolder()..configure([r]);
    f.record('zigbee2mqtt/Plug', {
      'energy': {'power': '12.5'},
    }, DateTime(2026, 10, 17, 8, 0));
    final out = f.tick(DateTime(2026, 10, 17, 8, 15));
    expect(_record(out['zigdash/history/0xb2/energy_power/2026-10-17']!)['b'], [
      [32, 12.5, 12.5, 12.5],
    ]);
  });
}
