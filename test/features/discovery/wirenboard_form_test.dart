import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zigdash/data/database/database.dart';
import 'package:zigdash/data/repositories/connection_repo.dart';
import 'package:zigdash/data/repositories/dashboard_repo.dart';
import 'package:zigdash/data/repositories/panel_repo.dart';
import 'package:zigdash/features/discovery/models/wirenboard_device.dart';
import 'package:zigdash/features/discovery/models/wirenboard_panel_suggestion.dart';
import 'package:zigdash/features/discovery/providers/discovery_provider.dart';
import 'package:zigdash/features/panels/providers/panel_value_provider.dart';
import 'package:zigdash/features/panels/screens/panel_form_screen.dart';
import 'package:zigdash/l10n/app_localizations.dart';
import 'package:zigdash/mqtt/providers/mqtt_manager_provider.dart';

class _Panels implements PanelRepo {
  Map<Symbol, dynamic>? saved;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #create) {
      saved = invocation.namedArguments;
      return Future<String>.value('new-panel');
    }
    return super.noSuchMethod(invocation);
  }
}

class _Dashboards implements DashboardRepo {
  final dashboard = Dashboard(
    id: 'd1',
    connectionId: 'c1',
    name: 'Home',
    topicPrefix: 'unrelated/dashboard',
    colorSeed: 0,
    iconCodepoint: 0,
    locked: false,
    sortOrder: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  @override
  Future<Dashboard?> getById(String id) async => dashboard;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  const cases = {
    'switch': '{"type":"switch"}',
    'range': '{"type":"range","min":10,"max":200}',
    'reading': '{"type":"value","units":"V","readonly":true}',
    'enum': '{"type":"text","enum":{"off":{"en":"Off"},"auto":{"en":"Auto"}}}',
    'button': '{"type":"pushbutton"}',
  };
  for (final entry in cases.entries) {
    testWidgets('${entry.key} survives the tile form and saves scalar config', (
      tester,
    ) async {
      const topic = '/devices/board/controls/Control 1';
      final discovery = WirenBoardDiscovery()
        ..apply('$topic/meta', entry.value);
      final device = discovery.devices.single;
      final suggestion = suggestWirenBoardPanel(device, device.controls.single);
      final panels = _Panels();
      final dashboards = _Dashboards();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () => context.push('/new'),
                child: const Text('Add'),
              ),
            ),
          ),
          GoRoute(
            path: '/new',
            builder: (_, __) => PanelFormScreen(
              connectionId: 'c1',
              dashboardId: 'd1',
              suggestion: suggestion,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            panelRepoProvider.overrideWithValue(panels),
            dashboardRepoProvider.overrideWithValue(dashboards),
            connectionsStreamProvider.overrideWith(
              (ref) => Stream.value(<Connection>[]),
            ),
            dashboardsForConnectionProvider.overrideWith(
              (ref, _) => Stream.value([dashboards.dashboard]),
            ),
            bridgeDevicesStreamProvider.overrideWith(
              (ref, _) => Stream.value([]),
            ),
            mqttManagerProvider.overrideWith(
              (ref, _) => Completer<Never>().future,
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('Save'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final saved = panels.saved!;
      expect(saved[#config].encode(), suggestion.config!.encode());
      expect(saved[#retain], isFalse);
      expect(saved[#type], suggestion.type);
      expect(
        composeTopic(
          saved[#topicPrefixOverride],
          saved[#subscribeTopic] ?? saved[#topic],
        ),
        topic,
      );
      if (!device.controls.single.readOnly) {
        expect(
          composeTopic(saved[#topicPrefixOverride], saved[#topic]),
          '$topic/on',
        );
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
