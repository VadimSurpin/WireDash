import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zigdash/data/database/database.dart';
import 'package:zigdash/data/database/tables/panels.dart';
import 'package:zigdash/features/panels/models/panel_config.dart';
import 'package:zigdash/features/devices/device_profile.dart';
import 'package:zigdash/features/discovery/models/device_panel_suggestion.dart';
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
  Panel? existing;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getById) {
      return Future<Panel?>.value(existing);
    }
    if (invocation.memberName == #setDevice) return Future<void>.value();
    if (invocation.memberName == #update) {
      saved = invocation.namedArguments;
      return Future<void>.value();
    }
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
    'device edit': '{"type":"switch"}',
    'device display edit': '{"type":"switch"}',
    'native display edit': '{"type":"switch"}',
    'reading selector': '{"type":"value","units":"V","readonly":true}',
    'device': '{"type":"switch"}',
    'switch': '{"type":"switch"}',
    'switch override': '{"type":"switch","readonly":true}',
    'switch override reset': '{"type":"switch","readonly":true}',
    'switch input selector': '{"type":"switch"}',
    'rgb': '{"type":"rgb"}',
    'local time': '{"type":"local_time"}',
    'custom': '{"type":"custom"}',
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
      if (entry.key == 'device display edit') {
        discovery.apply(
          '/devices/board/controls/Temperature/meta',
          '{"type":"temperature","readonly":true}',
        );
      }
      if (entry.key == 'switch' || entry.key == 'switch input selector') {
        discovery.apply('$topic/meta/readonly', '1');
      }
      final device = discovery.devices.single;
      final native = entry.key == 'native display edit';
      final custom = entry.key.contains('display edit');
      final whole = entry.key.startsWith('device') || native;
      final editing = entry.key.endsWith('edit');
      final suggestion = native
          ? PanelSuggestion(
              type: PanelType.device,
              name: 'Native device',
              topicPrefixOverride: '/devices/board',
              publishTopicSuffix: 'set',
              subscribeTopicSuffix: '',
              config: DeviceTileConfig(
                profile: classifyExposes([
                  {
                    'type': 'binary',
                    'property': 'state',
                    'name': 'state',
                    'access': 3,
                    'value_on': 'ON',
                    'value_off': 'OFF',
                  },
                  {
                    'type': 'numeric',
                    'property': 'temperature',
                    'name': 'temperature',
                    'access': 1,
                    'unit': '°C',
                  },
                ]),
              ),
            )
          : whole
          ? suggestWirenBoardDevicePanel(device)
          : suggestWirenBoardPanel(device, device.controls.single);
      final panels = _Panels();
      if (editing) {
        panels.existing = Panel(
          id: 'existing',
          dashboardId: 'd1',
          name: suggestion.name,
          type: suggestion.type,
          topic: suggestion.publishTopicSuffix,
          subscribeTopic: suggestion.subscribeTopicSuffix,
          topicPrefixOverride: suggestion.topicPrefixOverride,
          qos: 1,
          retain: false,
          width: PanelWidth.wide,
          sortOrder: 0,
          config: suggestion.config!.encode(),
          mergeFlags: 0,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
      }
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
              suggestion: editing ? null : suggestion,
              panelId: editing ? 'existing' : null,
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
      if (custom) {
        final id = native ? 'state' : 'Control 1';
        final label = find.byKey(ValueKey('display-label:0:$id'));
        await tester.ensureVisible(label);
        await tester.enterText(label, 'Kitchen lights');
        await tester.tap(find.byKey(ValueKey('display-property:$id')));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      final overriding = entry.key.startsWith('switch override');
      final resetOverride = entry.key == 'switch override reset';
      if (overriding) {
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Name'),
          'Kitchen relay',
        );
        final overrideSwitch = find.text(
          lookupAppLocalizations(const Locale('en')).panelAllowCommands,
        );
        await tester.tap(overrideSwitch);
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        if (resetOverride) {
          await tester.tap(overrideSwitch);
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
      }
      final selectingInput = entry.key == 'switch input selector';
      if (entry.key == 'reading selector' || selectingInput) {
        final name = find.widgetWithText(TextFormField, 'Name');
        await tester.enterText(name, 'Supply voltage');
        final selector = find.byType(DropdownButtonFormField<PanelType>);
        await tester.ensureVisible(selector);
        await tester.tap(selector);
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(
          find
              .text(
                selectingInput
                    ? lookupAppLocalizations(
                        const Locale('en'),
                      ).panelTypeTextInput
                    : lookupAppLocalizations(
                        const Locale('en'),
                      ).panelTypeProgress,
              )
              .last,
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          tester.widget<TextFormField>(name).controller!.text,
          'Supply voltage',
        );
      }
      await tester.tap(find.text('Save'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final saved = panels.saved!;
      if (custom) {
        final config = saved[#config] as PanelConfig;
        final display = config is WirenBoardDeviceConfig
            ? config.display
            : (config as DeviceTileConfig).display;
        final id = native ? 'state' : 'Control 1';
        expect(display.labels[id], 'Kitchen lights');
        expect(display.properties, [native ? 'temperature' : 'Temperature']);
        if (config is WirenBoardDeviceConfig) {
          expect(config.controlIds, isNull);
        }
      } else if (overriding && !resetOverride) {
        expect(saved[#config], isA<ToggleConfig>());
        final config = saved[#config] as ToggleConfig;
        expect(config.onPayload, '1');
        expect(config.offPayload, '0');
        expect(config.jsonPath, isNull);
        expect(saved[#topic], 'on');
        expect(saved[#name], 'Kitchen relay');
      } else if (selectingInput) {
        expect(saved[#config], isA<TextInputConfig>());
        expect((saved[#config] as TextInputConfig).template, '{value}');
        expect(saved[#name], 'Supply voltage');
      } else if (entry.key == 'reading selector') {
        expect(saved[#config], isA<ProgressConfig>());
        expect((saved[#config] as ProgressConfig).jsonPath, isNull);
        expect((saved[#config] as ProgressConfig).unit, 'V');
        expect(saved[#name], 'Supply voltage');
      } else {
        expect(saved[#config].encode(), suggestion.config!.encode());
      }
      expect(saved[#retain], isFalse);
      if (!editing) {
        expect(
          saved[#type],
          overriding && !resetOverride
              ? PanelType.toggle
              : selectingInput
              ? PanelType.textInput
              : entry.key == 'reading selector'
              ? PanelType.progress
              : suggestion.type,
        );
      }
      expect(
        composeTopic(
          saved[#topicPrefixOverride],
          saved[#subscribeTopic] ?? saved[#topic],
        ),
        whole ? '/devices/board' : topic,
      );
      if (!whole && !device.controls.single.readOnly) {
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
