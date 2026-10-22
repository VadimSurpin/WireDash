import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/features/discovery/models/z2m_device.dart';

// Fixture: a realistic bridge/devices payload with:
//   - an IKEA light (Router, light expose with state+brightness)
//   - an on/off plug (EndDevice, switch expose with binary state)
//   - a cover (EndDevice, cover expose with state+position)
//   - a contact sensor (EndDevice, top-level binary contact + numeric battery + linkquality)
//   - an enum-only device (EndDevice, top-level enum expose)
//   - a Coordinator (should be excluded)
const _bridgeDevicesJson = r'''
[
  {
    "friendly_name": "office_light",
    "type": "Router",
    "definition": {
      "vendor": "IKEA",
      "model": "LED1545G12",
      "exposes": [
        {
          "type": "light",
          "features": [
            { "type": "binary", "property": "state", "value_on": "ON", "value_off": "OFF" },
            { "type": "numeric", "property": "brightness", "value_min": 0, "value_max": 254 }
          ]
        }
      ]
    }
  },
  {
    "friendly_name": "kitchen_plug",
    "type": "EndDevice",
    "definition": {
      "vendor": "Tuya",
      "model": "TS0001",
      "exposes": [
        {
          "type": "switch",
          "features": [
            { "type": "binary", "property": "state", "value_on": "ON", "value_off": "OFF" }
          ]
        }
      ]
    }
  },
  {
    "friendly_name": "living_cover",
    "type": "Router",
    "definition": {
      "vendor": "Somfy",
      "model": "ZRTSI",
      "exposes": [
        {
          "type": "cover",
          "features": [
            { "type": "binary", "property": "state", "value_on": "OPEN", "value_off": "CLOSE" },
            { "type": "numeric", "property": "position", "value_min": 0, "value_max": 100 }
          ]
        }
      ]
    }
  },
  {
    "friendly_name": "door_sensor",
    "type": "EndDevice",
    "definition": {
      "vendor": "Aqara",
      "model": "MCCGQ11LM",
      "exposes": [
        { "type": "binary",  "property": "contact",     "value_on": false, "value_off": true },
        { "type": "numeric", "property": "battery",     "unit": "%"         },
        { "type": "numeric", "property": "linkquality"                       }
      ]
    }
  },
  {
    "friendly_name": "mode_switch",
    "type": "EndDevice",
    "definition": {
      "vendor": "Acme",
      "model": "XY-99",
      "exposes": [
        { "type": "enum", "property": "mode", "values": ["auto", "manual", "off"] }
      ]
    }
  },
  {
    "friendly_name": "Coordinator",
    "type": "Coordinator"
  }
]
''';

// Malformed JSON
const _badJson = 'not json at all {{}}';

// Device with no definition field
const _noDefinitionJson = r'''
[
  { "friendly_name": "bare_device", "type": "EndDevice" }
]
''';

