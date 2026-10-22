import '../../devices/device_profile.dart';
import '../../discovery/models/wirenboard_device.dart';

List<String> defaultWirenBoardDisplayProperties(WirenBoardDevice device) {
  final switches = device.controls.where(
    (c) => c.type == 'switch' && !c.readOnly,
  );
  final readings = device.controls.where((c) => c.numeric).take(2);
  final ids = {...switches.map((c) => c.id), ...readings.map((c) => c.id)};
  if (ids.isEmpty && device.controls.isNotEmpty) {
    ids.add(device.controls.first.id);
  }
  return ids.toList();
}

List<String> defaultDeviceDisplayProperties(DeviceProfile profile) => {
  ...profile.switches.map((f) => f.property),
  if (profile.brightness case final feature?) feature.property,
  if (profile.colorTemp case final feature?) feature.property,
  if (profile.position case final feature?) feature.property,
  if (profile.deviceClass == DeviceClass.colorLight &&
      profile.feature('color') != null)
    'color',
  if (profile.alarm case final feature?) feature.property,
  ...profile.readings
      .take(profile.deviceClass == DeviceClass.climate ? 2 : 1)
      .map((f) => f.property),
  if (profile.battery case final feature?) feature.property,
  if (profile.deviceClass == DeviceClass.cover &&
      profile.feature('state') != null)
    'state',
}.toList();
