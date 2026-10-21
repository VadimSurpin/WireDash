import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../data/database/database.dart';
import '../../../mqtt/mqtt_status.dart';
import '../../../mqtt/providers/mqtt_manager_provider.dart';
import '../../discovery/models/wirenboard_device.dart';
import '../../discovery/models/wirenboard_panel_suggestion.dart';
import '../../discovery/providers/wirenboard_discovery_provider.dart';
import '../models/panel_config.dart';
import '../providers/panel_value_provider.dart';

/// One dashboard tile, with the full device's scalar controls in its sheet.
/// Child controls use the normal panel renderer and connection/freshness gates.
class WirenBoardDevicePanel extends ConsumerWidget {
  const WirenBoardDevicePanel({
    super.key,
    required this.connectionId,
    required this.panel,
    required this.config,
    required this.controlBuilder,
  });

  final String connectionId;
  final Panel panel;
  final WirenBoardDeviceConfig config;
  final Widget Function(Panel panel) controlBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = _currentDevice(ref, connectionId, config.device);
    final language = Localizations.localeOf(context).languageCode;
    final l10n = context.l10n;
    final connected =
        ref.watch(connectionStatusProvider(connectionId)).valueOrNull ==
        MqttStatus.connected;
    final preview = device.controls
        .where((c) => c.type != 'pushbutton' && c.type != 'wo-switch')
        .take(3);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => _WirenBoardControls(
            connectionId: connectionId,
            panel: panel,
            config: config,
            controlBuilder: controlBuilder,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.developer_board_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      panel.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (!connected)
                    Tooltip(
                      message: l10n.controlNotConnected,
                      child: const Icon(Icons.cloud_off_outlined, size: 18),
                    ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l10n.wbControlCount(device.controls.length),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              for (final control in preview)
                Text(
                  '${control.title(language)}: ${_preview(context, ref, control)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _preview(
    BuildContext context,
    WidgetRef ref,
    WirenBoardControl control,
  ) {
    final raw = ref
        .watch(
          panelValueProvider(
            PanelStreamKey(
              connectionId: connectionId,
              topic: control.topic,
              jsonPath: null,
            ),
          ),
        )
        .valueOrNull;
    if (raw == null) return '—';
    final value = raw.toString();
    if (control.type == 'switch' || control.type == 'alarm') {
      if (value == '1') return context.l10n.panelStateOn;
      if (value == '0') return context.l10n.panelStateOff;
    }
    if (control.choices.isNotEmpty) {
      final language = Localizations.localeOf(context).languageCode;
      for (final entry in control.choices.entries) {
        if (entry.key == value ||
            (control.numeric &&
                num.tryParse(entry.key) != null &&
                num.tryParse(entry.key) == num.tryParse(value))) {
          return wirenBoardTitle(entry.value, language, value);
        }
      }
    }
    return control.unit == null ? value : '$value ${control.unit}';
  }
}

WirenBoardDevice _currentDevice(
  WidgetRef ref,
  String connectionId,
  WirenBoardDevice cached,
) =>
    ref
        .watch(wirenBoardDevicesProvider(connectionId))
        .valueOrNull
        ?.where((d) => d.id == cached.id)
        .firstOrNull ??
    cached;

class _WirenBoardControls extends ConsumerWidget {
  const _WirenBoardControls({
    required this.connectionId,
    required this.panel,
    required this.config,
    required this.controlBuilder,
  });

  final String connectionId;
  final Panel panel;
  final WirenBoardDeviceConfig config;
  final Widget Function(Panel panel) controlBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = _currentDevice(ref, connectionId, config.device);
    final language = Localizations.localeOf(context).languageCode;
    final indexes = {
      for (var i = 0; i < device.controls.length; i++) device.controls[i].id: i,
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .8,
          child: Column(
            children: [
              ListTile(
                title: Text(panel.name),
                subtitle: Text(
                  context.l10n.wbControlCount(device.controls.length),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: device.controls.length,
                  findChildIndexCallback: (key) =>
                      key is ValueKey<String> ? indexes[key.value] : null,
                  itemBuilder: (context, index) {
                    final control = device.controls[index];
                    final suggestion = suggestWirenBoardPanel(
                      device,
                      control,
                      language: language,
                    );
                    // Render controls without creating DB rows or exposing tile-edit
                    // actions for these temporary children.
                    return KeyedSubtree(
                      key: ValueKey(control.id),
                      child: controlBuilder(
                        panel.copyWith(
                          id: '${panel.id}/${control.id}',
                          name: control.title(language),
                          type: suggestion.type,
                          topicPrefixOverride: Value(control.topic),
                          topic: suggestion.publishTopicSuffix,
                          subscribeTopic: const Value(''),
                          deviceIeee: const Value(null),
                          retain: false,
                          config: suggestion.config!.encode(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
