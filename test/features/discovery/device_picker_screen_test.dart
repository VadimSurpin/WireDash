import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

Widget _wrap({required List<Override> overrides}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const DevicePickerScreen(connectionId: 'c1', dashboardId: 'd1'),
  ),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
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
    expect(find.text('Relay 1'), findsOneWidget);
    expect(find.text('/devices/relay/controls/Relay 1'), findsOneWidget);
    expect(find.text('Living Room Light'), findsNothing);
    expect(find.byType(TextField), findsNothing);
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
