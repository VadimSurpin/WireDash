import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/core/theme/signal_colors.dart';
import 'package:zigdash/data/database/database.dart';
import 'package:zigdash/data/database/tables/panels.dart';
import 'package:zigdash/features/panels/models/panel_config.dart';
import 'package:zigdash/features/panels/providers/panel_value_provider.dart';
import 'package:zigdash/features/panels/widgets/device_tile_panel.dart' show ltr;
import 'package:zigdash/features/panels/widgets/gauge_panel.dart';
import 'package:zigdash/features/panels/widgets/reading_panel.dart';
import 'package:zigdash/l10n/app_localizations.dart';

const _bands = [
  GaugeBand(from: 0, to: 20, tone: GaugeTone.attention),
  GaugeBand(from: 20, to: 50, tone: GaugeTone.normal),
  GaugeBand(from: 50, to: 100, tone: GaugeTone.good),
];

Panel _panel(ReadingConfig config) => Panel(
      id: 'p1',
      dashboardId: 'd1',
      name: 'Bedroom humidity',
      type: PanelType.reading,
      topic: '',
      subscribeTopic: '',
      topicPrefixOverride: 'zigbee2mqtt/climate',
      qos: 1,
      retain: false,
      width: PanelWidth.small,
      sortOrder: 0,
      config: config.encode(),
      mergeFlags: 0,
      createdAt: DateTime(2026, 10, 11),
      updatedAt: DateTime(2026, 10, 11),
    );

Future<void> _pump(WidgetTester tester, ReadingConfig config, Object? value,
    {TextDirection direction = TextDirection.ltr}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      panelValueProvider.overrideWith((ref, key) => Stream<Object?>.value(value)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: SizedBox(
            width: 180,
            child: ReadingPanel(
              connectionId: 'c1',
              subscribeTopic: 'zigbee2mqtt/climate',
              panel: _panel(config),
              config: config,
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('gaugeBandFor / gaugeFraction', () {
    test('the first band containing the value wins; edges are inclusive', () {
      expect(gaugeBandFor(20, _bands)!.tone, GaugeTone.attention);
      expect(gaugeBandFor(21, _bands)!.tone, GaugeTone.normal);
      expect(gaugeBandFor(75, _bands)!.tone, GaugeTone.good);
      expect(gaugeBandFor(120, _bands), isNull);
      expect(gaugeBandFor(null, _bands), isNull);
    });

    test('fraction clamps to the range and is null without one', () {
      expect(gaugeFraction(50, 0, 100), 0.5);
      expect(gaugeFraction(-5, 0, 100), 0);
      expect(gaugeFraction(500, 0, 100), 1);
      expect(gaugeFraction(50, 100, 100), isNull);
      expect(gaugeFraction(null, 0, 100), isNull);
    });
  });

  testWidgets(
    'a before-display expression scales numbers and preserves fixed decimals',
    (tester) async {
      await _pump(
        tester,
        const ReadingConfig(
          jsonPath: '',
          unit: 'V',
          valueExpression: '(Number(value) / 100).toFixed(2)',
        ),
        '1230',
      );
      expect(find.text(ltr('12.30 V')), findsOneWidget);
      await _pump(
        tester,
        const ReadingConfig(
          jsonPath: '',
          unit: 'V',
          valueExpression: 'Number(value) / 100',
          style: ReadingStyle.gauge,
          min: 0,
          max: 20,
        ),
        '1230',
      );
      expect(tester.widget<GaugeArc>(find.byType(GaugeArc)).value, 12.3);
    },
  );

  testWidgets(
    'a bad display expression keeps the reading and exposes an error indicator',
    (tester) async {
      await _pump(
        tester,
        const ReadingConfig(
          jsonPath: '',
          unit: 'V',
          valueExpression: 'missingValue',
        ),
        12,
      );
      expect(find.text(ltr('12 V')), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    },
  );

  group('ReadingPanel as a gauge', () {
    const gauge = ReadingConfig(
      jsonPath: 'humidity',
      unit: '%',
      style: ReadingStyle.gauge,
      min: 0,
      max: 100,
      bands: _bands,
    );

    testWidgets('draws the arc with the value inside and the name below',
        (tester) async {
      await _pump(tester, gauge, 48);
      expect(find.byType(GaugeArc), findsOneWidget);
      expect(find.text(ltr('48%')), findsOneWidget);
      expect(find.text('Bedroom humidity'), findsOneWidget);
    });

    testWidgets('shows a dash with no value and still draws the arc',
        (tester) async {
      await _pump(tester, gauge, null);
      expect(find.byType(GaugeArc), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('a plain value tile has no arc', (tester) async {
      await _pump(tester, const ReadingConfig(jsonPath: 'humidity', unit: '%'), 48);
      expect(find.byType(GaugeArc), findsNothing);
      expect(find.text(ltr('48%')), findsOneWidget);
    });

    testWidgets('a gauge without a saved range uses the preset for its reading',
        (tester) async {
      await _pump(
          tester,
          const ReadingConfig(
              jsonPath: 'humidity', unit: '%', style: ReadingStyle.gauge),
          48);
      final arc = tester.widget<GaugeArc>(find.byType(GaugeArc));
      expect((arc.min, arc.max), (0.0, 100.0));
    });

    testWidgets('the value text stays left-to-right in a Hebrew layout',
        (tester) async {
      await _pump(tester, gauge, 48, direction: TextDirection.rtl);
      final text = tester.widget<Text>(find.text(ltr('48%')));
      expect(text.textDirection, TextDirection.ltr);
    });

    testWidgets('a value in the good band fills in the healthy role',
        (tester) async {
      await _pump(tester, gauge, 75);
      final el = tester.element(find.byType(GaugeArc));
      expect(tester.widget<GaugeArc>(find.byType(GaugeArc)).fillColor(el),
          SignalColors.of(el).onHealthy);
    });

    testWidgets('a value in the attention band fills in the attention role',
        (tester) async {
      await _pump(tester, gauge, 10);
      final el = tester.element(find.byType(GaugeArc));
      expect(tester.widget<GaugeArc>(find.byType(GaugeArc)).fillColor(el),
          SignalColors.of(el).onAttention);
    });

    testWidgets('a value in a normal band, or none, fills in ink',
        (tester) async {
      await _pump(tester, gauge, 35);
      final el = tester.element(find.byType(GaugeArc));
      expect(tester.widget<GaugeArc>(find.byType(GaugeArc)).fillColor(el),
          Theme.of(el).colorScheme.onSurface);
    });
  });
}
