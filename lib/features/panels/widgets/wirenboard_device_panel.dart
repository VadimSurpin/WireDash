import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../data/database/database.dart';
import '../../../mqtt/mqtt_status.dart';
import '../../../mqtt/providers/mqtt_manager_provider.dart';
import '../../discovery/models/wirenboard_device.dart';
import '../../discovery/providers/wirenboard_discovery_provider.dart';
import '../models/panel_config.dart';
import 'wirenboard_control_row.dart';

/// A HomeUI-style device card: one header and compact inline control rows.
class WirenBoardDevicePanel extends ConsumerStatefulWidget {
  const WirenBoardDevicePanel({
    super.key,
    required this.connectionId,
    required this.panel,
    required this.config,
  });

  final String connectionId;
  final Panel panel;
  final WirenBoardDeviceConfig config;

  @override
  ConsumerState<WirenBoardDevicePanel> createState() =>
      _WirenBoardDevicePanelState();
}

class _WirenBoardDevicePanelState extends ConsumerState<WirenBoardDevicePanel> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final device = _currentDevice(ref, widget.connectionId, widget.config);
    final connected =
        ref.watch(connectionStatusProvider(widget.connectionId)).valueOrNull ==
        MqttStatus.connected;
    final header = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xff323d65)
        : const Color(0xff337ab7);
    final radius = BorderRadius.circular(8);
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: header),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: header,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Tooltip(
                        message: context.l10n.wbControlCount(
                          device.controls.length,
                        ),
                        child: Text(
                          widget.panel.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.titleSmall?.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                    if (!connected)
                      Tooltip(
                        message: context.l10n.controlNotConnected,
                        child: const Icon(
                          Icons.cloud_off_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    IconButton(
                      tooltip: context.l10n.wbOpenControls,
                      icon: const Icon(
                        Icons.open_in_full,
                        color: Colors.white,
                        size: 18,
                      ),
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        showDragHandle: true,
                        builder: (_) => WirenBoardDeviceControls(
                          connectionId: widget.connectionId,
                          panel: widget.panel,
                          config: widget.config,
                        ),
                      ),
                    ),
                    Semantics(
                      button: true,
                      expanded: _expanded,
                      child: IconButton(
                        tooltip: context.l10n.wbControlCount(
                          device.controls.length,
                        ),
                        icon: Icon(
                          _expanded ? Icons.expand_more : Icons.chevron_right,
                          color: Colors.white,
                        ),
                        onPressed: () => setState(() => _expanded = !_expanded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 4),
            for (final control in device.controls)
              WirenBoardControlRow(
                key: ValueKey(control.id),
                connectionId: widget.connectionId,
                device: device,
                control: control,
                qos: widget.panel.qos,
              ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

WirenBoardDevice _currentDevice(
  WidgetRef ref,
  String connectionId,
  WirenBoardDeviceConfig config,
) => config.visibleDevice(
  ref
          .watch(wirenBoardDevicesProvider(connectionId))
          .valueOrNull
          ?.where((d) => d.id == config.device.id)
          .firstOrNull ??
      config.device,
);

class WirenBoardDeviceControls extends ConsumerWidget {
  const WirenBoardDeviceControls({
    super.key,
    required this.connectionId,
    required this.panel,
    required this.config,
  });

  final String connectionId;
  final Panel panel;
  final WirenBoardDeviceConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = _currentDevice(ref, connectionId, config);
    final indexes = {
      for (var i = 0; i < device.controls.length; i++) device.controls[i].id: i,
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        minChildSize: .35,
        maxChildSize: 1,
        builder: (context, scrollController) => Scrollbar(
          controller: scrollController,
          child: CustomScrollView(
            key: const PageStorageKey('wirenboard-controls'),
            controller: scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: ListTile(
                  title: Text(panel.name),
                  subtitle: Text(
                    context.l10n.wbControlCount(device.controls.length),
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: device.controls.length,
                findChildIndexCallback: (key) =>
                    key is ValueKey<String> ? indexes[key.value] : null,
                itemBuilder: (context, index) {
                  final control = device.controls[index];
                  return WirenBoardControlRow(
                    key: ValueKey(control.id),
                    connectionId: connectionId,
                    device: device,
                    control: control,
                    qos: panel.qos,
                  );
                },
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.paddingOf(context).bottom + 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
