import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/features/discovery/models/z2m_device.dart';
import 'package:wiredash/features/ha_import/ha_registry.dart';

// Shaped like the user's Home Assistant 2026.1.1 on 2026-10-16 (see
// docs/design/ha-import.md, "Checked on a real Home Assistant"): three
// motion sensors, the bridge, a shutter Zigbee2MQTT removed long ago, rooms
// with Hebrew names, one floor, and a room set only on a device's entities.
Map<String, Object?> _dev(
  String id,
  String ident, {
  String? name,
  String? byUser,
  String? area,
  String? parent,
  String domain = 'mqtt',
}) => {
  'id': id,
  'identifiers': [
    [domain, ident],
  ],
  'name': name,
  'name_by_user': byUser,
  'area_id': area,
  'parent_device_id': parent,
  'config_entries': ['01KJQDAXG9DJVSZYAQWS4XMRYN'],
  'connections': <Object?>[],
  'model': 'Motion sensor',
  'model_id': 'ZG-204Z',
};

final _registry = HaRegistry.fromLists(
  devices: [
    _dev('shutter', 'zigbee2mqtt_0xc02cedfffec08aa5', name: 'תריס חדר עבודה'),
    _dev(
      'bridge',
      'zigbee2mqtt_bridge_0x00be44fffe70c427',
      name: 'Zigbee2MQTT Bridge',
      area: 'khdr_hvrym',
    ),
    _dev(
      'living',
      'zigbee2mqtt_0xa4c13836276df66f',
      name: '0xa4c13836276df66f',
      byUser: 'Living room motion',
      area: 'living_room',
    ),
    _dev(
      'kitchen',
      'zigbee2mqtt_0xa4c13828d7b8e8a1',
      name: '0xa4c13828d7b8e8a1',
      byUser: 'Kitchen motion',
      area: 'kitchen',
    ),
    _dev(
      'bedroom',
      'zigbee2mqtt_0xa4c13863521bcd41',
      name: '0xa4c13863521bcd41',
      byUser: 'Bedroom motion',
    ),
    _dev(
      'group',
      'zigbee2mqtt_1221051039810110150109113116116_5',
      name: 'All lights',
    ),
  ],
  areas: [
    {
      'area_id': 'living_room',
      'name': 'Living Room',
      'floor_id': 'ground_floor',
    },
    {'area_id': 'kitchen', 'name': 'Kitchen', 'floor_id': 'ground_floor'},
    {'area_id': 'bedroom', 'name': 'Bedroom', 'floor_id': null},
    {'area_id': 'khdr_hvrym', 'name': 'חדר הורים', 'floor_id': null},
  ],
  floors: [
    {'floor_id': 'ground_floor', 'name': 'Ground floor', 'level': 0},
  ],
  entitiesForDisplay: {
    'entity_categories': {},
    'entities': [
      {
        'ei': 'binary_sensor.0xa4c13863521bcd41_occupancy',
        'di': 'bedroom',
        'ai': 'bedroom',
      },
      {
        'ei': 'sensor.0xa4c13863521bcd41_battery',
        'di': 'bedroom',
        'ai': 'bedroom',
      },
      {'ei': 'binary_sensor.0xa4c13836276df66f_occupancy', 'di': 'living'},
    ],
  },
);

Z2mDevice _z2m(String ieee) => Z2mDevice(
  friendlyName: ieee,
  type: 'EndDevice',
  ieeeAddress: ieee,
  model: 'ZG-204Z',
  description: 'Motion sensor',
);

final _z2mDevices = [
  _z2m('0xa4c13836276df66f'),
  _z2m('0xa4c13828d7b8e8a1'),
  _z2m('0xa4c13863521bcd41'),
];

