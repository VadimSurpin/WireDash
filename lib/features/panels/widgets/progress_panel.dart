import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../models/panel_config.dart';
import '../models/display_expression.dart';
import 'display_expression_field.dart';
import '../providers/panel_value_provider.dart';
import '../../../core/theme/motion.dart';

class ProgressPanel extends ConsumerWidget {
  const ProgressPanel({
    super.key,
    required this.connectionId,
    required this.subscribeTopic,
    required this.panel,
    required this.config,
  });

  final String connectionId;
  final String subscribeTopic;
  final Panel panel;
  final ProgressConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valueAsync = ref.watch(
      panelValueProvider(
        PanelStreamKey(
          connectionId: connectionId,
          topic: subscribeTopic,
          jsonPath: config.jsonPath,
        ),
      ),
    );

    final displayed = displayValue(
      ref,
      config.valueExpression,
      valueAsync.valueOrNull,
    );
    final parsed = num.tryParse('${displayed.value}');
    final raw = parsed?.isFinite == true ? parsed!.toDouble() : null;

    final span = (config.max - config.min);
    final fraction = (raw == null || span <= 0)
        ? null
        : ((raw - config.min) / span).clamp(0.0, 1.0).toDouble();

    final valueLabel = displayed.applied
        ? displayed.value == null
              ? '—'
              : '${displayed.text}${config.unit ?? ''}'
        : raw == null
        ? '—'
        : '${_format(raw)}${config.unit ?? ''}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    panel.name,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AnimatedSwitcher(
                  duration: SignalMotion.of(context, SignalMotion.stateChange),
                  child: DisplayExpressionResult(
                    result: displayed,
                    child: Text(
                      valueLabel,
                      key: ValueKey(valueLabel),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: fraction ?? 0.0),
              duration: SignalMotion.of(context, SignalMotion.stateChange),
              builder: (context, animatedFraction, _) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fraction == null ? null : animatedFraction,
                    minHeight: 8,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _format(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }
}
