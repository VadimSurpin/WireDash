import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/features/history/history_record.dart';

void main() {
  final day = DateTime(2026, 10, 15);

  test('a day record parses into slots at local wall time', () {
    final points = parseDayRecord(
      '{"v":1,"unit":"°C","b":[[44,24,24,24],[40,22.17,21,23.5]]}',
      day,
    )!;
    expect(points, [
      HistoryPoint(DateTime(2026, 10, 15, 10), 22.17, 21, 23.5),
      HistoryPoint(DateTime(2026, 10, 15, 11), 24, 24, 24),
    ]);
  });

  test('empty, broken and odd records', () {
    expect(parseDayRecord('', day), isNull, reason: 'cleared by the recorder');
    expect(parseDayRecord('not json', day), isNull);
    expect(parseDayRecord('{"v":1}', day), isNull);
    expect(
      parseDayRecord('{"b":[[96,1,1,1],[-1,1,1,1],["x",1,1,1],[3,1,1]]}', day),
      isEmpty,
    );
  });

  test('topics, dates and attributes match the recorder', () {
    expect(
      historyRecordTopic('0xa1', 'temperature', DateTime(2026, 1, 5, 23)),
      'zigdash/history/0xa1/temperature/2026-01-05',
    );
    expect(historyAttr('state.l1'), 'state_l1');
    expect(historyAttr('power'), 'power');
  });

  test('the views read today and the days before', () {
    final now = DateTime(2026, 10, 15, 9, 30);
    expect(historyDays(HistoryRange.day, now), [
      DateTime(2026, 10, 14),
      DateTime(2026, 10, 15),
    ]);
    expect(historyDays(HistoryRange.week, now).length, 8);
    expect(historyDays(HistoryRange.month, now).first, DateTime(2026, 9, 16));
    expect(HistoryRange.day.isPro, isFalse);
    expect(HistoryRange.week.isPro, isTrue);
  });

  test('24 hours spans midnight and leaves out older slots', () {
    final now = DateTime(2026, 10, 15, 9, 30);
    final series = historySeries(HistoryRange.day, now, {
      '2026-10-14': [
        HistoryPoint(DateTime(2026, 10, 14, 9), 1, 1, 1), // older than 24 h
        HistoryPoint(DateTime(2026, 10, 14, 22), 2, 2, 2),
      ],
      '2026-10-15': [HistoryPoint(DateTime(2026, 10, 15, 8), 3, 3, 3)],
    });
    expect(series.map((p) => p.avg), [2, 3]);
  });

  test('7 days folds slots into hours; 30 days into days', () {
    final now = DateTime(2026, 10, 15, 12);
    final day15 = [
      HistoryPoint(DateTime(2026, 10, 15, 10), 20, 19, 21),
      HistoryPoint(DateTime(2026, 10, 15, 10, 15), 22, 21, 25),
      HistoryPoint(DateTime(2026, 10, 15, 11), 30, 30, 30),
    ];
    expect(historySeries(HistoryRange.week, now, {'2026-10-15': day15}), [
      HistoryPoint(DateTime(2026, 10, 15, 10), 21, 19, 25),
      HistoryPoint(DateTime(2026, 10, 15, 11), 30, 30, 30),
    ]);
    expect(historySeries(HistoryRange.month, now, {'2026-10-15': day15}), [
      HistoryPoint(DateTime(2026, 10, 15), 24, 19, 30),
    ]);
  });
}
