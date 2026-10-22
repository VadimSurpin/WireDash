import 'dart:convert';

import 'z2m_device.dart';

enum WirenBoardDeviceGroup { modules, z2m, builtins }

/// Retained metadata from the Wiren Board MQTT conventions. Values and
/// commands live on separate topics and are deliberately not used as metadata.
class WirenBoardDiscovery {
  final _devices = <String, _Metadata>{};
  final _controls = <String, Map<String, _Metadata>>{};

  /// Returns whether a valid metadata update was applied. Malformed messages
  /// leave the last good metadata intact; an empty payload removes metadata.
  bool apply(String topic, String payload) {
    final parts = topic.split('/');
    if (parts.length < 4 ||
        parts[0] != '' ||
        parts[1] != 'devices' ||
        parts[2].isEmpty) {
      return false;
    }
    final device = parts[2];
    final isDevice = parts[3] == 'meta' && parts.length <= 5;
    final isControl =
        parts.length >= 6 &&
        parts.length <= 7 &&
        parts[3] == 'controls' &&
        parts[4].isNotEmpty &&
        parts[5] == 'meta';
    if (!isDevice && !isControl) return false;
    final key = parts.length == (isDevice ? 4 : 6) ? null : parts.last;
    // Error topics describe runtime health, not discovery metadata.
    if (key == 'error') return false;
    Object? value;
    if (payload.isNotEmpty) {
      if (key == null) {
        try {
          value = jsonDecode(payload);
        } on FormatException {
          return false;
        }
        if (value is! Map<String, dynamic>) return false;
      } else {
        // Legacy scalar subtopics are plain strings (readonly may be 0/1).
        value = payload;
      }
    }
    final metadata = isDevice
        ? _devices.putIfAbsent(device, _Metadata.new)
        : _controls
              .putIfAbsent(device, () => {})
              .putIfAbsent(parts[4], _Metadata.new);
    metadata.update(key, value);
    return true;
  }

  List<WirenBoardDevice> get devices {
    final result = <WirenBoardDevice>[];
    for (final entry in _controls.entries) {
      final controls = <WirenBoardControl>[];
      for (final control in entry.value.entries) {
        final meta = control.value.values;
        if (meta['type'] is! String ||
            (meta['type'] as String).isEmpty ||
            _flag(meta['hidden'])) {
          continue;
        }
        controls.add(
          WirenBoardControl(
            deviceId: entry.key,
            id: control.key,
            metadata: meta,
          ),
        );
      }
      controls.sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
      });
      if (controls.isNotEmpty) {
        result.add(
          WirenBoardDevice(
            id: entry.key,
            metadata: _devices[entry.key]?.values ?? const {},
            controls: List.unmodifiable(controls),
          ),
        );
      }
    }
    result.sort((a, b) => a.id.compareTo(b.id));
    return List.unmodifiable(result);
  }
}

class _Metadata {
  Map<String, Object?> _json = {};
  final _legacy = <String, Object?>{};

  void update(String? key, Object? value) {
    if (key == null) {
      _json = value == null ? {} : Map<String, Object?>.from(value as Map);
    } else if (value == null) {
      _legacy.remove(key);
    } else {
      _legacy[key] = value;
    }
  }

  // Canonical JSON takes precedence regardless of retained delivery order.
  Map<String, Object?> get values => Map.unmodifiable({..._legacy, ..._json});
}

bool _flag(Object? value) =>
    value == true || value == 1 || value == '1' || value == 'true';

double? _number(Object? value) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  return parsed != null && parsed.isFinite ? parsed : null;
}

String wirenBoardTitle(Object? title, String language, String fallback) {
  if (title is Map) {
    for (final key in [language, 'en', 'ru']) {
      final text = title[key];
      if (text is String && text.trim().isNotEmpty) return text;
    }
    for (final text in title.values) {
      if (text is String && text.trim().isNotEmpty) return text;
    }
  }
  return title is String && title.trim().isNotEmpty ? title : fallback;
}

class WirenBoardDevice {
  const WirenBoardDevice({
    required this.id,
    required this.metadata,
    required this.controls,
    this.z2mMirror = false,
  });
  final String id;
  final Map<String, Object?> metadata;
  final List<WirenBoardControl> controls;

  /// Identity confirmed against the native bridge list (legacy converters).
  final bool z2mMirror;

  bool get isZ2mMirror =>
      z2mMirror ||
      const {'wb-mqtt-zigbee', 'wb-zigbee2mqtt'}.contains(metadata['driver']);

  WirenBoardDeviceGroup get group => isControllerBuiltin
      ? WirenBoardDeviceGroup.builtins
      : isZ2mMirror
      ? WirenBoardDeviceGroup.z2m
      : WirenBoardDeviceGroup.modules;

  WirenBoardDevice withZ2mMirror(bool matched) => WirenBoardDevice(
    id: id,
    metadata: metadata,
    controls: controls,
    z2mMirror: matched,
  );

