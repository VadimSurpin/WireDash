import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart' as mc;

import '../../../core/l10n/l10n_ext.dart';
import '../../../mqtt/mqtt_status.dart';
import '../../../mqtt/providers/mqtt_manager_provider.dart';
import '../../discovery/models/wirenboard_device.dart';
import '../../discovery/models/wirenboard_panel_suggestion.dart';
import '../models/panel_config.dart';
import '../providers/panel_value_provider.dart';
import 'control_action.dart';
import 'panel_reliability_frame.dart';

String wirenBoardValueLabel(
  BuildContext context,
  WirenBoardControl control,
  Object? raw, {
  bool includeUnit = true,
}) {
  if (raw == null) return '—';
  final value = raw.toString();
  if (control.type == 'switch' || control.type == 'alarm') {
    if (value == '1') return context.l10n.panelStateOn;
    if (value == '0') return context.l10n.panelStateOff;
  }
  final language = Localizations.localeOf(context).languageCode;
  for (final entry in control.choices.entries) {
    final number = num.tryParse(entry.key) ?? int.tryParse(entry.key);
    if (entry.key == value ||
        (control.numeric && number != null && number == num.tryParse(value))) {
      return wirenBoardTitle(entry.value, language, value);
    }
  }
  return !includeUnit || control.unit == null
      ? value
      : '$value ${control.unit}';
}

/// A scalar MQTT control in a list, without dashboard-card sizing or chrome.
class WirenBoardControlRow extends ConsumerStatefulWidget {
  const WirenBoardControlRow({
    super.key,
    required this.connectionId,
    required this.device,
    required this.control,
    this.qos = 1,
    this.label,
  });

  final String connectionId;
  final WirenBoardDevice device;
  final WirenBoardControl control;
  final int qos;
  final String? label;

  @override
  ConsumerState<WirenBoardControlRow> createState() =>
      _WirenBoardControlRowState();
}

class _WirenBoardControlRowState extends ConsumerState<WirenBoardControlRow>
    with AutomaticKeepAliveClientMixin {
  final _text = TextEditingController();
  double? _dragging;

  @override
  bool get wantKeepAlive => _text.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _text.addListener(updateKeepAlive);
  }

  @override
  void dispose() {
    _text.removeListener(updateKeepAlive);
    _text.dispose();
    super.dispose();
  }

  Future<void> _publish(String payload) => runControlAction(
    context,
    ref,
    widget.connectionId,
    (manager) => manager.publish(
      '${widget.control.topic}/on',
      '{value}',
      payload,
      qos: mc.MqttQos.values[widget.qos.clamp(0, 2)],
      retain: false,
    ),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final control = widget.control;
    final language = Localizations.localeOf(context).languageCode;
    final name = widget.label ?? control.title(language);
    final key = PanelStreamKey(
      connectionId: widget.connectionId,
      topic: control.topic,
      jsonPath: null,
    );
    final raw = ref.watch(panelValueProvider(key)).valueOrNull;
    final snapshot = ref.watch(panelValueSnapshotProvider(key)).valueOrNull;
    final connected =
        ref.watch(connectionStatusProvider(widget.connectionId)).valueOrNull ==
        MqttStatus.connected;
    final config = suggestWirenBoardPanel(
      widget.device,
      control,
      language: language,
    ).config!;
    final title = Text(
      name,
      style: Theme.of(context).textTheme.bodyMedium,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    Widget pair(Widget value) => Row(
      children: [
        Expanded(flex: 2, child: title),
        const SizedBox(width: 12),
        Flexible(
          child: Align(alignment: AlignmentDirectional.centerEnd, child: value),
        ),
      ],
    );
    final Widget body;
    if (control.type == 'switch' || control.type == 'alarm') {
      final on = raw?.toString() == '1';
      body = pair(
        Switch.adaptive(
          value: on,
          activeTrackColor: const Color(0xff337ab7),
          activeThumbColor: Colors.white,
          onChanged: control.readOnly || !connected
              ? null
              : (_) => _publish(on ? '0' : '1'),
        ),
      );
    } else if (control.readOnly ||
        config is TextLogConfig ||
        config is LedConfig) {
      body = pair(
        Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.ltr,
          children: [
            Flexible(
              child: Text(
                wirenBoardValueLabel(context, control, raw, includeUnit: false),
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            if (control.unit != null) ...[
              const SizedBox(width: 6),
              Text(
                control.unit!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      );
    } else if (config is ButtonConfig) {
      body = Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton(
          onPressed: connected ? () => _publish(config.payload) : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xff337ab7),
          ),
          child: title,
        ),
      );
    } else if (config is OptionsConfig) {
      final current = raw?.toString();
      final matches = config.options.where((o) => o.match == current);
      body = pair(
        DropdownButton<String>(
          value: matches.isEmpty ? null : current,
          isExpanded: true,
          isDense: true,
          iconEnabledColor: const Color(0xff337ab7),
          hint: Text(wirenBoardValueLabel(context, control, raw)),
          items: [
            for (final option in config.options)
              DropdownMenuItem(
                value: option.match,
                child: Text(
                  option.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: !connected
              ? null
              : (value) {
                  if (value != null) {
                    _publish(
                      config.options
                          .firstWhere((o) => o.match == value)
                          .payload,
                    );
                  }
                },
        ),
      );
    } else if (config is SliderConfig) {
      final value = (_dragging ?? double.tryParse('$raw') ?? config.min)
          .clamp(config.min, config.max)
          .toDouble();
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          pair(
            Text(
              '${value.round()}${control.unit == null ? '' : ' ${control.unit}'}',
            ),
          ),
          Slider(
            label: name,
            activeColor: const Color(0xff337ab7),
            value: value,
            min: config.min,
            max: config.max,
            divisions: config.step <= 0
                ? null
                : ((config.max - config.min) / config.step).round().clamp(
                    1,
                    10000,
                  ),
            onChanged: !connected ? null : (v) => setState(() => _dragging = v),
            onChangeEnd: !connected
                ? null
                : (v) {
                    _publish(v.round().toString());
                    setState(() => _dragging = null);
                  },
          ),
        ],
      );
    } else {
      body = Row(
        children: [
          Expanded(flex: 2, child: title),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    textAlign: TextAlign.end,
                    textDirection: control.numeric ? TextDirection.ltr : null,
                    enabled: connected,
                    keyboardType: control.numeric
                        ? const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          )
                        : TextInputType.text,
                    style: Theme.of(context).textTheme.bodyMedium,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.all(8),
                      border: const OutlineInputBorder(),
                      hintText:
                          raw?.toString() ??
                          context.l10n.panelTextInputDefaultHint,
                    ),
                    onSubmitted: !connected
                        ? null
                        : (_) => _publish(_text.text),
                  ),
                ),
                IconButton(
                  tooltip: name,
                  color: const Color(0xff337ab7),
                  icon: const Icon(Icons.check, size: 20),
                  onPressed: !connected ? null : () => _publish(_text.text),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return PanelReliabilityFrame(
      stale: snapshot?.freshness == PanelFreshness.stale,
      receivedAt: snapshot?.receivedAt,
      valueLabel: wirenBoardValueLabel(context, control, raw),
      controlsEnabled: control.readOnly || config is TextLogConfig || connected,
      child: Container(
        constraints: BoxConstraints(
          minHeight:
              control.readOnly &&
                  control.type != 'switch' &&
                  control.type != 'alarm'
              ? 32
              : 48,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: body,
      ),
    );
  }
}
