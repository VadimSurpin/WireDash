import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../models/gauge_defaults.dart';
import '../models/panel_config.dart';
import '../models/display_expression.dart';
import 'display_expression_field.dart';
import '../providers/panel_value_provider.dart';
import 'device_tile_panel.dart';
import 'gauge_panel.dart';
import '../../history/history_sheet.dart';

/// One numeric value with its unit, large, with the tile name below.
class ReadingPanel extends ConsumerWidget {
  const ReadingPanel({
    super.key,
    required this.connectionId,
    required this.subscribeTopic,
    required this.panel,
    required this.config,
  });

  final String connectionId;
  final String subscribeTopic;
  final Panel panel;
  final ReadingConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final raw = ref
        .watch(
          panelValueProvider(
            PanelStreamKey(
              connectionId: connectionId,
              topic: subscribeTopic,
              jsonPath: config.jsonPath,
            ),
          ),
        )
        .valueOrNull;
    final displayed = displayValue(ref, config.valueExpression, raw);
    final transformed = displayed.value;
    final parsed = transformed is num
        ? transformed
        : num.tryParse('$transformed');
    final value = parsed?.isFinite == true ? parsed : null;
    final text = displayed.applied && transformed != null && transformed is! num
        ? ltr(
            '${displayed.text}${config.unit == null ? '' : ' ${config.unit}'}',
          )
        : value == null
        ? '—'
        : config.decimals == null
        ? formatReading(value, config.unit)
        : ltr(
            '${value.toStringAsFixed(config.decimals!)}'
            '${config.unit == null ? '' : ' ${config.unit}'}',
          );
    // 2.7: a tap opens the reading's history (tiles linked to a device).
    final ieee = panel.deviceIeee;
    final VoidCallback? openHistory = ieee == null
        ? null
        : () => showHistorySheet(
            context,
            connectionId: connectionId,
            ieee: ieee,
            path: config.jsonPath,
            title: panel.name,
            unit: config.unit,
            topic: subscribeTopic,
          );
    final name = Text(
      panel.name,
      style: theme.textTheme.bodySmall,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (config.style == ReadingStyle.gauge) {
      // A gauge saved without a range (older config, hand-edited backup)
      // still draws, on the reading's preset range.
      final defaults = gaugeDefaults(
        property: config.jsonPath,
        unit: config.unit,
      );
      return Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: openHistory,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                DisplayExpressionResult(
                  result: displayed,
                  child: GaugeArc(
                    value: value,
                    min: config.min ?? defaults.min,
                    max: config.max ?? defaults.max,
                    bands: config.bands,
                    label: text,
                  ),
                ),
                const SizedBox(height: 4),
                name,
              ],
            ),
          ),
        ),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: openHistory,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DisplayExpressionResult(
                      result: displayed,
                      child: Text(text, style: theme.textTheme.headlineMedium),
                    ),
                  ),
                  // 3.1.2: says the tap opens a graph.
                  if (openHistory != null)
                    Icon(
                      Icons.timeline,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],

              ),
              name,
            ],
          ),
        ),
      ),
    );
  }
}
