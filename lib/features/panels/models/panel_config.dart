import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;
import 'cover_controls.dart';
export 'cover_controls.dart';

import '../../../data/database/tables/panels.dart';
import '../../devices/device_profile.dart';
import '../../discovery/models/wirenboard_device.dart';

/// Type-specific configuration stored as JSON in `Panels.config`. Decoded
/// on the fly in panel widgets. Refactor to a freezed sealed union once
/// the panel-type catalogue gets bigger than three.
sealed class PanelConfig {
  const PanelConfig();

  /// Incoming display formatting; never used for outgoing commands.
  String? get valueExpression => null;

  String encode() => json.encode(toJson());

  Map<String, dynamic> toJson();

  static PanelConfig decode(PanelType type, String raw) {
    final j = json.decode(raw) as Map<String, dynamic>;
    return switch (type) {
      PanelType.button => ButtonConfig.fromJson(j),
      PanelType.toggle => ToggleConfig.fromJson(j),
      PanelType.slider => SliderConfig.fromJson(j),
      PanelType.led => LedConfig.fromJson(j),
      PanelType.nodeStatus => NodeStatusConfig.fromJson(j),
      PanelType.progress => ProgressConfig.fromJson(j),
      PanelType.multiState ||
      PanelType.combo ||
      PanelType.radio => OptionsConfig.fromJson(j),
      PanelType.cover => CoverConfig.fromJson(j),
      PanelType.textInput => TextInputConfig.fromJson(j),
      PanelType.textLog => TextLogConfig.fromJson(j),
      PanelType.schedule => ScheduleConfig.fromJson(j),
      PanelType.scene => SceneConfig.fromJson(j),
      PanelType.autoClose => AutoCloseConfig.fromJson(j),
      PanelType.device =>
        j['protocol'] == 'wirenboard'
            ? WirenBoardDeviceConfig.fromJson(j)
            : DeviceTileConfig.fromJson(j),
      PanelType.reading => ReadingConfig.fromJson(j),
    };
  }

  static PanelConfig defaultFor(PanelType type) => switch (type) {
    PanelType.button => const ButtonConfig(payload: 'PRESS'),
    PanelType.toggle => const ToggleConfig(),
    PanelType.slider => const SliderConfig(),
    PanelType.led => const LedConfig(),
    PanelType.nodeStatus => const NodeStatusConfig(),
    PanelType.progress => const ProgressConfig(),
    PanelType.multiState ||
    PanelType.combo ||
    PanelType.radio => OptionsConfig.coverDefault(),
    PanelType.cover => const CoverConfig(),
    PanelType.textInput => const TextInputConfig(),
    PanelType.textLog => const TextLogConfig(),
    PanelType.schedule => const ScheduleConfig(),
    PanelType.scene => const SceneConfig(),
    PanelType.autoClose => AutoCloseConfig(),
    PanelType.device => const DeviceTileConfig(
      profile: DeviceProfile(deviceClass: DeviceClass.generic, features: []),
    ),
    PanelType.reading => const ReadingConfig(),
  };
}

class ButtonConfig extends PanelConfig {
  const ButtonConfig({
    required this.payload,
    this.colorArgb,
    this.iconCodepoint,
    this.isJson = false,
  });

  final String payload;
  final int? colorArgb;
  final int? iconCodepoint;
  final bool isJson;

  @override
  Map<String, dynamic> toJson() => {
    'payload': payload,
    if (colorArgb != null) 'color': colorArgb,
    if (iconCodepoint != null) 'icon': iconCodepoint,
    'isJson': isJson,
  };

  static ButtonConfig fromJson(Map<String, dynamic> j) => ButtonConfig(
    payload: j['payload'] as String? ?? 'PRESS',
    colorArgb: j['color'] as int?,
    iconCodepoint: j['icon'] as int?,
    isJson: j['isJson'] as bool? ?? false,
  );
}

