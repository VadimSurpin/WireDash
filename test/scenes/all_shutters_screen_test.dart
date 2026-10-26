import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart' as mc;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiredash/data/database/database.dart';
import 'package:wiredash/data/database/tables/connections.dart';
import 'package:wiredash/data/database/tables/panels.dart';
import 'package:wiredash/data/repositories/connection_repo.dart';
import 'package:wiredash/data/repositories/dashboard_repo.dart';
import 'package:wiredash/features/discovery/models/z2m_device.dart';
import 'package:wiredash/features/discovery/providers/discovery_provider.dart';
import 'package:wiredash/features/panels/models/panel_config.dart';
import 'package:wiredash/features/panels/widgets/scene_panel.dart';
import 'package:wiredash/features/scenes/all_shutters.dart';
import 'package:wiredash/features/scenes/scenes_providers.dart';
import 'package:wiredash/features/scenes/screens/scenes_screen.dart';
import 'package:wiredash/features/settings/providers/settings_controller.dart';
import 'package:wiredash/l10n/app_localizations.dart';
import 'package:wiredash/mqtt/broker_config.dart';
import 'package:wiredash/mqtt/mqtt_manager.dart';
import 'package:wiredash/mqtt/providers/mqtt_manager_provider.dart';

// The built-in "All shutters" scenes (all-shutters-2.4.md) in the Scenes
// tab and as a scene tile: offered when the Home has shutters, commanding
// every included one on tap.

class _Recording extends MqttManager {
  _Recording()
    : super(
        config: const BrokerConfig(
          id: 'c1',
          host: 'localhost',
          port: 1883,
          protocol: MqttProtocol.tcp,
        ),
        password: '',
      );
  final published = <(String, String)>[];
  @override
  bool get isConnected => true;
  @override
  void publish(
    String topic,
    String template,
    Object value, {
    mc.MqttQos qos = mc.MqttQos.atLeastOnce,
    bool retain = false,
  }) {
    published.add((topic, template));
  }
}

const _cover = {
  'type': 'cover',
  'features': [
    {
      'type': 'enum',
      'name': 'state',
      'property': 'state',
      'access': 3,
      'values': ['OPEN', 'CLOSE', 'STOP'],
    },
    {
      'type': 'numeric',
      'name': 'position',
      'property': 'position',
      'access': 7,
    },
  ],
};
const _light = {
  'type': 'light',
  'features': [
    {
      'type': 'binary',
      'name': 'state',
      'property': 'state',
      'access': 7,
      'value_on': 'ON',
      'value_off': 'OFF',
    },
  ],
};

Z2mDevice _dev(String name, Object expose, String ieee) => Z2mDevice(
  friendlyName: name,
  type: 'Router',
  ieeeAddress: ieee,
  rawExposes: [expose],
);

final _stamp = DateTime(2026, 10, 11);
final _home = Connection(
  transport: ConnectionTransport.mqtt,
  id: 'c1',
  name: 'Home',
  host: '192.168.1.2',
  port: 1883,
  protocol: MqttProtocol.tcp,
  keepAliveSeconds: 60,
  autoConnect: true,
  createdAt: _stamp,
  updatedAt: _stamp,
);
final _dashboard = Dashboard(
  id: 'd1',
  connectionId: 'c1',
  name: 'My Home',
  topicPrefix: 'zigbee2mqtt',
  colorSeed: 0,
  iconCodepoint: 0,
  locked: false,
  sortOrder: 0,
  createdAt: _stamp,
  updatedAt: _stamp,
);

