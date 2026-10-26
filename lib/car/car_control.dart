import 'dart:convert';

import '../data/database/database.dart';
import '../features/devices/device_profile.dart';
import '../features/discovery/models/wirenboard_curtain.dart';
import '../features/panels/models/device_display_properties.dart';
import '../features/panels/models/panel_config.dart';
import '../features/panels/providers/panel_value_provider.dart'
    show composeTopic;
import '../l10n/app_localizations.dart';

/// A car command is derived from a saved panel, never from a topic supplied by
/// the Android Auto host. MQTT IDs and raw payloads stay identical to the phone.
class CarCommand {
  const CarCommand(
    this.topic,
    this.payload, {
    this.retain = false,
    this.qos = 1,
  });
  final String topic, payload;
  final bool retain;
  final int qos;
}

class CarAction {
  const CarAction(this.id, this.title, this.icon, this.commands);
  final String id, title, icon;
  final List<CarCommand> commands;
  Map<String, Object?> toJson() => {'id': id, 'title': title, 'icon': icon};
}

class CarControl {
  const CarControl({
    required this.id,
    required this.name,
    required this.kind,
    required this.actions,
    this.topics = const [],
    this.path,
    this.onMatch = 'ON',
    this.waitForFeedback = true,
    this.binding,
  });
  final String id, name, kind;
  final List<CarAction> actions;
  final List<String> topics;
  final String? path;
  final String onMatch;
  final bool waitForFeedback;
  final WirenBoardCoverBinding? binding;

  /// A phone-side edit invalidates a pending command if its meaning changed.
  String get commandSignature => jsonEncode({
    'wait': waitForFeedback,
    'topics': topics,
    'path': path,
    'on': onMatch,
    'binding': binding?.toJson(),
    'actions': [
      for (final a in actions)
        {
          'id': a.id,
          'commands': [
            for (final c in a.commands) [c.topic, c.payload, c.retain, c.qos],
          ],
        },
    ],
  });
}

