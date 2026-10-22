import 'dart:convert';

/// A single expose entry — either a top-level (non-composite) expose or a
/// flattened feature from inside a composite expose (light/switch/cover).
///
/// [type]     — "binary" | "numeric" | "enum" | "light" | "switch" | "cover" | ...
/// [property] — MQTT JSON key (e.g. "state", "brightness", "contact").
/// [unit]     — optional unit string (e.g. "%").
/// [valueOn]  — for binary exposes, the "on" value serialised as a string
///              (e.g. "ON" or "true").
/// [access]   — Z2M access bitmask: bit 0 (1) published in state, bit 1 (2)
///              settable via `<device>/set`, bit 2 (4) gettable. Defaults to 0
///              when absent (e.g. composite parents carry no access of their own).
class Z2mExpose {
  /// Z2M access bit: the property can be written via `<device>/set`.
  static const int accessSet = 0x02;

  final String type;
  final String? property;
  final String? unit;
  final String? valueOn;
  final int access;

  const Z2mExpose({
    required this.type,
    this.property,
    this.unit,
    this.valueOn,
    this.access = 0,
  });

  /// True when this property can be written via `<device>/set`.
  bool get isSettable => property != null && (access & accessSet) != 0;

  factory Z2mExpose._fromMap(Map<String, dynamic> map) {
    final rawValueOn = map['value_on'];
    final String? valueOn;
    if (rawValueOn == null) {
      valueOn = null;
    } else if (rawValueOn is bool) {
      valueOn = rawValueOn.toString(); // true → "true"
    } else {
      valueOn = rawValueOn.toString();
    }

    final rawAccess = map['access'];
    final access = rawAccess is int
        ? rawAccess
        : (rawAccess is num ? rawAccess.toInt() : 0);

    return Z2mExpose(
      type: (map['type'] as String?) ?? 'unknown',
      property: map['property'] as String?,
      unit: map['unit'] as String?,
      valueOn: valueOn,
      access: access,
    );
  }
}

/// A Zigbee2MQTT device parsed from the `bridge/devices` payload.
///
/// [exposes] is a *flattened* list: composite exposes (light/switch/cover)
/// include the parent entry **and** each of its features, so callers can
/// match both the composite type ("light") and individual properties
/// ("brightness").
class Z2mDevice {
  final String friendlyName;
  final String type; // "Router" | "EndDevice" | "Coordinator"
  final String? vendor;
  final String? model;
  final List<Z2mExpose> exposes;

  /// False when Z2M has no converter for the device. Defaults to true: older
  /// payloads and hand-built fixtures omit the flag and mean "works fine".
  final bool supported;

  /// `definition.source == "generated"` (2.10.3): Zigbee2MQTT had no
  /// converter and built a definition from the device's clusters. It
  /// reports such a device as `supported: false`, yet the definition works
  /// (a custom ESP32 lamp switched fine from Zigbee2MQTT and Home Assistant
  /// while ZigDash called it unsupported).
  final bool generated;

  /// Whether there is anything to offer: a converter, or a generated
  /// definition that exposes something. What the review, the tile picker
  /// and the device page go by, instead of [supported] alone.
  bool get usable => supported || generated || exposes.isNotEmpty;

  /// The device's IEEE address, its stable identity across renames. Null
  /// only in hand-built fixtures.
  final String? ieeeAddress;

  /// `definition.exposes` as received, for device-tile classification
  /// (keeps categories, endpoints and nesting that [exposes] flattens away).
  final List<Object?> rawExposes;

  /// `power_source`, e.g. "Battery" or "Mains (single phase)".
  final String? powerSource;

  /// `interview_state` (Zigbee2MQTT 2.3+): PENDING, IN_PROGRESS, SUCCESSFUL
  /// or FAILED. Null on older bridges.
  final String? interviewState;

  bool get interviewFailed => interviewState == 'FAILED';

  /// `definition.description`, what the device is: "Motion sensor".
  final String? description;

  /// The name to show and to give new tiles: the friendly name, or for a
  /// device never named in Zigbee2MQTT (still called by its IEEE address)
  /// what it is plus the address's last four digits, "Motion sensor f66f"
  /// (2.7.1). Names given in Home Assistant never reach MQTT.
  String get displayName => displayNameOf(friendlyName);

  /// [displayName] as it reads when this device is called [name].
  String displayNameOf(String name) {
    final what = description ?? model;
    if (what == null || what.isEmpty || !_ieeeName.hasMatch(name)) {
      return name;
    }
    return '$what ${name.substring(name.length - 4)}';
  }

  const Z2mDevice({
    required this.friendlyName,
    required this.type,
    this.vendor,
    this.model,
    this.exposes = const [],
    this.supported = true,
    this.generated = false,
    this.ieeeAddress,
    this.rawExposes = const [],
    this.powerSource,
    this.interviewState,
    this.description,
  });
}

final _ieeeName = RegExp(r'^0x[0-9a-fA-F]{16}$');

/// Parses the `zigbee2mqtt/bridge/devices` retained JSON payload.
///
/// Returns an empty list on malformed JSON rather than throwing.
/// Coordinators are excluded from the result.
List<Z2mDevice> parseBridgeDevices(String jsonString) {
  try {
    final decoded = jsonDecode(jsonString);
    if (decoded is! List) return [];

    final result = <Z2mDevice>[];

    for (final item in decoded) {
      final map = item as Map<String, dynamic>?;
      if (map == null) continue;

      final deviceType = (map['type'] as String?) ?? '';
      if (deviceType == 'Coordinator') continue;

      final friendlyName = (map['friendly_name'] as String?) ?? '';
      final supported = map['supported'] != false;

      final definition = map['definition'] as Map<String, dynamic>?;
      final vendor = definition?['vendor'] as String?;
      final model = definition?['model'] as String?;

      final rawExposes = definition?['exposes'] as List<dynamic>? ?? [];
      final exposes = _flattenExposes(rawExposes);

      result.add(
        Z2mDevice(
          friendlyName: friendlyName,
          type: deviceType,
          vendor: vendor,
          model: model,
          exposes: exposes,
          supported: supported,
          generated: definition?['source'] == 'generated',
          ieeeAddress: map['ieee_address'] as String?,
          rawExposes: rawExposes,
          powerSource: map['power_source'] as String?,
          interviewState: map['interview_state'] as String?,
          description: definition?['description'] as String?,
        ),
      );
    }

    return result;
  } catch (_) {
    return [];
  }
}

/// Flattens the `exposes` array from a device definition.
///
/// Composite exposes (those with a `features` list, e.g. light/switch/cover)
/// produce the parent entry *plus* each flattened feature.  Top-level
/// (non-composite) exposes produce a single entry each.
List<Z2mExpose> _flattenExposes(List<dynamic> rawExposes) {
  final result = <Z2mExpose>[];

  for (final raw in rawExposes) {
    final map = raw as Map<String, dynamic>?;
    if (map == null) continue;

    final features = map['features'] as List<dynamic>?;

    if (features != null && features.isNotEmpty) {
      // Composite expose: add the parent (so we can match on e.g. "light")
      result.add(Z2mExpose._fromMap(map));
      // Then add each child feature
      for (final feat in features) {
        final featMap = feat as Map<String, dynamic>?;
        if (featMap != null) {
          result.add(Z2mExpose._fromMap(featMap));
        }
      }
    } else {
      // Top-level (non-composite) expose
      result.add(Z2mExpose._fromMap(map));
    }
  }

  return result;
}
