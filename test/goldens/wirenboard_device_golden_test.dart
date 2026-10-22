import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zigdash/data/database/database.dart';
import 'package:zigdash/data/database/tables/panels.dart';
import 'package:zigdash/features/discovery/models/wirenboard_device.dart';
import 'package:zigdash/features/discovery/providers/wirenboard_discovery_provider.dart';
import 'package:zigdash/features/panels/models/panel_config.dart';
import 'package:zigdash/features/panels/providers/panel_value_provider.dart';
import 'package:zigdash/features/panels/widgets/panel_tile.dart';
import 'package:zigdash/mqtt/mqtt_status.dart';
import 'package:zigdash/mqtt/providers/mqtt_manager_provider.dart';

import 'golden_harness.dart';

final _device =
    (WirenBoardDiscovery()
          ..apply(
            '/devices/room/controls/Relay/meta',
            '{"type":"switch","order":1,"title":{"en":"Relay","he":"ממסר"}}',
          )
          ..apply(
            '/devices/room/controls/Input/meta',
            '{"type":"switch","readonly":true,"order":2,"title":{"en":"Input","he":"כניסה"}}',
          )
          ..apply(
            '/devices/room/controls/Temperature/meta',
            '{"type":"temperature","readonly":true,"order":3,"title":{"en":"Temperature","he":"טמפרטורה"}}',
          )
          ..apply(
            '/devices/room/controls/Humidity/meta',
            '{"type":"rel_humidity","readonly":true,"order":4,"title":{"en":"Humidity","he":"לחות"}}',
          )
          ..apply(
            '/devices/room/controls/Mode/meta',
            '{"type":"value","enum":{"0":"Manual","1":"Auto"},"order":5,"title":{"en":"Mode","he":"מצב"}}',
          )
          ..apply(
            '/devices/room/controls/Level/meta',
            '{"type":"range","min":0,"max":100,"order":6,"title":{"en":"Level","he":"עוצמה"}}',
          )
          ..apply(
            '/devices/room/controls/Target/meta',
            '{"type":"value","order":7,"title":{"en":"Target","he":"יעד"}}',
          ))
        .devices
        .single;

Object _value(String topic) => switch (topic.split('/').last) {
  'Temperature' => '23.5',
  'Humidity' => '45.2',
  'Level' => '65',
  'Target' => '22',
  _ => '1',
};

List<Override> _overrides() => [
  wirenBoardDevicesProvider.overrideWith((ref, _) => Stream.value([_device])),
  connectionStatusProvider.overrideWith(
    (ref, _) => Stream.value(MqttStatus.connected),
  ),
  panelValueProvider.overrideWith(
    (ref, key) => Stream.value(_value(key.topic)),
  ),
  panelValueSnapshotProvider.overrideWith(
    (ref, key) => Stream.value(
      PanelValueSnapshot(
        value: _value(key.topic),
        receivedAt: DateTime(2026),
        connectionGeneration: 1,
        freshness: PanelFreshness.fresh,
      ),
    ),
  ),
];

Widget _gridCell(Widget child) => IntrinsicHeight(
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [Expanded(child: child)],
  ),
);

void main() {
  goldenTest(
    'Wiren Board device card',
    fileName: 'wirenboard_device_card',
    pumpBeforeTest: pumpNTimes(10, const Duration(milliseconds: 50)),
    builder: () => goldenMatrix(
      variants: [
        phoneMatrix[0],
        phoneMatrix[1],
        phoneMatrix[2],
        phoneMatrix[4],
      ],
      overrides: _overrides,
      screen: () => Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Builder(
              builder: (context) => _gridCell(
                PanelTile(
                  connectionId: 'c1',
                  dashboardId: 'd1',
                  topicPrefix: null,
                  locked: true,
                  panel: Panel(
                    id: 'p1',
                    dashboardId: 'd1',
                    name: 'WB-MSW · Room',
                    type: PanelType.device,
                    topic: '',
                    subscribeTopic: '',
                    topicPrefixOverride: '/devices/room',
                    qos: 1,
                    retain: false,
                    width: PanelWidth.wide,
                    sortOrder: 0,
                    config: WirenBoardDeviceConfig(device: _device).encode(),
                    mergeFlags: 0,
                    createdAt: DateTime(2026),
                    updatedAt: DateTime(2026),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
