import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart' as mc;
import '../../../core/l10n/l10n_ext.dart';
import '../../../data/database/database.dart';
import '../../../mqtt/mqtt_status.dart';
import '../../../mqtt/providers/mqtt_manager_provider.dart';
import '../models/panel_config.dart';
import '../providers/panel_value_provider.dart';
import 'control_action.dart';
import 'cover_button_icon.dart';

class WirenBoardCoverPanel extends ConsumerStatefulWidget {
  const WirenBoardCoverPanel({
    super.key,
    required this.connectionId,
    required this.panel,
    required this.config,
  });
  final String connectionId;
  final Panel panel;
  final CoverConfig config;
  @override
  ConsumerState<WirenBoardCoverPanel> createState() =>
      _WirenBoardCoverPanelState();
}

class _WirenBoardCoverPanelState extends ConsumerState<WirenBoardCoverPanel> {
  String? _pending;
  bool _failed = false;
  DateTime? _sentAt;
  int? _generation;
  int _request = 0;
  Timer? _timeout;
  PanelValueSnapshot? _open, _close;

  void _finish({bool failed = false}) {
    _timeout?.cancel();
    _request++;
    setState(() {
      _pending = null;
      _sentAt = null;
      _failed = failed;
    });
  }

  void _confirm() {
    if (_pending == null || _sentAt == null) return;
    bool matches(PanelValueSnapshot? state, String expected) =>
        state != null &&
        state.freshness == PanelFreshness.fresh &&
        state.connectionGeneration == _generation &&
        state.receivedAt.isAfter(_sentAt!) &&
        state.value.toString() == expected;
    final confirmed = switch (_pending) {
      'OPEN' => matches(_open, '1'),
      'CLOSE' => matches(_close, '1'),
      'STOP' => matches(_open, '0') && matches(_close, '0'),
      _ => false,
    };
    if (confirmed) _finish();
  }

  Future<void> _send(String action) async {
    final request = ++_request;
    _timeout?.cancel();
    setState(() {
      _pending = action;
      _failed = false;
      _sentAt = null;
    });
    _timeout = Timer(const Duration(seconds: 15), () {
      if (mounted && request == _request) _finish(failed: true);
    });
    try {
      await runControlAction(context, ref, widget.connectionId, (manager) {
        if (!mounted || request != _request) return;
        _sentAt = DateTime.now();
        _generation = manager.connectionGeneration;
        final binding = widget.config.wirenBoard!;
        for (final topic in [
          if (action == 'OPEN' || action == 'STOP') binding.openTopic,
          if (action == 'CLOSE' || action == 'STOP') binding.closeTopic,
        ]) {
          manager.publish(
            '$topic/on',
            action == 'STOP' ? '0' : '1',
            '',
            qos: mc.MqttQos.values[widget.panel.qos.clamp(1, 2)],
            retain: false,
          );
        }
      });
      if (mounted && request == _request && _sentAt == null) {
        _finish(failed: true);
      }
    } catch (_) {
      if (mounted && request == _request) _finish(failed: true);
    }
  }

  @override
  void didUpdateWidget(WirenBoardCoverPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionId != widget.connectionId ||
        oldWidget.config.wirenBoard?.openTopic !=
            widget.config.wirenBoard?.openTopic) {
      _timeout?.cancel();
      _request++;
      _pending = null;
      _sentAt = null;
      _failed = false;
      _open = null;
      _close = null;
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final binding = widget.config.wirenBoard!;
    final openKey = PanelStreamKey(
      connectionId: widget.connectionId,
      topic: binding.openTopic,
      jsonPath: null,
    );
    final closeKey = PanelStreamKey(
      connectionId: widget.connectionId,
      topic: binding.closeTopic,
      jsonPath: null,
    );
    _open = ref.watch(panelValueSnapshotProvider(openKey)).valueOrNull;
    _close = ref.watch(panelValueSnapshotProvider(closeKey)).valueOrNull;
    ref.listen(panelValueSnapshotProvider(openKey), (_, next) {
      _open = next.valueOrNull;
      _confirm();
    });
    ref.listen(panelValueSnapshotProvider(closeKey), (_, next) {
      _close = next.valueOrNull;
      _confirm();
    });
    final connection = ref
        .watch(connectionStatusProvider(widget.connectionId))
        .valueOrNull;
    ref.listen(connectionStatusProvider(widget.connectionId), (_, next) {
      if (_pending != null && next.valueOrNull != MqttStatus.connected) {
        _finish(failed: true);
      }
    });
    final ready =
        connection == MqttStatus.connected &&
        _open?.freshness == PanelFreshness.fresh &&
        _close?.freshness == PanelFreshness.fresh &&
        _open?.connectionGeneration == _close?.connectionGeneration &&
        const ['0', '1'].contains(_open?.value.toString()) &&
        const ['0', '1'].contains(_close?.value.toString());
    final cfg = widget.config;
    final l10n = context.l10n;
    final active =
        _open?.value.toString() == '1' && _close?.value.toString() == '0'
        ? 'OPEN'
        : _close?.value.toString() == '1' && _open?.value.toString() == '0'
        ? 'CLOSE'
        : null;
    Widget button(
      String action,
      CoverButtonConfig setting,
      String title,
      CoverButtonIcon fallback,
    ) => FilledButton.tonalIcon(
      key: ValueKey('wb-cover-$action'),
      onPressed: ready && _pending != action ? () => _send(action) : null,
      style: active == action && ready
          ? FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            )
          : null,
      icon: _pending == action
          ? SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: l10n.shortcutWorking,
              ),
            )
          : CoverButtonGlyph(setting.icon ?? fallback, size: 24),
      label: Text(
        setting.title?.trim().isNotEmpty == true ? setting.title! : title,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.panel.name,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (cfg.openButton.visible)
                  button(
                    'OPEN',
                    cfg.openButton,
                    l10n.panelCoverOpen,
                    CoverButtonIcon.up,
                  ),
                if (cfg.stopButton.visible)
                  button(
                    'STOP',
                    cfg.stopButton,
                    l10n.panelCoverStop,
                    CoverButtonIcon.stop,
                  ),
                if (cfg.closeButton.visible)
                  button(
                    'CLOSE',
                    cfg.closeButton,
                    l10n.panelCoverClose,
                    CoverButtonIcon.down,
                  ),
              ],
            ),
            if (_failed)
              Text(
                l10n.shortcutNotConfirmed,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (!ready)
              Text(
                connection == MqttStatus.connected
                    ? l10n.reliabilityLastKnown
                    : l10n.reliabilityControlsUnavailable,
              ),
          ],
        ),
      ),
    );
  }
}
