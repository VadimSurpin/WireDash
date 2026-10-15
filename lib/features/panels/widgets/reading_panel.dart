import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../models/gauge_defaults.dart';
import '../models/panel_config.dart';
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
    final value = raw is num ? raw : num.tryParse('$raw');
    final text = value == null
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
                GaugeArc(
                  value: value,
                  min: config.min ?? defaults.min,
                  max: config.max ?? defaults.max,
                  bands: config.bands,
                  label: text,
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
              Text(text, style: theme.textTheme.headlineMedium),
              name,
            ],
          ),
        ),
      ),
    );
  }
}
