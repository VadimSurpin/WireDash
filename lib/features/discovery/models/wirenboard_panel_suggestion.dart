import '../../../data/database/tables/panels.dart';
import '../../panels/models/panel_config.dart';
import 'device_panel_suggestion.dart';
import 'wirenboard_device.dart';

/// WB controls use raw scalar payloads, with writes on `<control>/on`.
PanelSuggestion suggestWirenBoardPanel(
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
    _ when !control.readOnly && (control.numeric || control.type == 'text') => (
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

String _enumValue(WirenBoardControl control, String key) {
  if (control.type != 'value') return key;
  final value = num.tryParse(key);
  if (value == null || !value.isFinite) return key;
  return value == value.roundToDouble() ? value.toInt().toString() : '$value';
}