/// The car exposes simple IoT actions. Editors, text input, schedules and
/// sliders remain on the phone. Existing dashboard order and button choices
/// are retained. A malformed panel cannot hide all the other controls.
List<CarControl> carControls(
  Dashboard dashboard,
  List<Panel> panels,
  AppLocalizations l10n,
) {
  final result = <CarControl>[];
  for (final panel in panels) {
    try {
      final config = PanelConfig.decode(panel.type, panel.config);
      final prefix = panel.topicPrefixOverride ?? dashboard.topicPrefix;
      final publish = composeTopic(prefix, panel.topic);
      final subscribe = composeTopic(
        prefix,
        panel.subscribeTopic ?? panel.topic,
      );
      CarCommand command(String payload) => CarCommand(
        publish,
        payload,
        retain: panel.retain,
        qos: panel.qos.clamp(0, 2),
      );
      CarControl toggle(
        String id,
        String name,
        String topic,
        String? path,
        String onMatch,
        CarCommand on,
        CarCommand off,
      ) => CarControl(
        id: id,
        name: name,
        kind: 'switch',
        topics: [topic],
        path: path,
        onMatch: onMatch,
        actions: [
          CarAction('ON', l10n.panelStateOn, 'on', [on]),
          CarAction('OFF', l10n.panelStateOff, 'off', [off]),
        ],
      );
      CarControl cover(String id, String name, CoverConfig cfg) {
        final wb = cfg.wirenBoard;
        List<CarCommand> commands(String action, String payload) => wb == null
            ? [command(payload)]
            : [
                if (action == 'OPEN' || action == 'STOP')
                  CarCommand(
                    '${wb.openTopic}/on',
                    action == 'STOP' ? '0' : '1',
                    qos: panel.qos.clamp(1, 2),
                  ),
                if (action == 'CLOSE' || action == 'STOP')
                  CarCommand(
                    '${wb.closeTopic}/on',
                    action == 'STOP' ? '0' : '1',
                    qos: panel.qos.clamp(1, 2),
                  ),
              ];
        CarAction action(
          String id,
          CoverButtonConfig setting,
          String title,
          String icon,
          String payload,
        ) => CarAction(
          id,
          setting.title?.trim().isNotEmpty == true ? setting.title! : title,
          setting.icon?.name ?? icon,
          commands(id, payload),
        );
        return CarControl(
          id: id,
          name: name,
          kind: 'cover',
          waitForFeedback: cfg.waitForFeedback,
          binding: wb,
          topics: !cfg.waitForFeedback
              ? []
              : wb == null
              ? [subscribe]
              : [wb.openTopic, wb.closeTopic],
          path: cfg.statePath,
          actions: [
            if (cfg.openButton.visible)
              action(
                'OPEN',
                cfg.openButton,
                l10n.panelCoverOpen,
                'rollerOpen',
                cfg.openPayload,
              ),
            if (cfg.closeButton.visible)
              action(
                'CLOSE',
                cfg.closeButton,
                l10n.panelCoverClose,
                'rollerClosed',
                cfg.closePayload,
              ),
            if (cfg.stopButton.visible)
              action(
                'STOP',
                cfg.stopButton,
                l10n.panelCoverStop,
                'stop',
                cfg.stopPayload,
              ),
          ],
        );
      }

      switch (config) {
        case ToggleConfig c:
          result.add(
            toggle(
              panel.id,
              panel.name,
              subscribe,
              c.jsonPath,
              c.onMatch,
              command(c.onPayload),
              command(c.offPayload),
            ),
          );
        case ButtonConfig c:
          result.add(
            CarControl(
              id: panel.id,
              name: panel.name,
              kind: 'button',
              waitForFeedback: false,
              actions: [
                CarAction('PRESS', panel.name, 'send', [command(c.payload)]),
              ],
            ),
          );
        case CoverConfig c:
          result.add(cover(panel.id, panel.name, c));
        case WirenBoardDeviceConfig c:
          final device = c.visibleDevice(c.device);
          final visible =
              c.display.properties ??
              defaultWirenBoardDisplayProperties(device);
          final pairs = <int>{};
          for (final control in device.controls) {
            if (!visible.contains(control.id) || control.readOnly) continue;
            final title =
                '${panel.name} · ${c.display.label(control.id, control.title(l10n.localeName))}';
            final pair = wirenBoardCurtainFor(device, control);
            if (pair != null) {
              if (pairs.add(pair.number)) {
                result.add(
                  cover(
                    '${panel.id}/curtain/${pair.number}',
                    '${panel.name} · ${pair.number}',
                    CoverConfig(
                      wirenBoard: pair,
                      stopButton: const CoverButtonConfig(visible: false),
                    ),
                  ),
                );
              }
            } else if (control.type == 'switch') {
              result.add(
                toggle(
                  '${panel.id}/${control.id}',
                  title,
                  control.topic,
                  null,
                  '1',
                  CarCommand('${control.topic}/on', '1'),
                  CarCommand('${control.topic}/on', '0'),
                ),
              );
            } else if (control.type == 'pushbutton') {
              result.add(
                CarControl(
                  id: '${panel.id}/${control.id}',
                  name: title,
                  kind: 'button',
                  waitForFeedback: false,
                  actions: [
                    CarAction('PRESS', title, 'send', [
                      CarCommand('${control.topic}/on', '1'),
                    ]),
                  ],
                ),
              );
            }
          }
        case DeviceTileConfig c:
          if (c.profile.deviceClass == DeviceClass.cover) {
            if (c.profile.feature('state')?.settable == true) {
              result.add(cover(panel.id, panel.name, const CoverConfig()));
            }
          } else {
            for (final feature in c.profile.switches) {
              if (c.display.properties != null &&
                  !c.display.properties!.contains(feature.property)) {
                continue;
              }
              final on = feature.valueOn ?? true,
                  off = feature.valueOff ?? false;
              result.add(
                toggle(
                  '${panel.id}/${feature.property}',
                  c.profile.switches.length == 1
                      ? panel.name
                      : '${panel.name} · ${feature.label ?? feature.property}',
                  subscribe,
                  feature.property,
                  '$on',
                  command(jsonEncode({feature.property: on})),
                  command(jsonEncode({feature.property: off})),
                ),
              );
            }
          }
        default:
          break;
      }
    } catch (_) {
      // The phone editor can repair an invalid saved panel.
    }
  }
  return result.where((control) => control.actions.isNotEmpty).toList();
}
