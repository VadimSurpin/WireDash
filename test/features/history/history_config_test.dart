import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/data/database/database.dart' show Panel;
import 'package:zigdash/data/database/tables/panels.dart';
import 'package:zigdash/features/devices/device_profile.dart';
import 'package:zigdash/features/history/history_config.dart';
import 'package:zigdash/features/panels/models/panel_config.dart';

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
  _num('linkquality', 'lqi'),
]);

final _plug = classifyExposes([
  {
    'type': 'switch',
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
  },
  _num('power', 'W'),
  _num('energy', 'kWh'),
]);

var _n = 0;
Panel _tile(
  PanelType type,
  PanelConfig config, {
  String? ieee,
  String? topic,
}) => Panel(
  id: 'p${_n++}',
  dashboardId: 'd1',
  name: 'tile',
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
  deviceIeee: ieee,
);

void main() {
  test('device tiles record what they show; reading tiles their value', () {
    final readings = historyReadingsOf([
      _tile(
        PanelType.device,
        DeviceTileConfig(profile: _climate),
        ieee: '0xa1',
        topic: 'zigbee2mqtt/Living room',
      ),
      _tile(
        PanelType.device,
        DeviceTileConfig(profile: _plug),
        ieee: '0xb2',
        topic: 'zigbee2mqtt/Plug',
      ),
      _tile(
        PanelType.reading,
        const ReadingConfig(jsonPath: 'energy', unit: 'kWh'),
        ieee: '0xb2',
        topic: 'zigbee2mqtt/Plug',
      ),
    ]);
    expect(readings, const [
      HistoryReading(
        ieee: '0xa1',
        path: 'temperature',
        topic: 'zigbee2mqtt/Living room',
        unit: '°C',
      ),
      HistoryReading(
        ieee: '0xa1',
        path: 'humidity',
        topic: 'zigbee2mqtt/Living room',
        unit: '%',
      ),
      HistoryReading(
        ieee: '0xb2',
        path: 'power',
        topic: 'zigbee2mqtt/Plug',
        unit: 'W',
      ),
      HistoryReading(
        ieee: '0xb2',
        path: 'energy',
        topic: 'zigbee2mqtt/Plug',
        unit: 'kWh',
      ),
    ]);
  });

  test('a value shown twice is recorded once; unlinked tiles are skipped', () {
    final readings = historyReadingsOf([
      _tile(
        PanelType.device,
        DeviceTileConfig(profile: _climate),
        ieee: '0xa1',
        topic: 'zigbee2mqtt/Living room',
      ),
      _tile(
        PanelType.reading,
        const ReadingConfig(jsonPath: 'temperature'),
        ieee: '0xa1',
        topic: 'zigbee2mqtt/Living room',
      ),
      _tile(
        PanelType.reading,
        const ReadingConfig(jsonPath: 'temperature'),
        topic: 'custom/topic',
      ),
    ]);
    expect(readings.map((r) => r.path), ['temperature', 'humidity']);
  });

  test('at most 50 readings', () {
    final readings = historyReadingsOf([
      for (var i = 0; i < 60; i++)
        _tile(
          PanelType.reading,
          const ReadingConfig(jsonPath: 'power'),
          ieee: '0x$i',
          topic: 'zigbee2mqtt/plug $i',
        ),
    ]);
    expect(readings.length, historyMaxReadings);
  });

  test('the config payload matches what the recorder reads', () {
    final j =
        jsonDecode(
              encodeHistoryConfig(
                home: 'Home',
                base: 'zigbee2mqtt',
                timeZone: 'Europe/Berlin',
                readings: const [
                  HistoryReading(
                    ieee: '0xa1',
                    path: 'state.l1',
                    topic: 'zigbee2mqtt/x',
                  ),
                ],
              ),
            )
            as Map;
    expect(j['keepDays'], 30);
    expect(j['timeZone'], 'Europe/Berlin');
    expect(j['readings'], [
      {
        'ieee': '0xa1',
        'attr': 'state_l1',
        'topic': 'zigbee2mqtt/x',
        'path': 'state.l1',
        'unit': '',
      },
    ]);
  });

  test('two phones with different dashboards converge', () {
    const a = HistoryReading(ieee: '0xa', path: 'temperature', topic: 'z/A');
    const b = HistoryReading(ieee: '0xb', path: 'power', topic: 'z/B');
    const c = HistoryReading(ieee: '0xc', path: 'humidity', topic: 'z/C');
    String enc(List<HistoryReading> r) => encodeHistoryConfig(
      home: 'H',
      base: 'zigbee2mqtt',
      timeZone: 'UTC',
      readings: r,
    );
    // The tablet shows a and b; the phone shows b and c.
    var retained = enc(mergeHistoryReadings(const [], const [a, b]));
    retained = enc(
      mergeHistoryReadings(decodeHistoryReadings(retained), const [b, c]),
    );
    final again = mergeHistoryReadings(decodeHistoryReadings(retained), const [
      a,
      b,
    ]);
    expect(again, const [a, b, c], reason: 'nothing to undo');
    expect(
      mergeHistoryReadings(decodeHistoryReadings(retained), const [b, c]),
      const [a, b, c],
    );
  });

  test('a renamed device takes the new topic', () {
    const old = HistoryReading(ieee: '0xa', path: 'power', topic: 'z/Old');
    const renamed = HistoryReading(ieee: '0xa', path: 'power', topic: 'z/New');
    expect(mergeHistoryReadings(const [old], const [renamed]), const [renamed]);
  });

  test('a broken retained config reads as none', () {
    expect(decodeHistoryReadings('not json'), isEmpty);
    expect(decodeHistoryReadings(''), isEmpty);
  });
}