class ToggleConfig extends PanelConfig {
  const ToggleConfig({
    this.valueExpression,
    this.onPayload = '{"state":"ON"}',
    this.offPayload = '{"state":"OFF"}',
    this.jsonPath = 'state',
    this.onMatch = 'ON',
    this.onIconCodepoint,
    this.offIconCodepoint,
  });

  @override
  final String? valueExpression;

  final String onPayload;
  final String offPayload;
  final String? jsonPath;
  final String onMatch;
  final int? onIconCodepoint;
  final int? offIconCodepoint;

  @override
  Map<String, dynamic> toJson() => {
    if (valueExpression != null && valueExpression!.trim().isNotEmpty)
      'valueExpression': valueExpression,
    'onPayload': onPayload,
    'offPayload': offPayload,
    if (jsonPath != null) 'jsonPath': jsonPath,
    'onMatch': onMatch,
    if (onIconCodepoint != null) 'onIcon': onIconCodepoint,
    if (offIconCodepoint != null) 'offIcon': offIconCodepoint,
  };

  static ToggleConfig fromJson(Map<String, dynamic> j) => ToggleConfig(
    valueExpression: j['valueExpression'] as String?,
    onPayload: j['onPayload'] as String? ?? '{"state":"ON"}',
    offPayload: j['offPayload'] as String? ?? '{"state":"OFF"}',
    jsonPath: j['jsonPath'] as String?,
    onMatch: j['onMatch'] as String? ?? 'ON',
    onIconCodepoint: j['onIcon'] as int?,
    offIconCodepoint: j['offIcon'] as int?,
  );
}

class SliderConfig extends PanelConfig {
  const SliderConfig({
    this.valueExpression,
    this.min = 0,
    this.max = 254,
    this.step = 1,
    this.vertical = false,
    this.valueTemplate = '{"brightness":{value}}',
    this.jsonPath = 'brightness',
  });

  @override
  final String? valueExpression;

  final double min;
  final double max;
  final double step;
  final bool vertical;
  final String valueTemplate;
  final String? jsonPath;

  @override
  Map<String, dynamic> toJson() => {
    if (valueExpression != null && valueExpression!.trim().isNotEmpty)
      'valueExpression': valueExpression,
    'min': min,
    'max': max,
    'step': step,
    'vertical': vertical,
    'valueTemplate': valueTemplate,
    if (jsonPath != null) 'jsonPath': jsonPath,
  };

  static SliderConfig fromJson(Map<String, dynamic> j) => SliderConfig(
    valueExpression: j['valueExpression'] as String?,
    min: (j['min'] as num?)?.toDouble() ?? 0,
    max: (j['max'] as num?)?.toDouble() ?? 254,
    step: (j['step'] as num?)?.toDouble() ?? 1,
    vertical: j['vertical'] as bool? ?? false,
    valueTemplate: j['valueTemplate'] as String? ?? '{"brightness":{value}}',
    jsonPath: j['jsonPath'] as String?,
  );
}

/// Read-only colored indicator. Subscribes to a topic, extracts a value via
/// [jsonPath], and lights up [onColorArgb] when the extracted value matches
/// [onMatch]. Useful for contact sensors, occupancy, leak alerts, etc.
class LedConfig extends PanelConfig {
  const LedConfig({
    this.valueExpression,
    this.jsonPath,
    this.onMatch = 'true',
    this.onColorArgb,
    this.offColorArgb,
    this.onLabel,
    this.offLabel,
  });

  @override
  final String? valueExpression;

  final String? jsonPath;
  final String onMatch;
  final int? onColorArgb;
  final int? offColorArgb;
  final String? onLabel;
  final String? offLabel;

  @override
  Map<String, dynamic> toJson() => {
    if (valueExpression != null && valueExpression!.trim().isNotEmpty)
      'valueExpression': valueExpression,
    if (jsonPath != null) 'jsonPath': jsonPath,
    'onMatch': onMatch,
    if (onColorArgb != null) 'onColor': onColorArgb,
    if (offColorArgb != null) 'offColor': offColorArgb,
    if (onLabel != null) 'onLabel': onLabel,
    if (offLabel != null) 'offLabel': offLabel,
  };

