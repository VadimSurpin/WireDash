import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/data/database/tables/panels.dart';
import 'package:wiredash/features/panels/models/panel_config.dart';

void main() {
  group('ReadingConfig', () {
    test('a tile from before gauges decodes as a plain value', () {
      final c = PanelConfig.decode(
          PanelType.reading, '{"jsonPath":"power","unit":"W"}') as ReadingConfig;
      expect(c.style, ReadingStyle.value);
      expect(c.min, isNull);
      expect(c.max, isNull);
      expect(c.bands, isEmpty);
    });

    test('a plain value encodes nothing gauge-related', () {
      const c = ReadingConfig(jsonPath: 'power', unit: 'W');
      expect(json.decode(c.encode()), {'jsonPath': 'power', 'unit': 'W'});
    });

    test('a gauge round-trips its range and bands', () {
      const c = ReadingConfig(
        jsonPath: 'humidity',
        unit: '%',
        style: ReadingStyle.gauge,
        min: 0,
        max: 100,
        bands: [
          GaugeBand(from: 30, to: 60, tone: GaugeTone.good),
          GaugeBand(from: 80, to: 100, tone: GaugeTone.attention),
        ],
      );
      final back =
          PanelConfig.decode(PanelType.reading, c.encode()) as ReadingConfig;
      expect(back.style, ReadingStyle.gauge);
      expect(back.min, 0);
      expect(back.max, 100);
      expect(back.bands, c.bands);
    });

    test('unknown style and tone names fall back, bands cap at three', () {
      final c = PanelConfig.decode(PanelType.reading, json.encode({
        'jsonPath': 'x',
        'style': 'dial',
        'bands': [
          {'from': 0, 'to': 1, 'tone': 'purple'},
          {'from': 1, 'to': 2, 'tone': 'good'},
          {'from': 2, 'to': 3, 'tone': 'good'},
          {'from': 3, 'to': 4, 'tone': 'good'},
          {'to': 5},
        ],
      })) as ReadingConfig;
      expect(c.style, ReadingStyle.value);
      expect(c.bands, hasLength(3));
      expect(c.bands.first.tone, GaugeTone.normal);
    });

    test('copyWith keeps what it is not given', () {
      const c = ReadingConfig(jsonPath: 'battery', unit: '%', min: 0, max: 100);
      final g = c.copyWith(style: ReadingStyle.gauge);
      expect(g.jsonPath, 'battery');
      expect(g.min, 0);
      expect(g.style, ReadingStyle.gauge);
    });
  });
}
