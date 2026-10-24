import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/utils/material_icon.dart';

/// Stores the original Material code point, like dashboard and scene icons.
class PanelIconPicker extends StatelessWidget {
  const PanelIconPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.defaultIcon = Icons.devices,
  });

  final int? value;
  final ValueChanged<int?> onChanged;
  final String? label;
  final IconData defaultIcon;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final choices = <IconData, String>{
      Icons.lightbulb: l10n.deviceClassLight,
      Icons.outlet: l10n.deviceClassSwitch,
      Icons.blinds: l10n.deviceClassCover,
      Icons.water_drop: l10n.deviceClassLeak,
      Icons.sensor_door: l10n.deviceClassContact,
      Icons.directions_walk: l10n.deviceClassMotion,
      Icons.thermostat: l10n.deviceClassClimate,
      Icons.devices: l10n.deviceClassGeneric,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label ?? l10n.dashFormIcon,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: Text(l10n.panelIconAutomatic),
              avatar: Icon(defaultIcon, size: 18),
              selected: value == null,
              onSelected: (_) => onChanged(null),
            ),
            for (final choice in choices.entries)
              IconButton(
                key: ValueKey('panel-icon:${choice.key.codePoint}'),
                tooltip: choice.value,
                isSelected: value == choice.key.codePoint,
                style: IconButton.styleFrom(
                  backgroundColor: value == choice.key.codePoint
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerLow,
                  foregroundColor: value == choice.key.codePoint
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
                onPressed: () => onChanged(choice.key.codePoint),
                icon: Icon(materialIcon(choice.key.codePoint)),
              ),
            // Keep an imported/custom icon visible even outside this palette.
            if (value != null &&
                !choices.keys.any((icon) => icon.codePoint == value))
              IconButton(
                tooltip: l10n.a11ySelectIcon,
                isSelected: true,
                onPressed: () => onChanged(value),
                icon: Icon(materialIcon(value!)),
              ),
          ],
        ),
      ],
    );
  }
}