void main() {
  test('Zigbee2MQTT devices are known by their address; bridge and groups '
      'are not devices', () {
    final ieee = {for (final d in _registry.devices) d.id: d.z2mIeee};
    expect(ieee['living'], '0xa4c13836276df66f');
    expect(ieee['bridge'], isNull);
    expect(ieee['group'], isNull);
  });

  test('a dashboard per floor, a section per room, the rest last', () {
    final plan = planImport(_registry, _z2mDevices);
    expect(plan.dashboards.map((d) => d.floor), ['Ground floor', null]);
    final ground = plan.dashboards.first;
    expect(ground.rooms.map((r) => r.name), ['Kitchen', 'Living Room']);
    expect(ground.rooms.first.devices.single.name, 'Kitchen motion');
    expect(plan.matched, 3);
    expect(plan.rooms, 3);
    expect(plan.zhaOnly, isFalse);
  });

  test('a room set only on the entities counts', () {
    final noFloor = planImport(_registry, _z2mDevices).dashboards.last;
    expect(noFloor.rooms.single.name, 'Bedroom');
    expect(noFloor.rooms.single.devices.single.name, 'Bedroom motion');
  });

  test('devices Zigbee2MQTT no longer has are not imported', () {
    final plan = planImport(_registry, _z2mDevices);
    final names = [
      for (final d in plan.dashboards)
        for (final r in d.rooms)
          for (final x in r.devices) x.name,
    ];
    expect(names, isNot(contains('תריס חדר עבודה')));
  });

  test('no floors: one dashboard; no area: a section without a name', () {
    final plan = planImport(
      HaRegistry.fromLists(
        devices: [
          _dev(
            'a',
            'zigbee2mqtt_0xa4c13836276df66f',
            byUser: 'Hall',
            area: 'hall',
          ),
          _dev(
            'b',
            'zigbee2mqtt_0xa4c13828d7b8e8a1',
            name: '0xa4c13828d7b8e8a1',
          ),
        ],
        areas: [
          {'area_id': 'hall', 'name': 'Hall'},
        ],
      ),
      _z2mDevices,
    );
    expect(plan.dashboards.single.floor, isNull);
    expect(plan.dashboards.single.rooms.map((r) => r.name), ['Hall', null]);
    // Named nowhere: the device's own readable name.
    expect(
      plan.dashboards.single.rooms.last.devices.single.name,
      'Motion sensor e8a1',
    );
  });

  test('child devices are skipped; a device listed twice counts once', () {
    final plan = planImport(
      HaRegistry.fromLists(
        devices: [
          _dev('a', 'zigbee2mqtt_0xa4c13836276df66f', byUser: 'One'),
          _dev('a2', 'zigbee2mqtt_0xa4c13836276df66f', byUser: 'Again'),
          _dev(
            'c',
            'zigbee2mqtt_0xa4c13828d7b8e8a1',
            byUser: 'Child',
            parent: 'a',
          ),
        ],
        areas: const [],
      ),
      _z2mDevices,
    );
    expect(plan.matched, 1);
  });

  test('ZHA only: nothing to import, and the plan says why', () {
    final plan = planImport(
      HaRegistry.fromLists(
        devices: [
          _dev('z', '84:fd:27:ff:fe:6d:2f:80', name: 'Lamp', domain: 'zha'),
        ],
        areas: const [],
      ),
      _z2mDevices,
    );
    expect(plan.matched, 0);
    expect(plan.zhaOnly, isTrue);
  });

  test('odd shapes are skipped, not fatal', () {
    final registry = HaRegistry.fromLists(
      devices: [
        {'identifiers': 'nope'},
        {
          'id': 'x',
          'identifiers': [
            ['mqtt'],
          ],
        },
        null,
      ],
      areas: [
        {'area_id': 3},
      ],
      floors: null,
      entitiesForDisplay: {'entities': 'nope'},
    );
    expect(registry.devices.single.z2mIeee, isNull);
    expect(registry.areas, isEmpty);
    expect(planImport(registry, _z2mDevices).dashboards, isEmpty);
  });
}
