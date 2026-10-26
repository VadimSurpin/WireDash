import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/features/connections/discovery/network_info_io.dart';

void main() {
  test('Samsung with Wi-Fi Direct listed first: picks wlan0', () {
    // Interfaces of a Galaxy S24 FE on a Deco /22, in the order that broke
    // the scan.
    expect(
      pickHomeIpv4(const [
        (name: 'p2p-wlan0-0', ip: '192.168.223.11'),
        (name: 'wlan0', ip: '192.168.68.62'),
      ]),
      '192.168.68.62',
    );
  });

  test('private mobile data is never picked over Wi-Fi', () {
    expect(
      pickHomeIpv4(const [
        (name: 'rmnet_data1', ip: '10.123.4.5'),
        (name: 'wlan0', ip: '192.168.1.20'),
      ]),
      '192.168.1.20',
    );
  });

  test('VPN and Wi-Fi Direct alone: nothing to scan', () {
    expect(
      pickHomeIpv4(const [
        (name: 'tun0', ip: '10.8.0.2'),
        (name: 'p2p-wlan0-0', ip: '192.168.49.1'),
      ]),
      isNull,
    );
  });

  test('an unknown interface with a private address still works', () {
    expect(
      pickHomeIpv4(const [(name: 'mlan0', ip: '192.168.0.9')]),
      '192.168.0.9',
    );
  });

  test('no private address: falls back to the first usable one', () {
    expect(
      pickHomeIpv4(const [(name: 'wlan0', ip: '100.70.1.2')]),
      '100.70.1.2',
    );
  });

  test('pickHomeAddress keeps the interface name', () {
    expect(
      pickHomeAddress([
        (name: 'p2p-wlan0-0', ip: '192.168.49.1'),
        (name: 'wlan0', ip: '192.168.68.57'),
      ]),
      (name: 'wlan0', ip: '192.168.68.57'),
    );
  });

  // 2.6.2: a VPN up during the scan is a diagnostic on the empty result.
  test('hasVpnInterface knows tunnel interfaces', () {
    expect(hasVpnInterface(['wlan0', 'tun0']), isTrue);
    expect(hasVpnInterface(['wlan0', 'utun3']), isTrue);
    expect(hasVpnInterface(['en0', 'wg0']), isTrue);
    expect(hasVpnInterface(['wlan0', 'p2p-wlan0-0', 'rmnet0']), isFalse);
    expect(hasVpnInterface(const []), isFalse);
  });

  group('why there is no home address (2.9.4)', () {
    test('mobile data only, IPv6 too', () {
      expect(
        whyNoNetwork(const [
          (name: 'rmnet_data0', ip: '2a00:1:2::5'),
          (name: 'wlan0', ip: 'fe80::1'),
        ]),
        NoNetwork.mobileData,
      );
    });

    test('nothing but link-local: no network', () {
      expect(
        whyNoNetwork(const [(name: 'wlan0', ip: 'fe80::abcd')]),
        NoNetwork.offline,
      );
      expect(whyNoNetwork(const []), NoNetwork.offline);
    });

    test('Wi-Fi with an IPv6 address only is not called mobile data', () {
      expect(
        whyNoNetwork(const [
          (name: 'wlan0', ip: '2a00:1:2::9'),
          (name: 'rmnet_data0', ip: '10.1.2.3'),
        ]),
        NoNetwork.unknown,
      );
    });

    test('only a VPN: unknown', () {
      expect(
        whyNoNetwork(const [(name: 'tun0', ip: '10.8.0.2')]),
        NoNetwork.unknown,
      );
    });
  });
}
