import '../../data/database/tables/panels.dart';
import '../../data/repositories/panel_repo.dart';
import '../discovery/models/z2m_device.dart';
import '../panels/models/gauge_defaults.dart';
import '../panels/models/panel_config.dart';
import 'device_profile.dart';

/// The Zigbee2MQTT base topic for a dashboard: its topic prefix, or the
/// Zigbee2MQTT default when a hand-made dashboard left it empty.
String z2mBase(String? dashboardPrefix, {String? homeBase}) {
  final set = homeBase?.trim() ?? '';
  if (set.isNotEmpty) return set;
  final p = dashboardPrefix?.trim() ?? '';
  return p.isEmpty ? 'zigbee2mqtt' : p;
}

/// A tile's default size for a device class: Wide for colour lights and
/// covers, Small otherwise.
PanelWidth defaultTileSize(DeviceClass c) => switch (c) {
      DeviceClass.colorLight || DeviceClass.cover => PanelWidth.wide,
      _ => PanelWidth.small,
    };

/// True for a Zigbee2MQTT friendly name that is still the IEEE address.
bool isIeeeName(String name) => RegExp(r'^0x[0-9a-fA-F]{16}$').hasMatch(name);

/// "Tuya CK-BL702-AL-01", or null.
String? deviceModelLabel(Z2mDevice d) {
  final label = [?d.vendor, ?d.model].join(' ');
  return label.isEmpty ? null : label;
}

/// Creates a device tile for [device]: bound by IEEE address, reading
/// `<base>/<friendly name>` and commanding its `/set`.
Future<String> createDeviceTile(
  PanelRepo panels, {
  required String dashboardId,
  required String base,
  required Z2mDevice device,
  String? name,
  PanelWidth? size,
  String? sectionId,
  required int sortOrder,
}) {
  final profile = classifyExposes(device.rawExposes);
  return panels.create(
    dashboardId: dashboardId,
    name: name ?? device.friendlyName,
    type: PanelType.device,
    topic: 'set',
    subscribeTopic: '',
    topicPrefixOverride: '$base/${device.friendlyName}',
    width: size ?? defaultTileSize(profile.deviceClass),
    sortOrder: sortOrder,
    sectionId: sectionId,
    deviceIeee: device.ieeeAddress,
    config: DeviceTileConfig(profile: profile, model: deviceModelLabel(device)),
  );
}

/// Creates a reading tile for one numeric [feature] of [device], linked to
/// the device so it follows renames and counts as "on a dashboard".
Future<String> createReadingTile(
  PanelRepo panels, {
  required String dashboardId,
  required String base,
  required Z2mDevice device,
  required DeviceFeature feature,
  required String name,
  PanelWidth size = PanelWidth.small,
  required int sortOrder,
  String? sectionId,
}) =>
    panels.create(
      dashboardId: dashboardId,
      name: name,
      type: PanelType.reading,
      topic: '',
      subscribeTopic: '',
      topicPrefixOverride: '$base/${device.friendlyName}',
      width: size,
      sortOrder: sortOrder,
      sectionId: sectionId,
      deviceIeee: device.ieeeAddress,
      config: readingConfigFor(feature),
    );

/// A reading tile's config for [feature]: shown as a value, with the gauge
/// range and bands already filled from the device's expose (or the preset
/// for that kind of reading), so switching to Gauge in the editor needs no
/// typing.
ReadingConfig readingConfigFor(DeviceFeature feature) {
  final d = gaugeDefaults(
    property: feature.property,
    unit: feature.unit,
    featureMin: feature.min,
    featureMax: feature.max,
  );
  return ReadingConfig(
    jsonPath: feature.property,
    unit: feature.unit,
    min: d.min,
    max: d.max,
    bands: d.bands,
  );
}
