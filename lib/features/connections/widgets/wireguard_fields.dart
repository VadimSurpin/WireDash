import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../mqtt/wireguard/backend.dart';

bool get supportsEmbeddedWireGuard =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

Future<bool> validateWireGuardForForm(
  BuildContext context,
  String config,
) async {
  try {
    await createWireGuardBackend().validate(config);
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.wgInvalidConfiguration)),
      );
    }
    return false;
  }
}

/// Shared by the first connection wizard and the editable connection form.
class WireGuardFields extends StatefulWidget {
  const WireGuardFields({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    this.busy = false,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final bool busy;

  @override
  State<WireGuardFields> createState() => _WireGuardFieldsState();
}

class _WireGuardFieldsState extends State<WireGuardFields> {
  late bool _show = widget.controller.text.isEmpty;

  Future<void> _import() async {
    try {
      final picked = await FilePicker.pickFiles(withData: true);
      if (picked == null || !mounted) return;
      final bytes = picked.files.single.bytes;
      if (bytes == null) throw const FormatException();
      final text = utf8.decode(bytes);
      await createWireGuardBackend().validate(text);
      if (mounted) {
        setState(() {
          widget.controller.text = text;
          _show = false;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.wgInvalidConfiguration)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!supportsEmbeddedWireGuard && !widget.enabled) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.wgTitle),
          subtitle: Text(l10n.wgDescription),
          value: widget.enabled,
          onChanged: widget.busy || !supportsEmbeddedWireGuard
              ? null
              : (value) {
                  if (value && widget.controller.text.isEmpty) {
                    setState(() => _show = true);
                  }
                  widget.onChanged(value);
                },
        ),
        if (widget.enabled) ...[
          TextFormField(
            controller: widget.controller,
            readOnly: !_show,
            obscureText: !_show,
            maxLines: _show ? 8 : 1,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l10n.wgConfiguration,
              helperText: l10n.wgSecretHint,
              helperMaxLines: 8,
              suffixIcon: IconButton(
                tooltip: _show ? l10n.wgHide : l10n.wgShow,
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
            validator: (value) =>
                widget.enabled && (value == null || value.trim().isEmpty)
                ? l10n.fieldRequired
                : null,
          ),
          TextButton.icon(
            onPressed: widget.busy ? null : _import,
            icon: const Icon(Icons.file_open_outlined),
            label: Text(l10n.wgImport),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
