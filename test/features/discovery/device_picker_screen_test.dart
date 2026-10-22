import 'package:zigdash/features/devices/devices_providers.dart'
    show homeBaseTopicProvider;
import 'package:zigdash/features/discovery/wirenboard_dashboard_importer.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zigdash/data/database/tables/panels.dart';
import 'package:zigdash/features/discovery/models/device_panel_suggestion.dart';
import 'package:zigdash/features/panels/models/panel_config.dart';
import 'package:zigdash/features/discovery/models/z2m_device.dart';
import 'package:zigdash/features/discovery/providers/discovery_provider.dart';
import 'package:zigdash/features/discovery/screens/device_picker_screen.dart';
import 'package:zigdash/l10n/app_localizations.dart';
import 'package:zigdash/features/discovery/models/wirenboard_device.dart';
import 'package:zigdash/features/discovery/providers/wirenboard_discovery_provider.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _fixtureDevices = [
  const Z2mDevice(
    friendlyName: 'Living Room Light',
    type: 'Router',
    vendor: 'IKEA',
    model: 'LED1545G12',
    exposes: [Z2mExpose(type: 'light')],
  ),
  const Z2mDevice(
    friendlyName: 'Kitchen Sensor',
    type: 'EndDevice',
    vendor: 'Aqara',
    model: 'WSDCGQ11LM',
    exposes: [Z2mExpose(type: 'numeric', property: 'temperature')],
  ),
];

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _wrap({required List<Override> overrides, String? homeBase}) =>
    ProviderScope(
      overrides: [
        homeBaseTopicProvider.overrideWith((ref, _) => homeBase),
        wirenBoardDashboardImporterProvider.overrideWith(
          (ref, _) => _NoopWbImporter(),
        ),
        wirenBoardDashboardIdsProvider.overrideWith((ref, _) => {}),
        ...overrides,
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DevicePickerScreen(connectionId: 'c1', dashboardId: 'd1'),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

class _NoopWbImporter implements WirenBoardDashboardImporter {
  @override
  Future<int> importDevices(
    List<WirenBoardDevice> devices, {
    bool includeBuiltins = false,
  }) async => 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'WB copies use the home custom native Z2M base for their section',
    (tester) async {
      final wb =
          (WirenBoardDiscovery()..apply(
                '/devices/room_lamp/controls/state/meta',
                '{"type":"switch"}',
              ))
              .devices;
      await tester.pumpWidget(
        _wrap(
          homeBase: 'home/z2m',
          overrides: [
            discoveredDevicesProvider.overrideWith((ref, _) async => []),
            wirenBoardDevicesProvider.overrideWith(
              (ref, _) => Stream.value(wb),
            ),
            bridgeDevicesStreamProvider.overrideWith((ref, args) {
              expect(args.base, 'home/z2m');
              return Stream.value(const [
                Z2mDevice(friendlyName: 'room/lamp', type: 'Router'),
              ]);
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wiren Board'));
      await tester.pumpAndSettle();
      expect(find.text('Wirenboard Z2M devices'), findsOneWidget);
      expect(find.text('Added modules'), findsNothing);
    },
  );

  testWidgets('Wiren Board source lists retained controls and live changes', (
    tester,
  ) async {
    final discovery = WirenBoardDiscovery()
      ..apply('/devices/relay/meta/name', 'Relay module')
      ..apply('/devices/relay/controls/Relay 1/meta', '{"type":"switch"}');
    final updates = StreamController<List<WirenBoardDevice>>.broadcast();
    await tester.pumpWidget(
      _wrap(
        overrides: [
          discoveredDevicesProvider.overrideWith(
            (ref, _) async => _fixtureDevices,
          ),
          bridgeDevicesStreamProvider.overrideWith(
            (ref, _) => Stream.value(const []),
          ),
          wirenBoardDevicesProvider.overrideWith((ref, _) => updates.stream),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wiren Board'));
    await tester.pump();
    updates.add(discovery.devices);
    await tester.pumpAndSettle();
    expect(find.text('Relay module'), findsOneWidget);
    expect(find.text('Relay 1'), findsNothing);
    await tester.tap(find.text('Relay module'));
    await tester.pumpAndSettle();
    expect(find.text('Relay 1'), findsOneWidget);
    expect(find.text('Living Room Light'), findsNothing);
    expect(find.byType(SearchBar), findsOneWidget);
    expect(find.text('Added modules'), findsOneWidget);
    updates.add([]);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No Wiren Board controls found'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await updates.close();
  });

  testWidgets(
    'groups built-ins, keeps expansion on updates and searches controls',
    (tester) async {
      final discovery = WirenBoardDiscovery()
        ..apply('/devices/hwmon/meta/name', 'Hardware monitor')
        ..apply(
          '/devices/hwmon/controls/CPU Temperature/meta',
          '{"type":"temperature","readonly":true}',
        )
        ..apply('/devices/wb-mr6c_12/meta/name', 'Relay module')
        ..apply(
          '/devices/wb-mr6c_12/controls/Relay 1/meta',
          '{"type":"switch"}',
        );
      final updates = StreamController<List<WirenBoardDevice>>.broadcast();
      await tester.pumpWidget(
        _wrap(
          overrides: [
            discoveredDevicesProvider.overrideWith((ref, _) async => []),
            bridgeDevicesStreamProvider.overrideWith(
              (ref, _) => Stream.value(const []),
            ),
            wirenBoardDevicesProvider.overrideWith((ref, _) => updates.stream),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wiren Board'));
      await tester.pump();
      updates.add(discovery.devices);
      await tester.pumpAndSettle();
      expect(find.text('Controller built-ins'), findsOneWidget);
      expect(find.text('Added modules'), findsOneWidget);
      expect(find.text('CPU Temperature'), findsNothing);
      expect(find.text('Relay 1'), findsNothing);
      await tester.tap(find.text('Relay module'));
      await tester.pumpAndSettle();
      discovery.apply(
        '/devices/wb-mr6c_12/controls/Relay 2/meta',
        '{"type":"switch"}',
      );
      updates.add(discovery.devices);
      await tester.pumpAndSettle();
      expect(find.text('Relay 1'), findsOneWidget);
      expect(find.text('Relay 2'), findsOneWidget);
      await tester.tap(find.text('Relay module'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(SearchBar),
          matching: find.byType(TextField),
        ),
        'CPU',
      );
      await tester.pumpAndSettle();
      expect(find.text('CPU Temperature'), findsOneWidget);
      expect(find.text('Relay module'), findsNothing);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Relay module'), findsOneWidget);
      expect(find.text('Relay 1'), findsNothing);
      expect(find.text('CPU Temperature'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await updates.close();
    },
  );

  testWidgets(
    'the plus action adds a whole device without expanding controls',
    (tester) async {
      final devices =
          (WirenBoardDiscovery()..apply(
                '/devices/hwmon/controls/Relay 1/meta',
                '{"type":"switch"}',
              ))
              .devices;
      PanelSuggestion? picked;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const DevicePickerScreen(
              connectionId: 'c1',
              dashboardId: 'd1',
              initialWirenBoard: true,
            ),
          ),
          GoRoute(
            path: '/connections/c1/dashboards/d1/panels/new',
            builder: (_, state) {
              picked = state.extra as PanelSuggestion;
              return const Scaffold(body: Text('New panel'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeBaseTopicProvider.overrideWith((ref, _) => null),
            wirenBoardDashboardImporterProvider.overrideWith(
              (ref, _) => _NoopWbImporter(),
            ),
            wirenBoardDashboardIdsProvider.overrideWith((ref, _) => {}),
            bridgeDevicesStreamProvider.overrideWith(
              (ref, _) => Stream.value(const []),
            ),
            wirenBoardDevicesProvider.overrideWith(
              (ref, _) => Stream.value(devices),
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
      expect(find.text('Relay 1'), findsNothing);
      await tester.tap(find.byTooltip('Add whole device'));
      await tester.pumpAndSettle();
      expect(picked!.type, PanelType.device);
      expect((picked!.config as WirenBoardDeviceConfig).device.id, 'hwmon');
      expect(picked!.topicPrefixOverride, '/devices/hwmon');
    },
  );

  testWidgets('data state — device friendly names render', (tester) async {
    await tester.pumpWidget(
      _wrap(
        overrides: [
          discoveredDevicesProvider.overrideWith(
            (ref, args) async => _fixtureDevices,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Living Room Light'), findsOneWidget);
    expect(find.text('Kitchen Sensor'), findsOneWidget);
  });

  testWidgets('empty state — discoverNone message shows', (tester) async {
    await tester.pumpWidget(
      _wrap(
        overrides: [
          discoveredDevicesProvider.overrideWith(
            (ref, args) async => <Z2mDevice>[],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // l10n key discoverNone → "No devices found."
    expect(find.text('No devices found.'), findsOneWidget);
  });

  testWidgets('error state — discoverFailed message and Retry button show', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        overrides: [
          discoveredDevicesProvider.overrideWith(
            (ref, args) async => throw Exception('timeout'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // l10n key discoverFailed
    expect(find.textContaining('No device list found'), findsOneWidget);
    // l10n key retry → "Retry"
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('loading state — CircularProgressIndicator is shown', (
    tester,
  ) async {
    // A Completer that is never completed keeps the FutureProvider loading.
    final completer = Completer<List<Z2mDevice>>();
    addTearDown(() {
      if (!completer.isCompleted) completer.completeError('disposed');
    });

    await tester.pumpWidget(
      _wrap(
        overrides: [
          discoveredDevicesProvider.overrideWith(
            (ref, args) => completer.future,
          ),
        ],
      ),
    );
    // One pump so the widget tree builds without resolving the future.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
