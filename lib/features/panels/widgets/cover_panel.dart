import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart' as mc;

import '../../../core/l10n/l10n_ext.dart';
import '../../../data/database/database.dart';
import '../../../mqtt/json_path.dart';
import '../models/panel_config.dart';
import '../providers/panel_value_provider.dart';
import 'control_action.dart';
import 'cover_button_icon.dart';
import 'wirenboard_cover_panel.dart';

/// Resolves which cover command a [SegmentedButton] selection change maps to.
///
/// Material's [SegmentedButton] (with `emptySelectionAllowed: true`) emits an
/// EMPTY selection when the user re-taps the segment that is already selected.
/// The selected segment mirrors the device's current [state], so an empty
/// selection means "re-issue the command for the current state" — not "do
/// nothing". Otherwise the button matching the live state (e.g. OPEN while the
/// cover is open) would be dead.
String? resolveCoverAction(Set<String> selection, String? state) =>
    selection.isNotEmpty ? selection.first : state;

class CoverPanel extends ConsumerStatefulWidget {
  const CoverPanel({
    super.key,
    required this.connectionId,
    required this.publishTopic,
    required this.subscribeTopic,
    required this.panel,
    required this.config,
  });

  final String connectionId;
  final String publishTopic;
  final String subscribeTopic;
  final Panel panel;
  final CoverConfig config;

  @override
  ConsumerState<CoverPanel> createState() => _CoverPanelState();
}

class _CoverPanelState extends ConsumerState<CoverPanel> {
  double? _draggingValue;
  Timer? _debounce;
  Timer? _confirmationTimeout;
  String? _pending;
  DateTime? _sentAt;
  int? _generation;
  int _request = 0;

  @override
  void didUpdateWidget(CoverPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionId != widget.connectionId ||
        oldWidget.config.waitForFeedback != widget.config.waitForFeedback ||
        oldWidget.subscribeTopic != widget.subscribeTopic ||
        oldWidget.publishTopic != widget.publishTopic ||
        oldWidget.config.wirenBoard?.openTopic !=
            widget.config.wirenBoard?.openTopic) {
      _debounce?.cancel();
      _confirmationTimeout?.cancel();
      _request++;
      _pending = null;
      _sentAt = null;
      _draggingValue = null;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _confirmationTimeout?.cancel();
    super.dispose();
  }

