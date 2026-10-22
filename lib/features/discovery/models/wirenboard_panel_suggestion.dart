import '../../../data/database/tables/panels.dart';
import '../../panels/models/panel_config.dart';
import 'device_panel_suggestion.dart';
import 'wirenboard_device.dart';

PanelSuggestion suggestWirenBoardDevicePanel(
  WirenBoardDevice device, {
  String language = 'en',
}) => PanelSuggestion(
  type: PanelType.device,
  name: device.title(language),
  topicPrefixOverride: '/devices/${device.id}',
  publishTopicSuffix: '',
  subscribeTopicSuffix: '',
  config: WirenBoardDeviceConfig(device: device),
);

/// WB controls use raw scalar payloads, with writes on `<control>/on`.
PanelSuggestion _defaultWirenBoardPanel(
  WirenBoardDevice device,
  WirenBoardControl control, {
  String language = 'en',
}) {
  final (PanelType type, PanelConfig config) = switch (control) {
    _ when control.type == 'wo-switch' && !control.readOnly => (
      PanelType.combo,
      const OptionsConfig(
        jsonPath: null,
        options: [
          SelectOption(label: '0', payload: '0', match: '0'),
          SelectOption(label: '1', payload: '1', match: '1'),
        ],
      ),
    ),
    _
        when control.type == 'switch' ||
            control.type == 'wo-switch' ||
            control.type == 'alarm' =>
      control.readOnly
          ? (PanelType.led, const LedConfig(jsonPath: null, onMatch: '1'))
          : (
              PanelType.toggle,
              const ToggleConfig(
                onPayload: '1',
                offPayload: '0',
                jsonPath: null,
                onMatch: '1',
              ),
            ),
    _ when !control.readOnly && control.type == 'pushbutton' => (
      PanelType.button,
      const ButtonConfig(payload: '1'),
    ),
    _ when !control.readOnly && control.choices.isNotEmpty => (
      PanelType.combo,
      OptionsConfig(
        jsonPath: null,
        options: [
          for (final entry in control.choices.entries)
            SelectOption(
              label: wirenBoardTitle(entry.value, language, entry.key),
              payload: _enumValue(control, entry.key),
              match: _enumValue(control, entry.key),
            ),
        ],
      ),
    ),
    _
        when !control.readOnly &&
            control.type == 'range' &&
            (control.max ?? 255) > (control.min ?? 0) =>
      (
        PanelType.slider,
        SliderConfig(
          min: control.min ?? 0,
          max: control.max ?? 255,
          step: 1,
          jsonPath: null,
          valueTemplate: '{value}',
        ),
      ),
    _ when control.numeric && control.readOnly => (
      PanelType.reading,
      ReadingConfig(jsonPath: '', unit: control.unit),
    ),
    _ when !control.readOnly => (
      PanelType.textInput,
      const TextInputConfig(template: '{value}'),
    ),
    _ => (PanelType.textLog, const TextLogConfig(jsonPath: null)),
  };
  return PanelSuggestion(
    type: type,
    name: '${device.title(language)} · ${control.title(language)}',
    topicPrefixOverride: control.topic,
    publishTopicSuffix: control.readOnly ? '' : 'on',
    subscribeTopicSuffix: '',
    config: config,
  );
}

/// Compatible widgets keep scalar payloads and the control's read-only contract.
PanelSuggestion suggestWirenBoardPanel(
  WirenBoardDevice device,
  WirenBoardControl control, {
  String language = 'en',
  PanelType? widgetType,
}) {
  final recommended = _defaultWirenBoardPanel(
    device,
    control,
    language: language,
  );
  final binary = const {'switch', 'wo-switch', 'alarm'}.contains(control.type);
  final numeric = control.numeric;
  final min = control.min ?? 0;
  final max = control.max ?? (control.type == 'range' ? 255 : 100);
  final types = <PanelType>{
    recommended.type,
    if (binary) PanelType.led,
    if (numeric) PanelType.reading,
    if (numeric && max > min) PanelType.progress,
    if (!control.readOnly) ...[
      if (control.type == 'switch') PanelType.toggle,
      if (binary || control.type == 'pushbutton') PanelType.button,
      if (numeric && max > min) PanelType.slider,
      if (binary || control.choices.isNotEmpty) ...[
        PanelType.combo,
        PanelType.radio,
        PanelType.multiState,
      ],
      PanelType.textInput,
    ],
    PanelType.textLog,
  };
  PanelConfig configFor(PanelType type) {
    if (type == recommended.type) return recommended.config!;
    return switch (type) {
      PanelType.toggle => const ToggleConfig(
        onPayload: '1',
        offPayload: '0',
        jsonPath: null,
        onMatch: '1',
      ),
      PanelType.button => const ButtonConfig(payload: '1'),
      PanelType.led => const LedConfig(jsonPath: null, onMatch: '1'),
      PanelType.reading => ReadingConfig(jsonPath: '', unit: control.unit),
      PanelType.progress => ProgressConfig(
        min: min,
        max: max,
        jsonPath: null,
        unit: control.unit,
      ),
      PanelType.slider => SliderConfig(
        min: min,
        max: max,
        step: 1,
        jsonPath: null,
        valueTemplate: '{value}',
      ),
      PanelType.textInput => const TextInputConfig(template: '{value}'),
      PanelType.combo ||
      PanelType.radio ||
      PanelType.multiState => OptionsConfig(
        jsonPath: null,
        options: [
          if (control.choices.isNotEmpty)
            for (final entry in control.choices.entries)
              SelectOption(
                label: wirenBoardTitle(entry.value, language, entry.key),
                payload: _enumValue(control, entry.key),
                match: _enumValue(control, entry.key),
              )
          else ...[
            const SelectOption(label: '0', payload: '0', match: '0'),
            const SelectOption(label: '1', payload: '1', match: '1'),
          ],
        ],
      ),
      _ => const TextLogConfig(jsonPath: null),
    };
  }

  final selected = widgetType ?? recommended.type;
  if (!types.contains(selected)) {
    throw ArgumentError('Widget is not compatible with this control');
  }
  PanelSuggestion option(PanelType type) => PanelSuggestion(
    type: type,
    name: recommended.name,
    topicPrefixOverride: control.topic,
    publishTopicSuffix: control.readOnly ? '' : 'on',
    subscribeTopicSuffix: '',
    config: configFor(type),
  );
  final result = option(selected);
  return PanelSuggestion(
    type: result.type,
    name: result.name,
    topicPrefixOverride: result.topicPrefixOverride,
    publishTopicSuffix: result.publishTopicSuffix,
    subscribeTopicSuffix: '',
    config: result.config,
    widgetChoices: [for (final type in types) option(type)],
  );
}

String _enumValue(WirenBoardControl control, String key) {
  if (control.type != 'value') return key;
  final value = num.tryParse(key);
  if (value == null || !value.isFinite) return key;
  return value == value.roundToDouble() ? value.toInt().toString() : '$value';
}