  static LedConfig fromJson(Map<String, dynamic> j) => LedConfig(
    valueExpression: j['valueExpression'] as String?,
    jsonPath: j['jsonPath'] as String?,
    onMatch: j['onMatch'] as String? ?? 'true',
    onColorArgb: j['onColor'] as int?,
    offColorArgb: j['offColor'] as int?,
    onLabel: j['onLabel'] as String?,
    offLabel: j['offLabel'] as String?,
  );
}

/// Z2M device availability indicator. Subscribes to the availability topic
/// (typically `<prefix>/availability`, where Z2M publishes raw `online` /
/// `offline` strings by default).
class NodeStatusConfig extends PanelConfig {
  const NodeStatusConfig({
    this.valueExpression,
    this.onlinePayload = 'online',
    this.jsonPath,
  });

  @override
  final String? valueExpression;

  final String onlinePayload;
  final String? jsonPath;

  @override
  Map<String, dynamic> toJson() => {
    if (valueExpression != null && valueExpression!.trim().isNotEmpty)
      'valueExpression': valueExpression,
    'onlinePayload': onlinePayload,
    if (jsonPath != null) 'jsonPath': jsonPath,
  };

  static NodeStatusConfig fromJson(Map<String, dynamic> j) => NodeStatusConfig(
    valueExpression: j['valueExpression'] as String?,
    onlinePayload: j['onlinePayload'] as String? ?? 'online',
    jsonPath: j['jsonPath'] as String?,
  );
}

/// Read-only progress bar. Useful for battery %, link quality, etc.
class ProgressConfig extends PanelConfig {
  const ProgressConfig({
    this.valueExpression,
    this.min = 0,
    this.max = 100,
    this.jsonPath,
    this.unit,
  });

  @override
  final String? valueExpression;

  final double min;
  final double max;
  final String? jsonPath;
  final String? unit;

  @override
  Map<String, dynamic> toJson() => {
    if (valueExpression != null && valueExpression!.trim().isNotEmpty)
      'valueExpression': valueExpression,
    'min': min,
    'max': max,
    if (jsonPath != null) 'jsonPath': jsonPath,
    if (unit != null) 'unit': unit,
  };

  static ProgressConfig fromJson(Map<String, dynamic> j) => ProgressConfig(
    valueExpression: j['valueExpression'] as String?,
    min: (j['min'] as num?)?.toDouble() ?? 0,
    max: (j['max'] as num?)?.toDouble() ?? 100,
    jsonPath: j['jsonPath'] as String?,
    unit: j['unit'] as String?,
  );
}

/// A single choice in a Multi-State / Combo / Radio panel. [payload] is what
/// gets published when the option is chosen; [match] is the value at the
/// panel's [OptionsConfig.jsonPath] that marks this option as the current one.
class SelectOption {
  const SelectOption({
    required this.label,
    required this.payload,
    required this.match,
  });

  final String label;
  final String payload;
  final String match;

  Map<String, dynamic> toJson() => {
    'label': label,
    'payload': payload,
    'match': match,
  };

  static SelectOption fromJson(Map<String, dynamic> j) => SelectOption(
    label: j['label'] as String? ?? '',
    payload: j['payload'] as String? ?? '',
    match: j['match'] as String? ?? '',
  );
}

/// Shared config for the enum-selection panel types (Multi-State, Combo,
/// Radio). They differ only in how the same list of [options] is rendered.
class OptionsConfig extends PanelConfig {
  const OptionsConfig({
    this.valueExpression,
    this.options = const [],
    this.jsonPath = 'state',
  });

  @override
  final String? valueExpression;

  final List<SelectOption> options;
  final String? jsonPath;

  /// Sensible default for Z2M covers: OPEN / STOP / CLOSE on the `state` field.
  factory OptionsConfig.coverDefault() => const OptionsConfig(
    jsonPath: 'state',
    options: [
      SelectOption(label: 'Open', payload: '{"state":"OPEN"}', match: 'OPEN'),
      SelectOption(label: 'Stop', payload: '{"state":"STOP"}', match: 'STOP'),
      SelectOption(
        label: 'Close',
        payload: '{"state":"CLOSE"}',
        match: 'CLOSE',
      ),
    ],
  );

