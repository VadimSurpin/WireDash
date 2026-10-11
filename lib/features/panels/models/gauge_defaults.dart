import 'panel_config.dart';

/// A gauge's starting range and bands for one reading
/// (docs/design/gauge-2.4.md, Defaults).
typedef GaugeDefaults = ({double min, double max, List<GaugeBand> bands});

/// The range and bands a gauge starts with. The device's expose wins when
/// Zigbee2MQTT declares a range ([featureMin] and [featureMax]); otherwise a
/// preset by what the reading is, judged from [property] and [unit]:
///
/// - battery: 0 to 100, attention under 20
/// - humidity: 0 to 100, good from 30 to 60
/// - temperature: 0 to 40 °C (32 to 104 °F), no bands
/// - power: 0 to 3000 W, no bands
/// - anything else: 0 to 100, no bands
///
/// Everything is editable afterwards.
GaugeDefaults gaugeDefaults({
  required String property,
  String? unit,
  num? featureMin,
  num? featureMax,
}) {
  final p = property.toLowerCase();
  final u = unit?.trim() ?? '';
  final kind = p.contains('battery')
      ? _Kind.battery
      : p.contains('humidity')
          ? _Kind.humidity
          : p.contains('temperature') || u == '°C' || u == '°F'
              ? _Kind.temperature
              : p == 'power' || p.endsWith('_power') || u == 'W'
                  ? _Kind.power
                  : _Kind.other;
  final preset = switch (kind) {
    _Kind.battery => (min: 0.0, max: 100.0),
    _Kind.humidity => (min: 0.0, max: 100.0),
    _Kind.temperature =>
      u == '°F' ? (min: 32.0, max: 104.0) : (min: 0.0, max: 40.0),
    _Kind.power => (min: 0.0, max: 3000.0),
    _Kind.other => (min: 0.0, max: 100.0),
  };
  final fromDevice = featureMin != null &&
      featureMax != null &&
      featureMax > featureMin;
  final min = fromDevice ? featureMin.toDouble() : preset.min;
  final max = fromDevice ? featureMax.toDouble() : preset.max;
  final bands = switch (kind) {
    _Kind.battery => [
        GaugeBand(from: min, to: 20, tone: GaugeTone.attention),
      ],
    _Kind.humidity => const [
        GaugeBand(from: 30, to: 60, tone: GaugeTone.good),
      ],
    _ => const <GaugeBand>[],
  };
  return (min: min, max: max, bands: bands);
}

enum _Kind { battery, humidity, temperature, power, other }
