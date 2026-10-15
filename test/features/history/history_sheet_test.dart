import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/features/history/history_chart.dart';
import 'package:zigdash/features/history/history_record.dart';
import 'package:zigdash/features/history/history_service.dart';
import 'package:zigdash/features/history/history_sheet.dart';
import 'package:zigdash/features/kiosk/kiosk.dart';
import 'package:zigdash/features/pro/pro.dart';
import 'package:zigdash/l10n/app_localizations.dart';

final _now = DateTime(2026, 10, 15, 12);

const _recordingThis =
    '{"readings":[{"ieee":"0xa1","attr":"temperature","topic":"z/x","path":"temperature"}]}';

class _KioskOn extends KioskController {
  @override
  KioskState build() => const KioskState(connectionId: 'c1', dashboardId: 'd1');
}

Widget _app({
  required bool? online,
  Map<String, List<HistoryPoint>> days = const {},
  ProStatus pro = ProStatus.unlocked,
  bool kiosk = false,
  String retained = _recordingThis,
}) => ProviderScope(
  overrides: [
    if (kiosk) kioskProvider.overrideWith(_KioskOn.new),
    proStatusProvider.overrideWithValue(pro),
    historyRecorderOnlineProvider.overrideWith(
      (ref, _) => online == null ? const Stream.empty() : Stream.value(online),
    ),
    historyDaysProvider.overrideWith((ref, _) => Stream.value(days)),
    historyRetainedConfigProvider.overrideWith(
      (ref, _) => Stream.value(retained),
    ),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: HistorySheet(
        connectionId: 'c1',
        ieee: '0xa1',
        path: 'temperature',
        title: 'Living room',
        unit: '°C',
        now: () => _now,
      ),
    ),
  ),
);

final _today = {
  '2026-10-15': [
    HistoryPoint(DateTime(2026, 10, 15, 10), 21, 20, 22),
    HistoryPoint(DateTime(2026, 10, 15, 10, 15), 22, 21, 23),
  ],
};

void main() {
  testWidgets('no recorder and no data: the set-up card', (tester) async {
    await tester.pumpWidget(_app(online: null));
    await tester.pump();
    expect(find.text('Record history on your hub'), findsOneWidget);
    expect(find.text('Set up on the hub'), findsOneWidget);
    expect(find.byType(HistoryChart), findsNothing);
  });

  testWidgets('a running recorder with no values yet says so', (tester) async {
    await tester.pumpWidget(_app(online: true));
    await tester.pump();
    expect(find.textContaining('No values yet'), findsOneWidget);
  });

  testWidgets('data: the graph, the latest value and since when', (
    tester,
  ) async {
    await tester.pumpWidget(_app(online: true, days: _today));
    await tester.pump();
    expect(find.byType(HistoryChart), findsOneWidget);
    expect(find.text('\u206622°C\u2069'), findsOneWidget);
    expect(find.textContaining('Recording since'), findsOneWidget);
    expect(find.text('7 days'), findsOneWidget, reason: 'outside Play');
  });

  testWidgets('an offline recorder is named under the graph', (tester) async {
    await tester.pumpWidget(_app(online: false, days: _today));
    await tester.pump();
    expect(find.textContaining("isn't answering"), findsOneWidget);
  });

  testWidgets('Pro not offered yet: only 24 hours', (tester) async {
    await tester.pumpWidget(
      _app(online: true, days: _today, pro: ProStatus.unavailable),
    );
    await tester.pump();
    expect(find.text('7 days'), findsNothing);
    expect(find.byType(SegmentedButton<HistoryRange>), findsNothing);
  });

  testWidgets('Pro locked: 7 days shows the sample and Unlock', (tester) async {
    await tester.pumpWidget(
      _app(online: true, days: _today, pro: ProStatus.locked),
    );
    await tester.pump();
    await tester.tap(find.text('7 days'));
    await tester.pump();
    expect(find.textContaining('ZigDash Pro'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
  });

  testWidgets('kiosk guests see the locked sample but no Unlock', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(online: true, days: _today, pro: ProStatus.locked, kiosk: true),
    );
    await tester.pump();
    await tester.tap(find.text('7 days'));
    await tester.pump();
    expect(find.textContaining('ZigDash Pro'), findsOneWidget);
    expect(find.text('Unlock'), findsNothing);
  });

  testWidgets('a reading the recorder skips says how to record it', (
    tester,
  ) async {
    await tester.pumpWidget(_app(online: true, retained: '{"readings":[]}'));
    await tester.pump();
    expect(
      find.textContaining('Only numbers shown on a dashboard'),
      findsOneWidget,
    );
    expect(find.textContaining('No values yet'), findsNothing);
  });
}