  @override
  Map<String, dynamic> toJson() => {
    if (valueExpression != null && valueExpression!.trim().isNotEmpty)
      'valueExpression': valueExpression,
    'options': options.map((o) => o.toJson()).toList(),
    if (jsonPath != null) 'jsonPath': jsonPath,
  };

  static OptionsConfig fromJson(Map<String, dynamic> j) => OptionsConfig(
    valueExpression: j['valueExpression'] as String?,
    options:
        (j['options'] as List?)
            ?.map((e) => SelectOption.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
    jsonPath: j['jsonPath'] as String?,
  );
}

/// Composite Z2M cover control: OPEN/STOP/CLOSE buttons + a 0-100 position
/// slider with preset chips, mirroring the Zigbee2MQTT device page. Reads the
/// whole device-state payload and pulls [statePath] and [positionPath] out of
/// it; publishes `{"state":...}` for the buttons and the [positionTemplate]
/// for the slider.
class CoverConfig extends PanelConfig {
  const CoverConfig({
    this.statePath = 'state',
    this.positionPath = 'position',
    this.openPayload = '{"state":"OPEN"}',
    this.stopPayload = '{"state":"STOP"}',
    this.closePayload = '{"state":"CLOSE"}',
    this.positionTemplate = '{"position":{value}}',
    this.presets = const [0, 25, 50, 75, 100],
    this.showSlider = true,
    this.waitForFeedback = true,
    this.wirenBoard,
    this.openButton = const CoverButtonConfig(),
    this.closeButton = const CoverButtonConfig(),
    this.stopButton = const CoverButtonConfig(),
  });

  final String statePath;
  final String positionPath;
  final String openPayload;
  final String stopPayload;
  final String closePayload;
  final String positionTemplate;
  final List<int> presets;
  final bool showSlider;
  final bool waitForFeedback;
  final WirenBoardCoverBinding? wirenBoard;
  final CoverButtonConfig openButton, closeButton, stopButton;

  CoverConfig copyWith({
    CoverButtonConfig? openButton,
    CoverButtonConfig? closeButton,
    CoverButtonConfig? stopButton,
    List<int>? presets,
    bool? showSlider,
    bool? waitForFeedback,
  }) => CoverConfig(
    statePath: statePath,
    positionPath: positionPath,
    openPayload: openPayload,
    closePayload: closePayload,
    stopPayload: stopPayload,
    positionTemplate: positionTemplate,
    presets: presets ?? this.presets,
    showSlider: showSlider ?? this.showSlider,
    waitForFeedback: waitForFeedback ?? this.waitForFeedback,
    wirenBoard: wirenBoard,
    openButton: openButton ?? this.openButton,
    closeButton: closeButton ?? this.closeButton,
    stopButton: stopButton ?? this.stopButton,
  );

  @override
  Map<String, dynamic> toJson() => {
    'statePath': statePath,
    'positionPath': positionPath,
    'openPayload': openPayload,
    'stopPayload': stopPayload,
    'closePayload': closePayload,
    'positionTemplate': positionTemplate,
    'presets': presets,
    'showSlider': showSlider,
    'waitForFeedback': waitForFeedback,
    if (wirenBoard != null) 'wirenBoard': wirenBoard!.toJson(),
    'openButton': openButton.toJson(),
    'closeButton': closeButton.toJson(),
    'stopButton': stopButton.toJson(),
  };

