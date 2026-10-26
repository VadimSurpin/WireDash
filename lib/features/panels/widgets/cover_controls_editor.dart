import 'package:flutter/material.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../models/panel_config.dart';
import 'cover_button_icon.dart';

class CoverControlsEditor extends StatefulWidget {
  const CoverControlsEditor({
    super.key,
    required this.config,
    required this.onChanged,
  });
  final CoverConfig config;
  final ValueChanged<CoverConfig> onChanged;

  @override
  State<CoverControlsEditor> createState() => _CoverControlsEditorState();
}

class _CoverControlsEditorState extends State<CoverControlsEditor> {
  late CoverConfig config = widget.config;

  @override
  void didUpdateWidget(CoverControlsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    config = widget.config;
  }

  void _update(
    String id, {
    bool? visible,
    String? title,
    CoverButtonIcon? icon,
  }) {
    final previous = switch (id) {
      'open' => config.openButton,
      'close' => config.closeButton,
      _ => config.stopButton,
    };
    final button = previous.copyWith(
      visible: visible,
      title: title,
      icon: icon,
    );
    setState(
      () => config = switch (id) {
        'open' => config.copyWith(openButton: button),
        'close' => config.copyWith(closeButton: button),
        _ => config.copyWith(stopButton: button),
      },
    );
    widget.onChanged(config);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget button(
      String id,
      String label,
      CoverButtonConfig value,
      CoverButtonIcon fallback,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: ValueKey('cover-$id-visible'),
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          subtitle: Text(l10n.coverShowButton),
          value: value.visible,
          onChanged: (v) => _update(id, visible: v),
        ),
        if (value.visible) ...[
          TextFormField(
            key: ValueKey('cover-$id-title'),
            initialValue: value.title,
            maxLength: 64,
            decoration: InputDecoration(
              labelText: l10n.coverButtonTitle,
              hintText: label,
            ),
            onChanged: (v) => _update(id, title: v),
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final icon in CoverButtonIcon.values)
                IconButton(
                  key: ValueKey('cover-$id-icon:${icon.name}'),
                  tooltip: coverIconLabel(context, icon),
                  isSelected: (value.icon ?? fallback) == icon,
                  onPressed: () => _update(id, icon: icon),
                  icon: CoverButtonGlyph(icon),
                ),
            ],
          ),
        ],
      ],
    );
    return Column(
      children: [
        SwitchListTile(
          key: const ValueKey('cover-wait-for-feedback'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.coverWaitForFeedback),
          subtitle: Text(l10n.coverWaitForFeedbackHelper),
          value: config.waitForFeedback,
          onChanged: (value) {
            setState(() => config = config.copyWith(waitForFeedback: value));
            widget.onChanged(config);
          },
        ),
        button(
          'open',
          l10n.panelCoverOpen,
          config.openButton,
          CoverButtonIcon.up,
        ),
        button(
          'close',
          l10n.panelCoverClose,
          config.closeButton,
          CoverButtonIcon.down,
        ),
        button(
          'stop',
          l10n.panelCoverStop,
          config.stopButton,
          CoverButtonIcon.stop,
        ),
        FormField<bool>(
          validator: (_) =>
              config.openButton.visible ||
                  config.closeButton.visible ||
                  config.stopButton.visible
              ? null
              : l10n.fieldRequired,
          builder: (field) => field.hasError
              ? Text(
                  field.errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