  /// Match standard controller device IDs exactly. External Modbus modules
  /// also commonly start with `wb-`, so a prefix match misclassifies them.
  bool get isControllerBuiltin =>
      id.startsWith('system__') ||
      const {'wb-cloud-agent', 'wb-nm-helper'}.contains(metadata['driver']) ||
      const {
        'alarms',
        'battery',
        'cloud_status',
        'network_connections',
        'knx',
        'system_time',
        'buzzer',
        'hwmon',
        'network',
        'power_status',
        'system',
        'metrics',
        'wb-adc',
        'wb-dac',
        'wb-gpio',
        'wb-w1',
        'wb-mcu',
        'wb-v1',
        'wbrules',
      }.contains(id);

  Map<String, dynamic> toJson() => {
    'id': id,
    'metadata': metadata,
    'controls': [for (final control in controls) control.toJson()],
    if (z2mMirror) 'z2mMirror': true,
  };

  factory WirenBoardDevice.fromJson(
    Map<String, dynamic> json,
  ) => WirenBoardDevice(
    id: json['id'] as String,
    metadata: Map<String, Object?>.from(json['metadata'] as Map? ?? const {}),
    z2mMirror: json['z2mMirror'] == true,
    controls: [
      for (final control in json['controls'] as List? ?? const [])
        WirenBoardControl.fromJson(Map<String, dynamic>.from(control as Map)),
    ],
  );

  String title(String language) => wirenBoardTitle(
    metadata['title'],
    language,
    metadata['name'] is String ? metadata['name'] as String : id,
  );
}

class WirenBoardControl {
  const WirenBoardControl({
    required this.deviceId,
    required this.id,
    required this.metadata,
  });
  final String deviceId;
  final String id;
  final Map<String, Object?> metadata;

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'id': id,
    'metadata': metadata,
  };

  factory WirenBoardControl.fromJson(Map<String, dynamic> json) =>
      WirenBoardControl(
        deviceId: json['deviceId'] as String,
        id: json['id'] as String,
        metadata: Map<String, Object?>.from(json['metadata'] as Map),
      );

  String get topic => '/devices/$deviceId/controls/$id';
  String get type => metadata['type'] as String;
  bool get readOnly => _flag(metadata['readonly']) || type == 'alarm';
  double get order => _number(metadata['order']) ?? 0;
  double? get min => _number(metadata['min']);
  double? get max => _number(metadata['max']);
  double? get precision => _number(metadata['precision']);
  Map<String, Object?> get choices => metadata['enum'] is Map
      ? Map<String, Object?>.from(metadata['enum'] as Map)
      : const {};
  String title(String language) => wirenBoardTitle(
    metadata['title'],
    language,
    metadata['name'] is String ? metadata['name'] as String : id,
  );

  String? get unit => metadata['units'] is String
      ? metadata['units'] as String
      : _legacyUnits[type];

  bool get numeric =>
      type == 'value' || type == 'range' || _legacyUnits.containsKey(type);

  static const _legacyUnits = {
    'temperature': '°C',
    'rel_humidity': '%',
    'atmospheric_pressure': 'mbar',
    'rainfall': 'mm/h',
    'wind_speed': 'm/s',
    'power': 'W',
    'power_consumption': 'kWh',
    'voltage': 'V',
    'water_flow': 'm³/h',
    'water_consumption': 'm³',
    'resistance': 'Ω',
    'concentration': 'ppm',
    'heat_power': 'Gcal/h',
    'heat_energy': 'Gcal',
    'current': 'A',
    'pressure': 'bar',
    'lux': 'lx',
    'sound_level': 'dB',
  };
}

/// New bridges identify their driver. The legacy wb-rules converter uses the
/// native friendly name with its first slash replaced by an underscore.
/// Match topic IDs, never translated display titles or a broad `wb-` prefix.
List<WirenBoardDevice> classifyWirenBoardDevices(
  List<WirenBoardDevice> devices,
  List<Z2mDevice> nativeDevices,
) {
  final names = {
    for (final d in nativeDevices)
      if (d.friendlyName.isNotEmpty) d.friendlyName.replaceFirst('/', '_'),
  };
  final addresses = {
    for (final d in nativeDevices)
      if (d.ieeeAddress != null) d.ieeeAddress!.toLowerCase(),
  };
  return devices
      .map((device) {
        if (device.isControllerBuiltin || device.isZ2mMirror) return device;
        final driver = device.metadata['driver'];
        if (driver != null && driver != '' && driver != 'wb-rules') {
          return device;
        }
        final ieee = device.metadata['ieee_address']?.toString().toLowerCase();
        final matched =
            names.contains(device.id) ||
            addresses.contains(device.id.toLowerCase()) ||
            (ieee != null && addresses.contains(ieee));
        return matched ? device.withZ2mMirror(true) : device;
      })
      .toList(growable: false);
}