  static CoverConfig fromJson(Map<String, dynamic> j) => CoverConfig(
    statePath: j['statePath'] as String? ?? 'state',
    positionPath: j['positionPath'] as String? ?? 'position',
    openPayload: j['openPayload'] as String? ?? '{"state":"OPEN"}',
    stopPayload: j['stopPayload'] as String? ?? '{"state":"STOP"}',
    closePayload: j['closePayload'] as String? ?? '{"state":"CLOSE"}',
    positionTemplate:
        j['positionTemplate'] as String? ?? '{"position":{value}}',
    presets:
        (j['presets'] as List?)?.map((e) => (e as num).toInt()).toList() ??
        const [0, 25, 50, 75, 100],
    showSlider: j['showSlider'] as bool? ?? true,
    waitForFeedback: j['waitForFeedback'] as bool? ?? true,
    wirenBoard: j['wirenBoard'] is Map
        ? WirenBoardCoverBinding.fromJson(
            Map<String, dynamic>.from(j['wirenBoard'] as Map),
          )
        : null,
    openButton: CoverButtonConfig.fromJson(
      Map<String, dynamic>.from(j['openButton'] as Map? ?? const {}),
    ),
    closeButton: CoverButtonConfig.fromJson(
      Map<String, dynamic>.from(j['closeButton'] as Map? ?? const {}),
    ),
    stopButton: CoverButtonConfig.fromJson(
      Map<String, dynamic>.from(j['stopButton'] as Map? ?? const {}),
    ),
  );
}

/// Free-form publish field. The typed text is substituted into [template]
/// ({value} placeholder) before publishing — default template is just the raw
/// text. Write-only (no subscription).
class TextInputConfig extends PanelConfig {
  const TextInputConfig({
    this.hint = '',
    this.template = '{value}',
    this.clearOnSend = false,
  });

  final String hint;
  final String template;
  final bool clearOnSend;

  @override
  Map<String, dynamic> toJson() => {
    'hint': hint,
    'template': template,
    'clearOnSend': clearOnSend,
  };

  static TextInputConfig fromJson(Map<String, dynamic> j) => TextInputConfig(
    hint: j['hint'] as String? ?? '',
    template: j['template'] as String? ?? '{value}',
    clearOnSend: j['clearOnSend'] as bool? ?? false,
  );
}

/// Read-only scrolling history of messages on a topic. Keeps the last
/// [maxLines] messages; optionally extracts a [jsonPath] field instead of
/// logging the whole payload.
class TextLogConfig extends PanelConfig {
  const TextLogConfig({
    this.valueExpression,
    this.maxLines = 50,
    this.jsonPath,
  });

  @override
  final String? valueExpression;

  final int maxLines;
  final String? jsonPath;

  @override
  Map<String, dynamic> toJson() => {
    if (valueExpression != null && valueExpression!.trim().isNotEmpty)
      'valueExpression': valueExpression,
    'maxLines': maxLines,
    if (jsonPath != null) 'jsonPath': jsonPath,
  };

  static TextLogConfig fromJson(Map<String, dynamic> j) => TextLogConfig(
    valueExpression: j['valueExpression'] as String?,
    maxLines: (j['maxLines'] as num?)?.toInt() ?? 50,
    jsonPath: j['jsonPath'] as String?,
  );
}

/// Configures a server-side daily open/close schedule executed by the
/// Node-RED scheduler flow on the SMHUB. ZigDash publishes this (plus the
/// composed target topic) as retained MQTT config — it never runs the
/// schedule itself. Times are "HH:mm" in the SMHUB's local time.
class ScheduleConfig extends PanelConfig {
  const ScheduleConfig({
    this.openTime = '07:00',
    this.closeTime = '19:00',
    this.openPayload = '{"state":"OPEN"}',
    this.closePayload = '{"state":"CLOSE"}',
    this.enabled = true,
  });

  final String openTime;
  final String closeTime;
  final String openPayload;
  final String closePayload;
  final bool enabled;

  ScheduleConfig copyWith({bool? enabled}) => ScheduleConfig(
    openTime: openTime,
    closeTime: closeTime,
    openPayload: openPayload,
    closePayload: closePayload,
    enabled: enabled ?? this.enabled,
  );

  @override
  Map<String, dynamic> toJson() => {
    'openTime': openTime,
    'closeTime': closeTime,
    'openPayload': openPayload,
    'closePayload': closePayload,
    'enabled': enabled,
  };

