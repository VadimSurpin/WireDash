import 'dart:convert';

import '../../data/database/database.dart' show Panel;
import '../../data/database/tables/panels.dart' show PanelType;
import '../devices/device_profile.dart';
import '../panels/models/panel_config.dart';
import 'history_record.dart';

/// The retained config the recorder reads (docs/design/history-2.7.md).
const historyConfigTopic = 'zigdash/history/config';

/// The recorder's heartbeat: `online`, or `offline` by its Last Will.
const historyBridgeTopic = 'zigdash/history/bridge/state';

/// At most this many readings are recorded per Home.
const historyMaxReadings = 50;

/// One recorded value: a device's numeric attribute at [path] of its state
/// topic [topic].
class HistoryReading {
  const HistoryReading({
    required this.ieee,
    required this.path,
    required this.topic,
    this.unit,
  });

  final String ieee;
  final String path;
  final String topic;
  final String? unit;

  String get attr => historyAttr(path);

  Map<String, Object?> toJson() => {
    'ieee': ieee,
    'attr': attr,
    'topic': topic,
    'path': path,
    'unit': unit ?? '',
  };

  @override
  bool operator ==(Object other) =>
      other is HistoryReading &&
      other.ieee == ieee &&
      other.path == path &&
      other.topic == topic &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(ieee, path, topic, unit);

  @override
  String toString() => 'HistoryReading($ieee $path @ $topic $unit)';
}

/// The values a device tile shows, primary first: a climate sensor's two
/// readings (temperature and humidity), any other class's first reading
/// (a plug's power). Matches the tile in device_tile_panel.dart.
List<DeviceFeature> historyShownOnDeviceTile(DeviceProfile profile) => profile
    .readings
    .take(profile.deviceClass == DeviceClass.climate ? 2 : 1)
    .toList();

/// What a Home records: every number its dashboards show, from reading
/// tiles and from device tiles, once each, in dashboard order, at most
/// [historyMaxReadings]. Tiles not linked to a device are left out: the
/// recorder keys history by IEEE address so renames keep it.
List<HistoryReading> historyReadingsOf(Iterable<Panel> tiles) {
  final out = <HistoryReading>[];
  final seen = <String>{};
  void add(Panel tile, String path, String? unit) {
    final ieee = tile.deviceIeee;
    final topic = tile.topicPrefixOverride;
    if (ieee == null || topic == null || topic.isEmpty || path.isEmpty) {
      return;
    }
    if (!seen.add('$ieee/${historyAttr(path)}')) return;
    out.add(HistoryReading(ieee: ieee, path: path, topic: topic, unit: unit));
  }

  for (final tile in tiles) {
    if (out.length >= historyMaxReadings) break;
    switch (tile.type) {
      case PanelType.reading:
        final c = PanelConfig.decode(PanelType.reading, tile.config);
        if (c is ReadingConfig) add(tile, c.jsonPath, c.unit);
      case PanelType.device:
        final c = PanelConfig.decode(PanelType.device, tile.config);
        if (c is DeviceTileConfig) {
          for (final f in historyShownOnDeviceTile(c.profile)) {
            add(tile, f.property, f.unit);
          }
        }
      default:
        break;
    }
  }
  return out.take(historyMaxReadings).toList();
}

/// The config payload for the recorder.
String encodeHistoryConfig({
  required String home,
  required String base,
  required String timeZone,
  required List<HistoryReading> readings,
}) => jsonEncode({
  'v': 1,
  'home': home,
  'base': base,
  'timeZone': timeZone,
  'keepDays': historyKeepDays,
  'readings': [for (final r in readings) r.toJson()],
});

/// The readings in a retained config payload; empty for none or a broken one.
List<HistoryReading> decodeHistoryReadings(String payload) {
  if (payload.trim().isEmpty) return const [];
  try {
    final j = jsonDecode(payload);
    if (j is! Map || j['readings'] is! List) return const [];
    return [
      for (final r in j['readings'] as List)
        if (r is Map &&
            r['ieee'] is String &&
            r['path'] is String &&
            r['topic'] is String)
          HistoryReading(
            ieee: r['ieee'] as String,
            path: r['path'] as String,
            topic: r['topic'] as String,
            unit: (r['unit'] as String?)?.isEmpty ?? true
                ? null
                : r['unit'] as String,
          ),
    ];
  } on FormatException {
    return const [];
  }
}

/// What to record when several phones share a Home: the readings already
/// on the broker, then this phone's new ones, at most [historyMaxReadings].
/// Phones only ever add, so two phones with different dashboards converge
/// instead of overwriting each other. A reading whose topic changed (a
/// renamed device) takes this phone's topic.
List<HistoryReading> mergeHistoryReadings(
  List<HistoryReading> retained,
  List<HistoryReading> mine,
) {
  String key(HistoryReading r) => '${r.ieee}/${r.attr}';
  final byKey = {for (final r in mine) key(r): r};
  final out = <HistoryReading>[for (final r in retained) byKey[key(r)] ?? r];
  final seen = {for (final r in out) key(r)};
  for (final r in mine) {
    if (seen.add(key(r))) out.add(r);
  }
  return out.take(historyMaxReadings).toList();
}
