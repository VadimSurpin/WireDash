import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/core/review/command_confirmations.dart';

void main() {
  final t0 = DateTime(2026, 9, 26, 12);
  CommandConfirmations make() => CommandConfirmations();

  // First-run decision: a successful session is a day on which the user sent
  // a command and received a confirming state update.
  test('a Zigbee2MQTT state update after its /set command confirms it', () {
    final c = make();
    c.commandSent('zigbee2mqtt/lamp/set', t0);
    expect(
      c.messageReceived('zigbee2mqtt/lamp', t0.add(const Duration(seconds: 1))),
      isTrue,
    );
  });

  test('a state update without a command confirms nothing', () {
    expect(make().messageReceived('zigbee2mqtt/lamp', t0), isFalse);
  });

  test('another device answering does not confirm the command', () {
    final c = make();
    c.commandSent('zigbee2mqtt/lamp/set', t0);
    expect(c.messageReceived('zigbee2mqtt/plug', t0), isFalse);
  });

  test('an update after the 10 second window does not count', () {
    final c = make();
    c.commandSent('zigbee2mqtt/lamp/set', t0);
    expect(
      c.messageReceived(
        'zigbee2mqtt/lamp',
        t0.add(const Duration(seconds: 11)),
      ),
      isFalse,
    );
  });

  test('a per-attribute Zigbee2MQTT command is confirmed by the device', () {
    final c = make();
    c.commandSent('zigbee2mqtt/lamp/set/brightness', t0);
    expect(c.messageReceived('zigbee2mqtt/lamp', t0), isTrue);
  });

  // The broker echoes a publish back on its own topic, so a command outside
  // the Zigbee2MQTT /set convention cannot prove a device answered.
  test('a custom topic does not confirm itself', () {
    final c = make();
    c.commandSent('home/relay', t0);
    expect(c.messageReceived('home/relay', t0), isFalse);
  });

  test('one command is confirmed once', () {
    final c = make();
    c.commandSent('zigbee2mqtt/lamp/set', t0);
    expect(c.messageReceived('zigbee2mqtt/lamp', t0), isTrue);
    expect(c.messageReceived('zigbee2mqtt/lamp', t0), isFalse);
  });

  // 2.8.1: live data counts as a good day; the bridge and commands do not.
  test('isDeviceReport', () {
    expect(isDeviceReport('zigbee2mqtt/Kitchen motion'), isTrue);
    expect(isDeviceReport('home/zigbee/0xa4c13836276df66f'), isTrue);
    expect(isDeviceReport('zigbee2mqtt/bridge/devices'), isFalse);
    expect(isDeviceReport('zigbee2mqtt/lamp/set'), isFalse);
    expect(isDeviceReport('zigbee2mqtt/lamp/availability'), isFalse);
    expect(isDeviceReport('zigbee2mqtt'), isFalse);
  });
}