  static ScheduleConfig fromJson(Map<String, dynamic> j) => ScheduleConfig(
    openTime: j['openTime'] as String? ?? '07:00',
    closeTime: j['closeTime'] as String? ?? '19:00',
    openPayload: j['openPayload'] as String? ?? '{"state":"OPEN"}',
    closePayload: j['closePayload'] as String? ?? '{"state":"CLOSE"}',
    enabled: j['enabled'] as bool? ?? true,
  );
}

class SceneConfig extends PanelConfig {
  const SceneConfig({this.sceneId = ''});

  /// Id of the Scene this panel activates.
  final String sceneId;

  @override
  Map<String, dynamic> toJson() => {'sceneId': sceneId};

  static SceneConfig fromJson(Map<String, dynamic> j) =>
      SceneConfig(sceneId: j['sceneId'] as String? ?? '');
}

/// Configures a server-side "close device N seconds after it turns on" rule
/// executed by the Node-RED auto-close flow on the SMHUB. ZigDash publishes
/// this (plus the composed target topic) as retained MQTT config — it never
/// runs the timer itself. Delay is in seconds, clamped to [1, 3600].
class AutoCloseConfig extends PanelConfig {
  AutoCloseConfig({
    this.triggerPath = 'state',
    this.triggerValue = 'ON',
    this.closePayload = '{"state":"OFF"}',
    int delaySeconds = 60,
    this.enabled = true,
  }) : delaySeconds = delaySeconds.clamp(1, 3600);

  final String triggerPath;
  final String triggerValue;
  final String closePayload;
  final int delaySeconds;
  final bool enabled;

  AutoCloseConfig copyWith({bool? enabled}) => AutoCloseConfig(
    triggerPath: triggerPath,
    triggerValue: triggerValue,
    closePayload: closePayload,
    delaySeconds: delaySeconds,
    enabled: enabled ?? this.enabled,
  );

  @override
  Map<String, dynamic> toJson() => {
    'triggerPath': triggerPath,
    'triggerValue': triggerValue,
    'closePayload': closePayload,
    'delaySeconds': delaySeconds,
    'enabled': enabled,
  };

  static AutoCloseConfig fromJson(Map<String, dynamic> j) => AutoCloseConfig(
    triggerPath: j['triggerPath'] as String? ?? 'state',
    triggerValue: j['triggerValue'] as String? ?? 'ON',
    closePayload: j['closePayload'] as String? ?? '{"state":"OFF"}',
    delaySeconds: (j['delaySeconds'] as num?)?.toInt() ?? 60,
    enabled: j['enabled'] as bool? ?? true,
  );
}

/// Presentation overrides belong to a saved panel, never to broker metadata.
class DevicePanelDisplay {
  const DevicePanelDisplay({
    this.iconCodepoint,
    this.properties,
    this.labels = const {},
    this.expressions = const {},
  });
  final int? iconCodepoint;
  final List<String>? properties;
  final Map<String, String> labels;
  final Map<String, String> expressions;
  bool get hasPropertyOverrides =>
      properties != null || labels.isNotEmpty || expressions.isNotEmpty;
  bool get isDefault => iconCodepoint == null && !hasPropertyOverrides;
  String label(String id, String fallback) => labels[id] ?? fallback;
  Map<String, dynamic> toJson() => {
    if (iconCodepoint != null) 'icon': iconCodepoint,
    if (properties != null) 'properties': properties,
    if (labels.isNotEmpty) 'labels': labels,
    if (expressions.isNotEmpty) 'expressions': expressions,
  };
  static DevicePanelDisplay fromJson(Object? value) {
    if (value is! Map) return const DevicePanelDisplay();
    return DevicePanelDisplay(
      iconCodepoint: value['icon'] is int ? value['icon'] as int : null,
      properties: value['properties'] is List
          ? (value['properties'] as List).whereType<String>().toList()
          : null,
      expressions: value['expressions'] is Map
          ? {
              for (final e in (value['expressions'] as Map).entries)
                if (e.key is String &&
                    e.value is String &&
                    (e.value as String).trim().isNotEmpty)
                  e.key as String: (e.value as String).trim(),
            }
          : const {},
      labels: value['labels'] is Map
          ? {
              for (final entry in (value['labels'] as Map).entries)
                if (entry.key is String &&
                    entry.value is String &&
                    (entry.value as String).trim().isNotEmpty)
                  entry.key as String: (entry.value as String).trim(),
            }
          : const {},
    );
  }
}

/// A device tile: the device's class and exposes, cached when the tile was
/// added so it renders with the broker unreachable. The device itself is the
/// panel's `deviceIeee`; its topics are resolved from the friendly name.
class DeviceTileConfig extends PanelConfig {
  const DeviceTileConfig({
    required this.profile,
    this.model,
    this.display = const DevicePanelDisplay(),
  });

