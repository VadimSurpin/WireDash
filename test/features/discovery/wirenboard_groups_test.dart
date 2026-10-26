import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/features/discovery/models/wirenboard_device.dart';
import 'package:wiredash/features/discovery/models/z2m_device.dart';
import 'package:wiredash/features/discovery/providers/discovery_provider.dart';
import 'package:wiredash/features/discovery/providers/wirenboard_discovery_provider.dart';

WirenBoardDevice device(String id, {String? driver, String? title}) =>
    WirenBoardDevice(
      id: id,
      metadata: {
        if (driver != null) 'driver': driver,
        if (title != null) 'title': {'en': title},
      },
      controls: const [],
    );

void main() {
  test(
    'controller services and requested legacy built-ins are grouped without hiding ordinary modules',
    () {
      for (final id in [
        'alarms',
        'battery',
        'cloud_status',
        'network_connections',
        'knx',
        'system_time',
        'system__cloud',
        'system__networks__eth0',
        'system__battery',
      ]) {
        expect(device(id).group, WirenBoardDeviceGroup.builtins, reason: id);
      }
      expect(
        device('cloud-provider', driver: 'wb-cloud-agent').isControllerBuiltin,
        isTrue,
      );
      expect(
        device('connections', driver: 'wb-nm-helper').isControllerBuiltin,
        isTrue,
      );
      expect(
        device('wb-msw-v3_42', title: 'Battery').group,
        WirenBoardDeviceGroup.modules,
      );
      expect(
        device('wb-mr6_10', title: 'Cloud status').group,
        WirenBoardDeviceGroup.modules,
      );
      expect(device('system_custom').isControllerBuiltin, isFalse);
    },
  );

  test(
    'driver metadata identifies both bridge generations without the native Z2M list',
    () {
      final discovery = WirenBoardDiscovery()
        ..apply('/devices/new/meta', '{"driver":"wb-mqtt-zigbee"}')
        ..apply('/devices/new/controls/state/meta', '{"type":"switch"}')
        ..apply('/devices/old/meta/driver', 'wb-zigbee2mqtt')
        ..apply('/devices/old/controls/state/meta/type', 'switch');
      for (final d in discovery.devices) {
        expect(d.group, WirenBoardDeviceGroup.z2m);
      }
    },
  );

  test(
    'legacy copies match native topic IDs and IEEE addresses, not display titles or other drivers',
    () {
      const native = [
        Z2mDevice(
          friendlyName: 'room/lamp',
          type: 'Router',
          ieeeAddress: '0x00158d0001234567',
        ),
        Z2mDevice(friendlyName: 'relay', type: 'Router'),
      ];
      final matched = classifyWirenBoardDevices([
        device('room_lamp', driver: 'wb-rules'),
        device('0x00158D0001234567'),
        device('relay', driver: 'wb-modbus'),
        device('other-module', title: 'room/lamp'),
        device('knx', driver: 'wb-mqtt-zigbee'),
      ], native);
      expect(matched.map((d) => d.group), [
        WirenBoardDeviceGroup.z2m,
        WirenBoardDeviceGroup.z2m,
        WirenBoardDeviceGroup.modules,
        WirenBoardDeviceGroup.modules,
        WirenBoardDeviceGroup.builtins,
      ]);
      final cached = WirenBoardDevice.fromJson(matched.first.toJson());
      expect(cached.isZ2mMirror, isTrue);
      expect(cached.metadata, matched.first.metadata);
    },
  );

  test(
    'late native discovery reclassifies the WB list without delaying or duplicating it',
    () async {
      final native = StreamController<List<Z2mDevice>>.broadcast();
      const args = (connectionId: 'c1', base: 'home/custom-z2m');
      final container = ProviderContainer(
        overrides: [
          wirenBoardDevicesProvider.overrideWith(
            (ref, _) => Stream.value([device('room_lamp'), device('sensor')]),
          ),
          bridgeDevicesStreamProvider.overrideWith((ref, actual) {
            expect(actual, args);
            return native.stream;
          }),
        ],
      );
      final subscription = container.listen(
        classifiedWirenBoardDevicesProvider(args),
        (_, __) {},
      );
      await Future<void>.delayed(Duration.zero);
      await container.pump();
      var result = container
          .read(classifiedWirenBoardDevicesProvider(args))
          .requireValue;
      expect(
        result.map((d) => d.group),
        everyElement(WirenBoardDeviceGroup.modules),
      );
      native.add(const [Z2mDevice(friendlyName: 'room/lamp', type: 'Router')]);
      await Future<void>.delayed(Duration.zero);
      await container.pump();
      result = container
          .read(classifiedWirenBoardDevicesProvider(args))
          .requireValue;
      expect(result, hasLength(2));
      expect(result.first.group, WirenBoardDeviceGroup.z2m);
      expect(result.last.group, WirenBoardDeviceGroup.modules);
      subscription.close();
      container.dispose();
      await native.close();
    },
  );
}
