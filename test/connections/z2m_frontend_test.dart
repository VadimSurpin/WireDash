import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/features/connections/discovery/z2m_frontend.dart';

// 2.7.2: where Zigbee2MQTT's web page says its broker is.
void main() {
  group('z2mMqttConfigOf', () {
    test('reads the mqtt section of bridge/info only', () {
      final info = jsonEncode({
        'topic': 'bridge/info',
        'payload': {
          'config': {
            'mqtt': {'server': 'mqtt://localhost:1883', 'user': 'z2m'},
          },
        },
      });
      expect(z2mMqttConfigOf(info), {
        'server': 'mqtt://localhost:1883',
        'user': 'z2m',
      });
      expect(
        z2mMqttConfigOf(jsonEncode({'topic': 'bridge/state', 'payload': {}})),
        isNull,
      );
      expect(z2mMqttConfigOf('not json'), isNull);
    });
  });

  group('z2mBrokerSetting', () {
    Z2mBrokerSetting? setting(String server, {String? user}) =>
        z2mBrokerSetting({
          'server': server,
          'user': ?user,
        }, frontendHost: '192.168.1.30');

    test('localhost is the web page\'s machine', () {
      final s = setting('mqtt://localhost:1883')!;
      expect(s.hosts, ['192.168.1.30']);
      expect(s.port, 1883);
      expect(s.tls, isFalse);
      expect(s.sameMachine, isTrue);
      expect(s.user, isNull);
    });

    test('Home Assistant\'s core-mosquitto counts as the same machine', () {
      expect(setting('mqtt://core-mosquitto:1883')!.sameMachine, isTrue);
    });

    test('another address is looked up there, with its port and user', () {
      final s = setting('mqtt://192.168.1.20:1884', user: 'zigbee')!;
      expect(s.hosts, ['192.168.1.20']);
      expect(s.port, 1884);
      expect(s.sameMachine, isFalse);
      expect(s.user, 'zigbee');
    });

    test('a Docker service name: this machine first, then the name', () {
      final s = setting('mqtt://mosquitto')!;
      expect(s.hosts, ['192.168.1.30', 'mosquitto']);
      expect(s.port, 1883);
      expect(s.sameMachine, isFalse);
    });

    test('mqtts defaults to 8883 over TLS', () {
      final s = setting('mqtts://broker.lan')!;
      expect(s.port, 8883);
      expect(s.tls, isTrue);
    });

    test('nothing usable', () {
      expect(setting('ws://broker.lan:9001'), isNull);
      expect(z2mBrokerSetting(null, frontendHost: 'x'), isNull);
      expect(z2mBrokerSetting({'server': ''}, frontendHost: 'x'), isNull);
    });
  });
}