/// No saved scenes, and no database (a drift stream would leave a timer).
class _NoScenes implements SceneRepo {
  @override
  Stream<List<Scene>> watchByConnection(String connectionId) =>
      Stream.value(const []);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<_Recording> _pump(
  WidgetTester tester,
  List<Z2mDevice> devices, {
  Map<String, Object> prefs = const {},
  Widget? child,
  bool noDashboards = false,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final mgr = _Recording();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(p),
        sceneRepoProvider.overrideWithValue(_NoScenes()),
        connectionsStreamProvider.overrideWith((ref) => Stream.value([_home])),
        dashboardsForConnectionProvider.overrideWith(
          (ref, _) => Stream.value(noDashboards ? const [] : [_dashboard]),
        ),
        bridgeDevicesStreamProvider.overrideWith(
          (ref, _) => Stream.value(devices),
        ),
        mqttManagerProvider.overrideWith((ref, _) async => mgr),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child ?? const ScenesScreen(connectionId: 'c1'),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return mgr;
}

void main() {
  final shutters = [
    _dev('Living room blind', _cover, '0x01'),
    _dev('Kitchen lamp', _light, '0x02'),
    _dev('Garage door', _cover, '0x03'),
  ];

  testWidgets('a Home with shutters lists the three built-ins first', (
    tester,
  ) async {
    await _pump(tester, shutters);
    expect(find.text('All shutters'), findsOneWidget);
    expect(find.text('Close all shutters'), findsOneWidget);
    expect(find.text('Open all shutters'), findsOneWidget);
    expect(find.text('Stop all shutters'), findsOneWidget);
    expect(find.text('2 shutters'), findsNWidgets(3));
    expect(find.text('Your scenes'), findsOneWidget);
    expect(find.textContaining('No scenes yet'), findsOneWidget);
  });

  testWidgets('a Home without shutters shows only the empty state', (
    tester,
  ) async {
    await _pump(tester, [shutters[1]]);
    expect(find.text('All shutters'), findsNothing);
    expect(find.text('Close all shutters'), findsNothing);
    expect(find.textContaining('No scenes yet'), findsOneWidget);
  });

  testWidgets('tapping Close all commands every shutter, not the lamp', (
    tester,
  ) async {
    final mgr = await _pump(tester, shutters);
    await tester.tap(find.text('Close all shutters'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(mgr.published, [
      ('zigbee2mqtt/Living room blind/set', '{"state":"CLOSE"}'),
      ('zigbee2mqtt/Garage door/set', '{"state":"CLOSE"}'),
    ]);
    expect(find.text('Activated Close all shutters'), findsOneWidget);
  });

  testWidgets('an excluded shutter is left out and not counted', (
    tester,
  ) async {
    final mgr = await _pump(
      tester,
      shutters,
      prefs: {
        allShuttersExcludedKey('c1'): ['0x03'],
      },
    );
    expect(find.text('1 shutter'), findsNWidgets(3));
    await tester.tap(find.text('Open all shutters'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(mgr.published, [
      ('zigbee2mqtt/Living room blind/set', '{"state":"OPEN"}'),
    ]);
  });

  testWidgets('Which shutters… unticks a shutter and saves it at once', (
    tester,
  ) async {
    await _pump(tester, shutters);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Which shutters…').last);
    await tester.pumpAndSettle();
    expect(find.text('Garage door'), findsOneWidget);
    await tester.tap(find.text('Garage door'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(excludedShutters(prefs, 'c1'), {'0x03'});
  });

  testWidgets('with no base topic known yet, nothing is sent', (tester) async {
    final mgr = await _pump(tester, shutters, noDashboards: true);
    expect(
      find.text('Close all shutters'),
      findsNothing,
      reason: 'no base, no device list, so the group is hidden',
    );
    final panel = Panel(
      id: 'p1',
      dashboardId: 'd1',
      name: 'Close all shutters',
      type: PanelType.scene,
      topic: '',
      subscribeTopic: '',
      topicPrefixOverride: null,
      qos: 1,
      retain: false,
      width: PanelWidth.small,
      sortOrder: 0,
      config: SceneConfig(
        sceneId: allShuttersSceneId(ShutterCommand.close),
      ).encode(),
      mergeFlags: 0,
      createdAt: _stamp,
      updatedAt: _stamp,
    );
    await _pump(
      tester,
      shutters,
      noDashboards: true,
      child: Scaffold(
        body: ScenePanel(
          connectionId: 'c1',
          panel: panel,
          config: SceneConfig(
            sceneId: allShuttersSceneId(ShutterCommand.close),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Close all shutters'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(mgr.published, isEmpty);
    expect(
      find.text("Not connected — can't activate the scene"),
      findsOneWidget,
    );
  });

  testWidgets('a scene tile for a built-in runs it too', (tester) async {
    final panel = Panel(
      id: 'p1',
      dashboardId: 'd1',
      name: 'Close all shutters',
      type: PanelType.scene,
      topic: '',
      subscribeTopic: '',
      topicPrefixOverride: null,
      qos: 1,
      retain: false,
      width: PanelWidth.small,
      sortOrder: 0,
      config: SceneConfig(
        sceneId: allShuttersSceneId(ShutterCommand.stop),
      ).encode(),
      mergeFlags: 0,
      createdAt: _stamp,
      updatedAt: _stamp,
    );
    final mgr = await _pump(
      tester,
      shutters,
      child: Scaffold(
        body: ScenePanel(
          connectionId: 'c1',
          panel: panel,
          config: SceneConfig(sceneId: allShuttersSceneId(ShutterCommand.stop)),
        ),
      ),
    );
    expect(find.text('Scene not found — re-pick it'), findsNothing);
    await tester.tap(find.text('Close all shutters'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(mgr.published.map((p) => p.$2).toSet(), {'{"state":"STOP"}'});
    expect(mgr.published, hasLength(2));
  });
}
