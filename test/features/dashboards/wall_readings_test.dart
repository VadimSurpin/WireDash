import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zigdash/data/database/database.dart' show Dashboard, Panel;
import 'package:zigdash/data/database/tables/panels.dart';
import 'package:zigdash/data/repositories/dashboard_repo.dart';
import 'package:zigdash/data/repositories/panel_repo.dart';
import 'package:zigdash/features/dashboards/wall_display.dart';
import 'package:zigdash/features/dashboards/wall_readings.dart';
import 'package:zigdash/features/dashboards/widgets/wall_idle_screen.dart';
import 'package:zigdash/features/devices/device_profile.dart';
import 'package:zigdash/features/panels/models/panel_config.dart';
import 'package:zigdash/features/panels/providers/panel_value_provider.dart';
import 'package:zigdash/features/settings/providers/settings_controller.dart';

Map<String, Object?> _num(String p, String unit) => {
  'type': 'numeric',
  'name': p,
  'property': p,
  'access': 1,
  'unit': unit,
};

final _climate = classifyExposes([
  _num('temperature', '°C'),
  _num('humidity', '%'),
  _num('battery', '%'),
]);

var _n = 0;
Panel _tile(
  PanelType type,
  PanelConfig config, {
  required String name,
  String? topic,
}) => Panel(
  id: 'p${_n++}',
  dashboardId: 'd1',
  name: name,
  type: type,
  topic: '',
  topicPrefixOverride: topic,
  qos: 1,
  retain: false,
  width: PanelWidth.small,
  sortOrder: _n,
  config: config.encode(),
  mergeFlags: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  final tiles = [
    _tile(
      PanelType.device,
      DeviceTileConfig(profile: _climate),
      name: 'Living room',
      topic: 'zigbee2mqtt/Living room',
    ),
    _tile(
      PanelType.reading,
      const ReadingConfig(jsonPath: 'power', unit: 'W'),
      name: 'Washer',
      topic: 'zigbee2mqtt/Washer',
    ),
    _tile(
      PanelType.reading,
      const ReadingConfig(jsonPath: 'co2', unit: 'ppm'),
      name: 'Office',
      topic: 'zigbee2mqtt/Office',
    ),
  ];

  test('every number a dashboard shows, in order, once each', () {
    final all = wallReadingsOf([...tiles, tiles.first], 'zigbee2mqtt');
    expect(
      [for (final r in all) '${r.name} ${r.path}'],
      [
        'Living room temperature',
        'Living room humidity',
        'Washer power',
        'Office co2',
      ],
    );
    expect(all.first.topic, 'zigbee2mqtt/Living room');
    expect(all.first.unit, '°C');
  });

  group('the idle clock with readings', () {
    late SharedPreferences prefs;

    Future<void> pump(WidgetTester tester, {List<String>? chosen}) async {
      SharedPreferences.setMockInitialValues({
        if (chosen != null) 'wall_idle_readings_d1': chosen,
      });
      prefs = await SharedPreferences.getInstance();
      final values = {
        'zigbee2mqtt/Living room/temperature': 21.5,
        'zigbee2mqtt/Living room/humidity': 48,
        'zigbee2mqtt/Washer/power': 1200,
        'zigbee2mqtt/Office/co2': 640,
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            dashboardByIdProvider('d1').overrideWith(
              (_) async => Dashboard(
                id: 'd1',
                connectionId: 'c1',
                name: 'Home',
                topicPrefix: 'zigbee2mqtt',
                colorSeed: 0,
                iconCodepoint: 0,
                locked: false,
                sortOrder: 0,
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
              ),
            ),
            panelsForDashboardProvider(
              'd1',
            ).overrideWith((_) => Stream.value(tiles)),
            panelValueProvider.overrideWith(
              (ref, key) =>
                  Stream.value(values['${key.topic}/${key.jsonPath}']),
            ),
          ],
          child: MaterialApp(
            home: WallIdleScreen(
              show: WallIdleShow.readings,
              dashboardId: 'd1',
              now: () => DateTime(2026, 10, 17, 21, 5),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('the first three until the user picks', (tester) async {
      await pump(tester);
      expect(find.text('Living room'), findsNWidgets(2));
      expect(find.text('Washer'), findsOneWidget);
      expect(find.text('Office'), findsNothing);
      expect(find.textContaining('21.5'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the picked ones, at most three', (tester) async {
      final all = wallReadingsOf(tiles, 'zigbee2mqtt');
      await pump(tester, chosen: [all[3].key, all[0].key]);
      expect(find.text('Office'), findsOneWidget);
      expect(find.text('Living room'), findsOneWidget);
      expect(find.text('Washer'), findsNothing);
      expect(find.textContaining('640'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