  Future<void> _publishRaw(String payload, String action) async {
    final request = ++_request;
    _confirmationTimeout?.cancel();
    setState(() {
      _pending = action;
      _sentAt = null;
    });
    void finish() {
      if (!mounted || request != _request) return;
      _confirmationTimeout?.cancel();
      setState(() => _pending = null);
    }

    if (widget.config.waitForFeedback) {
      _confirmationTimeout = Timer(const Duration(seconds: 15), () {
        finish();
        if (mounted && request == _request) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.shortcutNotConfirmed)),
          );
        }
      });
    }
    try {
      await runControlAction(context, ref, widget.connectionId, (mgr) {
        if (!mounted || request != _request || _pending == null) return;
        _sentAt = DateTime.now();
        _generation = mgr.connectionGeneration;
        mgr.publish(
          widget.publishTopic,
          payload,
          '',
          qos: mc.MqttQos.values[widget.panel.qos.clamp(0, 2)],
          retain: widget.panel.retain,
        );
        if (!widget.config.waitForFeedback) {
          _confirmationTimeout = Timer(const Duration(seconds: 1), finish);
        }
      });
      if (_sentAt == null) finish();
    } catch (_) {
      finish();
    }
  }

  Future<void> _publishPosition(double v) async {
    await runControlAction(
      context,
      ref,
      widget.connectionId,
      (mgr) => mgr.publish(
        widget.publishTopic,
        widget.config.positionTemplate,
        v.round(),
        qos: mc.MqttQos.values[widget.panel.qos.clamp(0, 2)],
        retain: widget.panel.retain,
      ),
    );
  }

  void _onSliderChanged(double v) {
    setState(() => _draggingValue = v);
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 200),
      () => _publishPosition(v),
    );
  }

  void _onSliderEnd(double v) {
    _debounce?.cancel();
    _publishPosition(v);
    setState(() => _draggingValue = null);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.config.wirenBoard != null) {
      return WirenBoardCoverPanel(
        connectionId: widget.connectionId,
        panel: widget.panel,
        config: widget.config,
      );
    }
    final cfg = widget.config;
    // Command-only covers do not subscribe to device state.
    final valueAsync = cfg.waitForFeedback
        ? ref.watch(
            panelValueProvider(
              PanelStreamKey(
                connectionId: widget.connectionId,
                topic: widget.subscribeTopic,
                jsonPath: null,
              ),
            ),
          )
        : const AsyncValue<Object?>.data(null);

    final feedbackKey = PanelStreamKey(
      connectionId: widget.connectionId,
      topic: widget.subscribeTopic,
      jsonPath: null,
    );
    if (cfg.waitForFeedback) {
      ref.listen(panelValueSnapshotProvider(feedbackKey), (_, next) {
        final message = next.valueOrNull;
        if (_pending == null ||
            _sentAt == null ||
            message == null ||
            message.freshness != PanelFreshness.fresh ||
            message.connectionGeneration != _generation ||
            !message.receivedAt.isAfter(_sentAt!)) {
          return;
        }
        final reported = extractByPath(
          message.value.toString(),
          cfg.statePath,
        )?.toString().toUpperCase();
        final confirmed = switch (_pending) {
          'OPEN' => const ['OPEN', 'OPENING'].contains(reported),
          'CLOSE' => const ['CLOSE', 'CLOSED', 'CLOSING'].contains(reported),
          'STOP' => const ['STOP', 'STOPPED'].contains(reported),
          _ => false,
        };
        if (confirmed) {
          _confirmationTimeout?.cancel();
          setState(() => _pending = null);
        }
      });
    }
    Widget buttonIcon(String action, CoverButtonIcon icon) => _pending == action
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              semanticsLabel: context.l10n.shortcutWorking,
            ),
          )
        : CoverButtonGlyph(icon);
    String? state;
    double? position;
    valueAsync.whenData((raw) {
      if (raw == null) return;
      state = extractByPath(raw.toString(), cfg.statePath)?.toString();
      final p = extractByPath(raw.toString(), cfg.positionPath);
      if (p is num) {
        position = p.toDouble();
      } else if (p != null) {
        position = double.tryParse(p.toString());
      }
    });

    final liveValue = (_draggingValue ?? position ?? 0)
        .clamp(0, 100)
        .toDouble();
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.panel.name,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (cfg.waitForFeedback)
                  Text(
                    position == null ? '—' : '${position!.round()} %',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (cfg.openButton.visible ||
                cfg.closeButton.visible ||
                cfg.stopButton.visible)
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  emptySelectionAllowed: true,
                  showSelectedIcon: false,
                  segments: [
                    if (cfg.openButton.visible)
                      ButtonSegment(
                        value: 'OPEN',
                        label: Text(
                          cfg.openButton.title?.trim().isNotEmpty == true
                              ? cfg.openButton.title!
                              : context.l10n.panelCoverOpen,
                        ),
                        icon: buttonIcon(
                          'OPEN',
                          cfg.openButton.icon ?? CoverButtonIcon.up,
                        ),
                      ),
                    if (cfg.stopButton.visible)
                      ButtonSegment(
                        value: 'STOP',
                        label: Text(
                          cfg.stopButton.title?.trim().isNotEmpty == true
                              ? cfg.stopButton.title!
                              : context.l10n.panelCoverStop,
                        ),
                        icon: buttonIcon(
                          'STOP',
                          cfg.stopButton.icon ?? CoverButtonIcon.stop,
                        ),
                      ),
                    if (cfg.closeButton.visible)
                      ButtonSegment(
                        value: 'CLOSE',
                        label: Text(
                          cfg.closeButton.title?.trim().isNotEmpty == true
                              ? cfg.closeButton.title!
                              : context.l10n.panelCoverClose,
                        ),
                        icon: buttonIcon(
                          'CLOSE',
                          cfg.closeButton.icon ?? CoverButtonIcon.down,
                        ),
                      ),
                  ],
                  selected: {
                    if (state == 'OPEN' && cfg.openButton.visible) 'OPEN',
                    if (state == 'CLOSE' && cfg.closeButton.visible) 'CLOSE',
                    if (state == 'STOP' && cfg.stopButton.visible) 'STOP',
                  },
                  onSelectionChanged: (sel) {
                    switch (resolveCoverAction(sel, state)) {
                      case 'OPEN':
                        _publishRaw(cfg.openPayload, 'OPEN');
                      case 'STOP':
                        _publishRaw(cfg.stopPayload, 'STOP');
                      case 'CLOSE':
                        _publishRaw(cfg.closePayload, 'CLOSE');
                    }
                  },
                ),
              ),
            const SizedBox(height: 12),
            if (cfg.waitForFeedback && cfg.presets.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: cfg.presets
                    .map(
                      (p) => ActionChip(
                        label: Text('$p%'),
                        onPressed: () => _publishPosition(p.toDouble()),
                      ),
                    )
                    .toList(),
              ),
            if (cfg.waitForFeedback && cfg.showSlider) ...[
              // Merged so the slider node itself carries the panel name.
              MergeSemantics(
                child: Semantics(
                  label: widget.panel.name,
                  child: Slider(
                    value: liveValue,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: '${liveValue.round()}',
                    semanticFormatterCallback: (v) => '${v.round()}%',
                    onChanged: _onSliderChanged,
                    onChangeEnd: _onSliderEnd,
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('0', style: TextStyle(color: scheme.outline)),
                  Text('100', style: TextStyle(color: scheme.outline)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
