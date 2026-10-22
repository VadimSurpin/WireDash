import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../models/display_expression.dart';

class DisplayExpressionField extends ConsumerStatefulWidget {
  const DisplayExpressionField({
    super.key,
    this.initialValue,
    required this.onChanged,
  });
  final String? initialValue;
  final ValueChanged<String> onChanged;

  @override
  ConsumerState<DisplayExpressionField> createState() =>
      _DisplayExpressionFieldState();
}

class _DisplayExpressionFieldState
    extends ConsumerState<DisplayExpressionField> {
  late final _expression = TextEditingController(
    text: widget.initialValue ?? '',
  );
  final _sample = TextEditingController(text: '1234');
  late bool _expanded = widget.initialValue?.trim().isNotEmpty == true;
  DisplayValue? _result;

  @override
  void didUpdateWidget(covariant DisplayExpressionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = widget.initialValue ?? '';
    if (oldWidget.initialValue != widget.initialValue &&
        _expression.text != text) {
      _expression.text = text;
      _result = null;
    }
  }

  @override
  void dispose() {
    _expression.dispose();
    _sample.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(_expanded ? Icons.expand_less : Icons.functions),
            label: Text(l10n.displayExpressionTitle),
          ),
        ),
        if (_expanded) ...[
          TextFormField(
            key: const ValueKey('display-expression'),
            controller: _expression,
            minLines: 1,
            maxLines: 4,
            maxLength: DisplayExpressionEvaluator.maxExpressionLength,
            autocorrect: false,
            enableSuggestions: false,
            smartQuotesType: SmartQuotesType.disabled,
            smartDashesType: SmartDashesType.disabled,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              labelText: l10n.displayExpressionTitle,
              hintText: '(Number(value) / 100).toFixed(2)',
              helperText: l10n.displayExpressionHint,
              helperMaxLines: 5,
              errorMaxLines: 4,
            ),
            validator: (value) {
              final error = ref
                  .read(displayExpressionEvaluatorProvider)
                  .validate(value);
              return error == null ? null : l10n.displayExpressionError(error);
            },
            onChanged: (value) {
              setState(() => _result = null);
              widget.onChanged(value);
            },
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('display-expression-sample'),
                  controller: _sample,
                  decoration: InputDecoration(
                    labelText: l10n.displayExpressionSample,
                  ),
                  onChanged: (_) => setState(() => _result = null),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  Object? value = _sample.text;
                  try {
                    value = jsonDecode(_sample.text);
                  } on FormatException {
                    /* raw scalar */
                  }
                  setState(
                    () => _result = ref
                        .read(displayExpressionEvaluatorProvider)
                        .evaluate(_expression.text, value),
                  );
                },
                child: Text(l10n.displayExpressionTest),
              ),
            ],
          ),
          if (_result case final result?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                result.error == null
                    ? l10n.displayExpressionResult(result.text)
                    : l10n.displayExpressionError(result.error!),
                style: TextStyle(
                  color: result.error == null
                      ? null
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Keep the normal widget layout unchanged when no expression is configured.
class DisplayExpressionResult extends StatelessWidget {
  const DisplayExpressionResult({
    super.key,
    required this.result,
    required this.child,
  });
  final DisplayValue result;
  final Widget child;
  @override
  Widget build(BuildContext context) => result.error == null
      ? child
      : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: context.l10n.displayExpressionError(result.error!),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(width: 4),
            Flexible(child: child),
          ],
        );
}
