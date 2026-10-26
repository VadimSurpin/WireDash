import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/features/panels/models/gauge_defaults.dart';
import 'package:wiredash/features/panels/models/panel_config.dart';

void main() {
  group('gaugeDefaults', () {
    test('battery: 0 to 100, attention under 20', () {
      final d = gaugeDefaults(property: 'battery', unit: '%');
      expect((d.min, d.max), (0.0, 100.0));
      expect(d.bands, [const GaugeBand(from: 0, to: 20, tone: GaugeTone.attention)]);
    });

    test('humidity: 0 to 100, good between 30 and 60', () {
      final d = gaugeDefaults(property: 'humidity', unit: '%');
      expect((d.min, d.max), (0.0, 100.0));
      expect(d.bands, [const GaugeBand(from: 30, to: 60, tone: GaugeTone.good)]);
    });

    test('temperature: 0 to 40 °C or 32 to 104 °F, no bands', () {
      final c = gaugeDefaults(property: 'temperature', unit: '°C');
      expect((c.min, c.max), (0.0, 40.0));
      expect(c.bands, isEmpty);
      final f = gaugeDefaults(property: 'temperature', unit: '°F');
      expect((f.min, f.max), (32.0, 104.0));
      final byUnit = gaugeDefaults(property: 'local_temperature', unit: '°C');
      expect(byUnit.max, 40);
    });

    test('power: 0 to 3000 W, by property or unit', () {
      expect(gaugeDefaults(property: 'power', unit: 'W').max, 3000);
      expect(gaugeDefaults(property: 'active_power', unit: 'W').max, 3000);
      expect(gaugeDefaults(property: 'load', unit: 'W').max, 3000);
    });

    test('anything else: 0 to 100, no bands', () {
      final d = gaugeDefaults(property: 'illuminance', unit: 'lx');
      expect((d.min, d.max), (0.0, 100.0));
      expect(d.bands, isEmpty);
    });

    test("the device's declared range wins over the preset", () {
      final d = gaugeDefaults(
          property: 'temperature', unit: '°C', featureMin: -20, featureMax: 60);
      expect((d.min, d.max), (-20.0, 60.0));
    });

    test('a declared range that is empty or inverted is ignored', () {
      expect(
          gaugeDefaults(property: 'humidity', featureMin: 50, featureMax: 50).max,
          100);
      expect(
          gaugeDefaults(property: 'humidity', featureMin: 90, featureMax: 10).max,
          100);
    });

    test('battery attention band starts at the declared minimum', () {
      final d = gaugeDefaults(property: 'battery', featureMin: 5, featureMax: 100);
      expect(d.bands.single.from, 5);
    });
  });
}
