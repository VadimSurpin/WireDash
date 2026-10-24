import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../models/panel_config.dart';
import 'display_expression_field.dart';
import 'panel_icon_picker.dart';

typedef DeviceDisplayProperty = ({String id, String label});

class DevicePanelDisplayEditor extends StatefulWidget {
  const DevicePanelDisplayEditor({
    super.key,
    required this.properties,
    required this.defaults,
    required this.value,
    required this.onChanged,
  });
  final List<DeviceDisplayProperty> properties;
  final List<String> defaults;
  final DevicePanelDisplay value;
  final ValueChanged<DevicePanelDisplay> onChanged;

  @override
  State<DevicePanelDisplayEditor> createState() =>
      _DevicePanelDisplayEditorState();
}

class _DevicePanelDisplayEditorState extends State<DevicePanelDisplayEditor> {
  var _reset = 0;
  late DevicePanelDisplay _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  void didUpdateWidget(covariant DevicePanelDisplayEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.value, oldWidget.value)) _value = widget.value;
  }

  void _change(DevicePanelDisplay value) {
    setState(() => _value = value);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected = _value.properties ?? widget.defaults;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelIconPicker(
          value: _value.iconCodepoint,
          onChanged: (icon) => _change(
            DevicePanelDisplay(
              iconCodepoint: icon,
              properties: _value.properties,
              labels: _value.labels,
              expressions: _value.expressions,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.panelDisplayTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.panelDisplayHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final property in widget.properties)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Checkbox(
                  key: ValueKey('display-property:${property.id}'),
                  semanticLabel: property.label,
                  value: selected.contains(property.id),
                  onChanged: (checked) {
                    final ids = (_value.properties ?? widget.defaults).toSet();
                    if (checked == true) {
                      ids.add(property.id);
                    } else {
                      ids.remove(property.id);
                    }
                    _change(
                      DevicePanelDisplay(
                        iconCodepoint: _value.iconCodepoint,
                        properties: ids.toList(),
                        labels: _value.labels,
                        expressions: _value.expressions,
                      ),
                    );
                  },
                ),
                Expanded(
                  child: Column(
                    children: [
                      TextFormField(
                        key: ValueKey('display-label:$_reset:${property.id}'),
                        initialValue: _value.labels[property.id] ?? '',
                        decoration: InputDecoration(
                          labelText: property.label,
                          hintText: l10n.panelDisplayLabel,
                        ),
                        onChanged: (label) {
                          final labels = Map<String, String>.of(_value.labels);
                          if (label.trim().isEmpty) {
                            labels.remove(property.id);
                          } else {
                            labels[property.id] = label.trim();
                          }
                          _change(
                            DevicePanelDisplay(
                              iconCodepoint: _value.iconCodepoint,
                              properties: _value.properties,
                              labels: labels,
                              expressions: _value.expressions,
                            ),
                          );
                        },
                      ),
                      DisplayExpressionField(
                        key: ValueKey(
                          'display-expression:$_reset:${property.id}',
                        ),
                        initialValue: _value.expressions[property.id],
                        onChanged: (expression) {
                          final expressions = Map<String, String>.of(
                            _value.expressions,
                          );
                          if (expression.trim().isEmpty) {
                            expressions.remove(property.id);
                          } else {
                            expressions[property.id] = expression;
                          }
                          _change(
                            DevicePanelDisplay(
                              iconCodepoint: _value.iconCodepoint,
                              properties: _value.properties,
                              labels: _value.labels,
                              expressions: expressions,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: () {
              setState(() => _reset++);
              _change(DevicePanelDisplay(iconCodepoint: _value.iconCodepoint));
            },
            child: Text(l10n.panelDisplayReset),
          ),
        ),
      ],
    );
  }
}