void main() {
  group('parseBridgeDevices', () {
    test('excludes Coordinator; returns 5 devices', () {
      final devices = parseBridgeDevices(_bridgeDevicesJson);
      expect(devices.length, 5);
      expect(devices.any((d) => d.type == 'Coordinator'), isFalse);
    });

    test('parses office_light fields correctly', () {
      final devices = parseBridgeDevices(_bridgeDevicesJson);
      final light = devices.firstWhere((d) => d.friendlyName == 'office_light');
      expect(light.vendor, 'IKEA');
      expect(light.model, 'LED1545G12');
      expect(light.type, 'Router');
    });

    test('flattens composite light exposes into Z2mExpose list', () {
      final devices = parseBridgeDevices(_bridgeDevicesJson);
      final light = devices.firstWhere((d) => d.friendlyName == 'office_light');
      // composite light expose itself + 2 features flattened
      // We keep the parent type too so suggestPanel can match on "light"
      expect(light.exposes.any((e) => e.type == 'light'), isTrue);
      expect(light.exposes.any((e) => e.property == 'brightness'), isTrue);
      expect(
        light.exposes.any((e) => e.property == 'state' && e.type == 'binary'),
        isTrue,
      );
    });

    test('parses top-level binary expose with valueOn', () {
      final devices = parseBridgeDevices(_bridgeDevicesJson);
      final sensor = devices.firstWhere((d) => d.friendlyName == 'door_sensor');
      final contact = sensor.exposes.firstWhere((e) => e.property == 'contact');
      expect(contact.type, 'binary');
      // Zigbee2MQTT marks open as the "on" state: value_on is false.
      expect(contact.valueOn, 'false'); // boolean false → "false"
    });

    test('parses numeric expose with unit', () {
      final devices = parseBridgeDevices(_bridgeDevicesJson);
      final sensor = devices.firstWhere((d) => d.friendlyName == 'door_sensor');
      final battery = sensor.exposes.firstWhere((e) => e.property == 'battery');
      expect(battery.type, 'numeric');
      expect(battery.unit, '%');
    });

    test('parses enum expose property', () {
      final devices = parseBridgeDevices(_bridgeDevicesJson);
      final mode = devices.firstWhere((d) => d.friendlyName == 'mode_switch');
      final modeExpose = mode.exposes.firstWhere((e) => e.property == 'mode');
      expect(modeExpose.type, 'enum');
    });

    test('device with no definition yields empty exposes, no crash', () {
      final devices = parseBridgeDevices(_noDefinitionJson);
      expect(devices.length, 1);
      expect(devices.first.friendlyName, 'bare_device');
      expect(devices.first.exposes, isEmpty);
      expect(devices.first.vendor, isNull);
      expect(devices.first.model, isNull);
    });

    // 2.10.3: a generated definition is reported as unsupported by
    // Zigbee2MQTT but exposes working controls.
    test('a generated definition is unsupported to Z2M but usable here', () {
      final devices = parseBridgeDevices(r'''
[
  {
    "friendly_name": "esp_lamp",
    "type": "Router",
    "ieee_address": "0x1234567890abcdef",
    "supported": false,
    "definition": {
      "vendor": "Espressif",
      "model": "ZBLightBulb",
      "source": "generated",
      "exposes": [
        {"type": "switch", "features": [
          {"type": "binary", "name": "state", "property": "state",
           "access": 7, "value_on": "ON", "value_off": "OFF"}
        ]}
      ]
    }
  }
]
''');
      final lamp = devices.single;
      expect(lamp.supported, isFalse);
      expect(lamp.generated, isTrue);
      expect(lamp.usable, isTrue);
      expect(lamp.exposes.map((e) => e.type), contains('switch'));
    });

    test('malformed JSON returns empty list without throwing', () {
      final devices = parseBridgeDevices(_badJson);
      expect(devices, isEmpty);
    });

    test('empty array returns empty list', () {
      final devices = parseBridgeDevices('[]');
      expect(devices, isEmpty);
    });
  });

  // 2.7.1: devices never named in Zigbee2MQTT.
  group('displayName', () {
    test('a named device keeps its name', () {
      const d = Z2mDevice(
        friendlyName: 'Bedroom',
        type: 'EndDevice',
        description: 'Motion sensor',
        ieeeAddress: '0xa4c13836276df66f',
      );
      expect(d.displayName, 'Bedroom');
    });

    test('an unnamed device says what it is, with the last four digits', () {
      final d = parseBridgeDevices('''[{
        "friendly_name": "0xa4c13836276df66f",
        "ieee_address": "0xa4c13836276df66f",
        "type": "EndDevice",
        "definition": {"model": "ZG-204Z", "vendor": "HOBEIAN",
          "description": "Motion sensor", "exposes": []}
      }]''').single;
      expect(d.description, 'Motion sensor');
      expect(d.displayName, 'Motion sensor f66f');
    });

    test('falls back to the model, then to the address', () {
      const model = Z2mDevice(
        friendlyName: '0xa4c13836276df66f',
        type: 'EndDevice',
        model: 'ZG-204Z',
      );
      expect(model.displayName, 'ZG-204Z f66f');
      const bare = Z2mDevice(
        friendlyName: '0xa4c13836276df66f',
        type: 'EndDevice',
      );
      expect(bare.displayName, '0xa4c13836276df66f');
    });
  });
}
