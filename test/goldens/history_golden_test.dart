import 'dart:math' as math;

import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/features/history/history_record.dart';
import 'package:wiredash/features/history/history_service.dart';
import 'package:wiredash/features/history/history_sheet.dart';
import 'package:wiredash/features/pro/pro.dart';

import 'golden_harness.dart';

// 2.7 history sheet (docs/design/history-2.7.md, decision 9): a day of
// living-room temperature with a gap, and the locked Pro view.

final _now = DateTime(2026, 10, 15, 18);

List<HistoryPoint> _day(DateTime d, {int from = 0, int to = 96}) => [
  for (var s = from; s < to; s++)
    if (s < 50 || s > 58) // two hours without values
      () {
        final v = 21.5 + 1.8 * math.sin((s - 30) / 96 * 2 * math.pi);
        return HistoryPoint(
          DateTime(d.year, d.month, d.day).add(Duration(minutes: s * 15)),
          double.parse(v.toStringAsFixed(2)),
          double.parse((v - 0.3).toStringAsFixed(2)),
          double.parse((v + 0.3).toStringAsFixed(2)),
        );
      }(),
];

final _days = {
  '2026-10-14': _day(DateTime(2026, 10, 14), from: 60),
  '2026-10-15': _day(DateTime(2026, 10, 15), to: 72),
};

Widget _sheet() => Scaffold(
  body: SafeArea(
    child: HistorySheet(
      connectionId: 'c1',
      ieee: '0xa1',
      path: 'temperature',
      title: 'Living room · Temperature',
      unit: '°C',
      now: () => _now,
    ),
  ),
);

void main() {
  group('history', () {
    goldenTest(
      'sheet',
      fileName: 'history_sheet_phone',
      pumpBeforeTest: pumpNTimes(6, const Duration(milliseconds: 50)),
      builder: () => goldenMatrix(
        variants: phoneMatrix,
        overrides: () => [
          proStatusProvider.overrideWithValue(ProStatus.locked),
          historyRecorderOnlineProvider.overrideWith(
            (ref, _) => Stream.value(true),
          ),
          historyDaysProvider.overrideWith((ref, _) => Stream.value(_days)),
          historyRetainedConfigProvider.overrideWith(
            (ref, _) => Stream.value(''),
          ),
        ],
        screen: _sheet,
      ),
    );
  });
}
