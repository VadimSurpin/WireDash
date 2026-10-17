import 'package:alchemist/alchemist.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zigdash/data/database/database.dart' show Dashboard, Panel;
import 'package:zigdash/data/database/tables/panels.dart';
import 'package:zigdash/data/repositories/dashboard_repo.dart';
import 'package:zigdash/data/repositories/panel_repo.dart';
import 'package:zigdash/features/dashboards/wall_display.dart';
import 'package:zigdash/features/dashboards/wall_sensors.dart';
import 'package:zigdash/features/dashboards/widgets/wall_alarm_screen.dart';
import 'package:zigdash/features/dashboards/widgets/wall_idle_screen.dart';
import 'package:zigdash/features/panels/models/panel_config.dart';
import 'package:zigdash/features/panels/providers/panel_value_provider.dart';
import 'package:zigdash/features/settings/providers/settings_controller.dart';

import 'golden_harness.dart';

// 2.9 wall tablet (docs/design/wall-tablet-2.9.md): the idle clock with
// three readings on a landscape tablet, and alarm takeover on a phone.

Panel _reading(String id, String name, String path, String unit) => Panel(
  id: id,
  dashboardId: 'd1',
  name: name,
  type: PanelType.reading,
  topic: '',
  topicPrefixOverride: 'zigbee2mqtt/$name',
  qos: 1,
  retain: false,
  width: PanelWidth.small,
  sortOrder: 0,
  config: ReadingConfig(jsonPath: path, unit: unit).encode(),
  mergeFlags: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

final _tiles = [
  _reading('p1', 'Living room', 'temperature', '°C'),
  _reading('p2', 'Bedroom', 'humidity', '%'),
  _reading('p3', 'Kettle', 'power', 'W'),
];

const _values = {
  'zigbee2mqtt/Living room/temperature': 21.4,
  'zigbee2mqtt/Bedroom/humidity': 48,
  'zigbee2mqtt/Kettle/power': 1800,
};

void main() {
  late SharedPreferences prefs;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('wall tablet', () {
    goldenTest(
      'idle clock with readings',
      fileName: 'wall_idle_readings_tablet',
      pumpBeforeTest: pumpNTimes(4, const Duration(milliseconds: 50)),
      builder: () => goldenMatrix(
        variants: tabletMatrix,
        overrides: () => [
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
          ).overrideWith((_) => Stream.value(_tiles)),
          panelValueProvider.overrideWith(
            (ref, key) => Stream.value(_values['${key.topic}/${key.jsonPath}']),
          ),
        ],
        screen: () => WallIdleScreen(
          show: WallIdleShow.readings,
          dashboardId: 'd1',
          now: () => DateTime(2026, 10, 17, 21, 5),
        ),
      ),
    );

    goldenTest(
      'alarm takeover',
      fileName: 'wall_alarm_phone',
      builder: () => goldenMatrix(
        variants: phoneMatrix,
        overrides: () => [],
        screen: () => WallAlarmScreen(
          kind: WallAlarmKind.leak,
          deviceName: 'Laundry leak',
          onOk: () {},
        ),
      ),
    );
  });
}
