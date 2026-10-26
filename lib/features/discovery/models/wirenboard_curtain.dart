import '../../panels/models/cover_controls.dart';
import 'wirenboard_device.dart';

/// A complete, writable curtain pair is published only in actuator mode.
WirenBoardCoverBinding? wirenBoardCurtainFor(
  WirenBoardDevice device,
  WirenBoardControl control,
) {
  final match = RegExp(
    r'^Curtain ([1-3]) (Open|Close)$',
  ).firstMatch(control.id);
  if (match == null || control.deviceId != device.id) return null;
  final number = int.parse(match[1]!);
  for (final direction in ['Open', 'Close']) {
    final member = device.controls
        .where((c) => c.id == 'Curtain $number $direction')
        .firstOrNull;
    if (member == null ||
        member.deviceId != device.id ||
        member.readOnly ||
        member.type != 'switch') {
      return null;
    }
  }
  return WirenBoardCoverBinding(deviceId: device.id, number: number);
}