  final DevicePanelDisplay display;

  final DeviceProfile profile;

  /// Vendor and model, e.g. "Tuya CK-BL702-AL-01", shown when the friendly
  /// name is still an IEEE address.
  final String? model;

  @override
  Map<String, dynamic> toJson() => {
    'profile': profile.toJson(),
    if (model != null) 'model': model,
    if (!display.isDefault) 'display': display.toJson(),
  };

  static DeviceTileConfig fromJson(Map<String, dynamic> j) => DeviceTileConfig(
    profile: DeviceProfile.fromJson(j['profile']),
    model: j['model'] as String?,
    display: DevicePanelDisplay.fromJson(j['display']),
  );
}

/// A whole WB device. Cache metadata so its controls remain accessible when
/// offline; values are subscribed to independently on their scalar topics.
class WirenBoardDeviceConfig extends PanelConfig {
  const WirenBoardDeviceConfig({
    required this.device,
    this.controlIds,
    this.display = const DevicePanelDisplay(),
  });

  final DevicePanelDisplay display;

  final WirenBoardDevice device;

  /// Null follows all current and future controls; a list pins a user's subset.
  final List<String>? controlIds;

  WirenBoardDevice visibleDevice(WirenBoardDevice live) => controlIds == null
      ? live
      : WirenBoardDevice(
          id: live.id,
          metadata: live.metadata,
          z2mMirror: live.z2mMirror,
          controls: [
            for (final control in live.controls)
              if (controlIds!.contains(control.id)) control,
          ],
        );

  @override
  Map<String, dynamic> toJson() => {
    'protocol': 'wirenboard',
    'device': device.toJson(),
    if (controlIds != null) 'controlIds': controlIds,
    if (!display.isDefault) 'display': display.toJson(),
  };

  static WirenBoardDeviceConfig fromJson(Map<String, dynamic> json) =>
      WirenBoardDeviceConfig(
        device: WirenBoardDevice.fromJson(
          Map<String, dynamic>.from(json['device'] as Map),
        ),
        controlIds: (json['controlIds'] as List?)?.cast<String>(),
        display: DevicePanelDisplay.fromJson(json['display']),
      );
}

/// How a reading tile draws its value (docs/design/gauge-2.4.md).
enum ReadingStyle {
  /// The value, large, with the name below.
  value,

  /// A half arc from [ReadingConfig.min] to [ReadingConfig.max] with the
  /// value in the middle and up to three colour bands.
  gauge,
}

/// The colour a gauge band takes, from the theme's state roles: never a
/// free colour, so the arc stays on-brand in dark mode and Material You.
enum GaugeTone { normal, good, attention }

/// One colour band on a gauge: [tone] applies to values from [from] up to
/// and including [to].
@immutable
class GaugeBand {
  const GaugeBand({required this.from, required this.to, required this.tone});

  final double from;
  final double to;
  final GaugeTone tone;

  bool contains(num v) => v >= from && v <= to;

  Map<String, dynamic> toJson() => {'from': from, 'to': to, 'tone': tone.name};

  static GaugeBand? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final from = (raw['from'] as num?)?.toDouble();
    final to = (raw['to'] as num?)?.toDouble();
    if (from == null || to == null) return null;
    final tone = GaugeTone.values.firstWhere(
      (t) => t.name == raw['tone'],
      orElse: () => GaugeTone.normal,
    );
    return GaugeBand(from: from, to: to, tone: tone);
  }

