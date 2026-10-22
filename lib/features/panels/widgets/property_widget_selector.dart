import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../data/database/tables/panels.dart';
import '../../../l10n/app_localizations.dart';
import '../../discovery/models/device_panel_suggestion.dart';

String panelWidgetLabel(PanelType type, AppLocalizations l10n) =>
    switch (type) {
      PanelType.button => l10n.panelTypeButton,
      PanelType.toggle => l10n.panelTypeToggle,
      PanelType.slider => l10n.panelTypeSlider,
      PanelType.led => l10n.panelTypeLed,
      PanelType.nodeStatus => l10n.panelTypeNodeStatus,
      PanelType.progress => l10n.panelTypeProgress,
      PanelType.multiState => l10n.panelTypeMultiState,
      PanelType.combo => l10n.panelTypeCombo,
      PanelType.radio => l10n.panelTypeRadio,
      PanelType.cover => l10n.panelTypeCover,
      PanelType.textInput => l10n.panelTypeTextInput,
      PanelType.textLog => l10n.panelTypeTextLog,
      PanelType.schedule => l10n.panelTypeSchedule,
      PanelType.scene => l10n.panelTypeScene,
      PanelType.autoClose => l10n.panelTypeAutoClose,
      PanelType.device => l10n.panelTypeDevice,
      PanelType.reading => l10n.panelTypeReading,
    };

class PropertyWidgetSelector extends StatelessWidget {
  const PropertyWidgetSelector({
    super.key,
    required this.choices,
    required this.value,
    required this.onChanged,
  });
  final List<PanelSuggestion> choices;
  final PanelType value;
  final ValueChanged<PanelType>? onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<PanelType>(
    key: ValueKey(value),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: context.l10n.panelPropertyWidget),
    items: [
      for (final choice in choices)
        DropdownMenuItem(
          value: choice.type,
          child: Text(panelWidgetLabel(choice.type, context.l10n)),
        ),
    ],
    onChanged: onChanged == null
        ? null
        : (value) {
            if (value != null) onChanged!(value);
          },
  );
}
