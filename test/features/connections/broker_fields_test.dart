import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/data/database/tables/connections.dart';
import 'package:zigdash/features/connections/widgets/broker_fields.dart';

/// Runs [tidyBrokerAddress] on a host/port pair; returns host, port, protocol.
(String, String, MqttProtocol) tidy(
  String host,
  String port, [
  MqttProtocol protocol = MqttProtocol.tcp,
]) {
  final h = TextEditingController(text: host);
  final p = TextEditingController(text: port);
  var proto = protocol;
  tidyBrokerAddress(
    host: h,
    port: p,
    protocol: protocol,
    onProtocol: (v) => proto = v,
  );
  return (h.text, p.text, proto);
}

void main() {
  group('tidyBrokerAddress', () {
    test('a Home Assistant link becomes its host on the broker port', () {
      expect(tidy('http://192.168.68.52:8123', '1883'), (
        '192.168.68.52',
        '1883',
        MqttProtocol.tcp,
      ));
      expect(tidy('https://homeassistant.local:8123/lovelace/0', '1883'), (
        'homeassistant.local',
        '1883',
        MqttProtocol.tcp,
      ));
    });

    test('the case seen on a phone: link host and 8123 typed as port', () {
      expect(tidy('http://192.168.68.52', '8123'), (
        '192.168.68.52',
        '1883',
        MqttProtocol.tcp,
      ));
    });

    test('8123 in the port field is never a broker', () {
      expect(tidy('192.168.1.20', '8123'), (
        '192.168.1.20',
        '1883',
        MqttProtocol.tcp,
      ));
      expect(tidy('192.168.1.20', '8123', MqttProtocol.tcpSsl), (
        '192.168.1.20',
        '8883',
        MqttProtocol.tcpSsl,
      ));
    });

    test('a broker port typed with the host moves to the port field', () {
      expect(tidy('192.168.1.20:1884', '1883'), (
        '192.168.1.20',
        '1884',
        MqttProtocol.tcp,
      ));
      expect(tidy('mqtts://broker.example.com:8883', '1883'), (
        'broker.example.com',
        '8883',
        MqttProtocol.tcpSsl,
      ));
    });

    test('a web port typed with the host is swapped for the broker port', () {
      expect(tidy('homeassistant.local:8123', '1883'), (
        'homeassistant.local',
        '1883',
        MqttProtocol.tcp,
      ));
      expect(tidy('http://192.168.1.20', '80'), (
        '192.168.1.20',
        '1883',
        MqttProtocol.tcp,
      ));
    });

    test('plain hosts and unusual ports are left alone', () {
      expect(tidy('192.168.1.20', '1883'), (
        '192.168.1.20',
        '1883',
        MqttProtocol.tcp,
      ));
      expect(tidy('Broker.Local', '8080'), (
        'Broker.Local',
        '8080',
        MqttProtocol.tcp,
      ));
      expect(tidy(' 192.168.1.20 ', '1883'), (
        '192.168.1.20',
        '1883',
        MqttProtocol.tcp,
      ));
    });

    test('WebSocket connections are untouched', () {
      expect(tidy('http://192.168.1.20:8123', '9001', MqttProtocol.ws), (
        'http://192.168.1.20:8123',
        '9001',
        MqttProtocol.ws,
      ));
    });
  });
}