  @override
  bool operator ==(Object other) =>
      other is GaugeBand &&
      other.from == from &&
      other.to == to &&
      other.tone == tone;

  @override
  int get hashCode => Object.hash(from, to, tone);
}

/// A gauge may carry at most this many bands.
const gaugeMaxBands = 3;

/// A reading tile: one numeric value at [jsonPath] (empty for a raw scalar) of the subscribed
/// payload, shown with [unit], as a plain value or as a gauge.
class ReadingConfig extends PanelConfig {
  const ReadingConfig({
    this.valueExpression,
    this.jsonPath = 'temperature',
    this.unit,
    this.decimals,
    this.style = ReadingStyle.value,
    this.min,
    this.max,
    this.bands = const [],
  });

  @override
  final String? valueExpression;

  final String jsonPath;
  final String? unit;

  /// Fraction digits; null shows the value as received, trimmed to one.
  final int? decimals;

  final ReadingStyle style;

  /// The gauge's range. Null until the tile is first shown as a gauge; the
  /// editor fills them from the device's expose or [gaugeDefaults].
  final double? min;
  final double? max;

  /// Up to [gaugeMaxBands] colour bands, in any order; the first that
  /// contains the value colours the arc.
  final List<GaugeBand> bands;

  ReadingConfig copyWith({
    String? jsonPath,
    String? unit,
    int? decimals,
    ReadingStyle? style,
    double? min,
    double? max,
    List<GaugeBand>? bands,
  }) => ReadingConfig(
    valueExpression: valueExpression,
    jsonPath: jsonPath ?? this.jsonPath,
    unit: unit ?? this.unit,
    decimals: decimals ?? this.decimals,
    style: style ?? this.style,
    min: min ?? this.min,
    max: max ?? this.max,
    bands: bands ?? this.bands,
  );

  @override
  Map<String, dynamic> toJson() => {
    if (valueExpression != null && valueExpression!.trim().isNotEmpty)
      'valueExpression': valueExpression,
    'jsonPath': jsonPath,
    if (unit != null) 'unit': unit,
    if (decimals != null) 'decimals': decimals,
    if (style != ReadingStyle.value) 'style': style.name,
    if (min != null) 'min': min,
    if (max != null) 'max': max,
    if (bands.isNotEmpty) 'bands': [for (final b in bands) b.toJson()],
  };

  static ReadingConfig fromJson(Map<String, dynamic> j) => ReadingConfig(
    valueExpression: j['valueExpression'] as String?,
    jsonPath: j['jsonPath'] as String? ?? 'temperature',
    unit: j['unit'] as String?,
    decimals: (j['decimals'] as num?)?.toInt(),
    style: ReadingStyle.values.firstWhere(
      (s) => s.name == j['style'],
      orElse: () => ReadingStyle.value,
    ),
    min: (j['min'] as num?)?.toDouble(),
    max: (j['max'] as num?)?.toDouble(),
    bands: [
      if (j['bands'] is List)
        for (final b in (j['bands'] as List).take(gaugeMaxBands))
          if (GaugeBand.fromJson(b) case final band?) band,
    ],
  );
}

/// Scalar widgets with an incoming display value. Write-only widgets and
/// whole devices use their existing commands or per-property settings.
bool supportsDisplayExpression(PanelType type) => const {
  PanelType.toggle,
  PanelType.slider,
  PanelType.led,
  PanelType.nodeStatus,
  PanelType.progress,
  PanelType.multiState,
  PanelType.combo,
  PanelType.radio,
  PanelType.textLog,
  PanelType.reading,
}.contains(type);

PanelConfig withDisplayExpression(
  PanelType type,
  PanelConfig config,
  String? expression,
) {
  if (!supportsDisplayExpression(type)) return config;
  final fields = config.toJson()..remove('valueExpression');
  if (expression != null && expression.trim().isNotEmpty) {
    fields['valueExpression'] = expression.trim();
  }
  return PanelConfig.decode(type, jsonEncode(fields));
}
