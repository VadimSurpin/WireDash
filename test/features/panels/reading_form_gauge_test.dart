import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zigdash/data/database/database.dart';
import 'package:zigdash/data/database/tables/panels.dart';
import 'package:zigdash/data/repositories/connection_repo.dart';
import 'package:zigdash/data/repositories/dashboard_repo.dart';
import 'package:zigdash/data/repositories/panel_repo.dart';
import 'package:zigdash/features/discovery/providers/discovery_provider.dart';
import 'package:zigdash/features/panels/models/panel_config.dart';
import 'package:zigdash/features/panels/screens/panel_form_screen.dart';
import 'package:zigdash/l10n/app_localizations.dart';
import 'package:zigdash/mqtt/providers/mqtt_manager_provider.dart';

// Editing a reading tile (gauge-2.4.md, Editor): "Show as" switches between
// Value and Gauge; the first switch to Gauge on a tile without a range fills
// the preset for its reading, and Save keeps the gauge fields.

final _stamp = DateTime(2026, 10, 11);

Panel _reading(ReadingConfig config) => Panel(
      id: 'r1',
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
      createdAt: _stamp,
      updatedAt: _stamp,
    );

final _dashboard = Dashboard(
  id: 'd1',
  connectionId: 'c1',
  name: 'Home',
  topicPrefix: 'zigbee2mqtt',
  colorSeed: 0,
  iconCodepoint: 0,
  locked: false,
  sortOrder: 0,
  createdAt: _stamp,
  updatedAt: _stamp,
);

Widget _app(_Panels panels) => ProviderScope(
      overrides: [
        panelRepoProvider.overrideWithValue(panels),
        dashboardRepoProvider.overrideWithValue(_Dashboards()),
        connectionsStreamProvider
            .overrideWith((ref) => Stream.value(const <Connection>[])),
        dashboardsForConnectionProvider
            .overrideWith((ref, _) => Stream.value([_dashboard])),
        mqttManagerProvider.overrideWith((ref, _) => Completer<Never>().future),
        bridgeDevicesStreamProvider.overrideWith((ref, _) => Stream.value(const [])),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Save pops the form, so it needs a route under it.
        routerConfig: GoRouter(
          initialLocation: '/form',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) => const Scaffold(body: Text('dashboard')),
              routes: [
                GoRoute(
                  path: 'form',
                  builder: (_, __) => const PanelFormScreen(
                      connectionId: 'c1', dashboardId: 'd1', panelId: 'r1'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _field(String text) => find.byWidgetPredicate(
    (w) => w is EditableText && w.controller.text == text);

void main() {
  testWidgets('a value tile opens on Value with no gauge fields', (tester) async {
    await tester.pumpWidget(
        _app(_Panels(_reading(const ReadingConfig(jsonPath: 'humidity', unit: '%')))));
    await _settle(tester);
    await tester.scrollUntilVisible(find.text('Show as'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Gauge'), findsOneWidget);
    expect(find.text('Color bands'), findsNothing);
  });

  testWidgets('switching to Gauge fills the preset range and bands',
      (tester) async {
    final panels =
        _Panels(_reading(const ReadingConfig(jsonPath: 'humidity', unit: '%')));
    await _tall(tester);
    await tester.pumpWidget(_app(panels));
    await _settle(tester);
    await tester.scrollUntilVisible(find.text('Gauge'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Gauge'));
    await tester.tap(find.text('Gauge'), warnIfMissed: true);
    await _settle(tester);
    expect(find.text('Color bands'), findsOneWidget);
    expect(_field('0'), findsOneWidget, reason: 'min');
    expect(_field('100'), findsOneWidget, reason: 'max');
    expect(_field('30'), findsOneWidget, reason: 'good band from');
    expect(_field('60'), findsOneWidget, reason: 'good band to');
    expect(find.text('Good'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Save'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save'));
    await _settle(tester);
    final saved = panels.updated as ReadingConfig;
    expect(saved.style, ReadingStyle.gauge);
    expect((saved.min, saved.max), (0.0, 100.0));
    expect(saved.bands, [const GaugeBand(from: 30, to: 60, tone: GaugeTone.good)]);
  });

  testWidgets('a gauge tile opens with its own range, not the preset',
      (tester) async {
    await tester.pumpWidget(_app(_Panels(_reading(const ReadingConfig(
      jsonPath: 'temperature',
      unit: '°C',
      style: ReadingStyle.gauge,
      min: -10,
      max: 35,
      bands: [GaugeBand(from: 30, to: 35, tone: GaugeTone.attention)],
    )))));
    await _settle(tester);
    await tester.scrollUntilVisible(find.text('Color bands'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(_field('-10'), findsOneWidget);
    expect(_field('35'), findsNWidgets(2), reason: 'max and the band end');
    expect(find.text('Attention'), findsOneWidget);
  });

  testWidgets('a fourth band cannot be added; a removed band is gone on save',
      (tester) async {
    final panels = _Panels(_reading(const ReadingConfig(
      jsonPath: 'humidity',
      unit: '%',
      style: ReadingStyle.gauge,
      min: 0,
      max: 100,
      bands: [
        GaugeBand(from: 0, to: 30, tone: GaugeTone.attention),
        GaugeBand(from: 30, to: 60, tone: GaugeTone.good),
        GaugeBand(from: 60, to: 100, tone: GaugeTone.attention),
      ],
    )));
    await tester.pumpWidget(_app(panels));
    await _settle(tester);
    await tester.scrollUntilVisible(find.text('Color bands'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Add band'), findsNothing);
    await tester.tap(find.byTooltip('Remove band').last);
    await _settle(tester);
    expect(find.text('Add band'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Save'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save'));
    await _settle(tester);
    expect((panels.updated as ReadingConfig).bands, hasLength(2));
  });
}

class _Panels implements PanelRepo {
  _Panels(this.panel);
  final Panel panel;
  PanelConfig? updated;
  @override
  Future<Panel?> getById(String id) async => panel;
  @override
  Future<void> update({
    required String id,
    required String name,
    required String topic,
    String? subscribeTopic,
    String? topicPrefixOverride,
    int qos = 1,
    bool retain = false,
    PanelWidth width = PanelWidth.small,
    required PanelConfig config,
  }) async {
    updated = config;
  }

  @override
  Future<void> setDevice(String id, String? ieee) async {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Dashboards implements DashboardRepo {
  @override
  Future<Dashboard?> getById(String id) async => _dashboard;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
