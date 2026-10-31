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
  const CarAction(
    this.id,
    this.title,
    this.icon,
    this.commands, {
    this.iconCodepoint,
    this.colorArgb,
    this.position,
    this.stateMatch,
  });
  final String id, title, icon;
  final List<CarCommand> commands;
  final int? iconCodepoint, colorArgb;
  final int? position;
  final String? stateMatch;
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'icon': icon,
    if (iconCodepoint != null) 'iconCodepoint': iconCodepoint,
    if (colorArgb != null) 'colorArgb': colorArgb,
    if (position != null) 'position': position,
    if (stateMatch != null) 'stateMatch': stateMatch,
  };
}

class CarControl {
  const CarControl({
    required this.id,
    required this.name,
    required this.kind,
    required this.actions,
    this.sectionId,
    this.topics = const [],
    this.path,
    this.positionPath,
    this.onMatch = 'ON',
    this.waitForFeedback = true,
    this.binding,
  });
  final String id, name, kind;
  final String? sectionId;
  final List<CarAction> actions;
  final List<String> topics;
  final String? path;
  final String? positionPath;
  final String onMatch;
  final bool waitForFeedback;
  final WirenBoardCoverBinding? binding;

  /// A phone-side edit invalidates a pending command if its meaning changed.
  String get commandSignature => jsonEncode({
    'wait': waitForFeedback,
    'topics': topics,
    'path': path,
    'positionPath': positionPath,
    'on': onMatch,
    'binding': binding?.toJson(),
    'actions': [
      for (final a in actions)
        {
          'id': a.id,
          'position': a.position,
          'stateMatch': a.stateMatch,
          'commands': [
            for (final c in a.commands) [c.topic, c.payload, c.retain, c.qos],
          ],
        },
    ],
  });
}

/// The car exposes simple IoT actions. Editors, text input, schedules and
/// continuous sliders remain on the phone; cover positions use preset buttons.
/// Existing dashboard order and button choices
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
        CarCommand off, {
        int? onIcon,
        int? offIcon,
      }) => CarControl(
        id: id,
        name: name,
        kind: 'switch',
        sectionId: panel.sectionId,
        topics: [topic],
        path: path,
        onMatch: onMatch,
        actions: [
          CarAction('ON', l10n.panelStateOn, 'on', [on], iconCodepoint: onIcon),
          CarAction('OFF', l10n.panelStateOff, 'off', [
            off,
          ], iconCodepoint: offIcon),
        ],
      );
      CarControl cover(
        String id,
        String name,
        CoverConfig cfg, {
        bool positionSupported = true,
      }) {
        final wb = cfg.wirenBoard;
        final positions = wb == null && cfg.waitForFeedback && positionSupported
            ? (cfg.presets.isNotEmpty
                      ? cfg.presets
                      : cfg.showSlider
                      ? const [0, 25, 50, 75, 100]
                      : const <int>[])
                  .where((p) => p >= 0 && p <= 100)
                  .toSet()
                  .toList()
            : const <int>[];
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
          sectionId: panel.sectionId,
          waitForFeedback: cfg.waitForFeedback,
          binding: wb,
          topics: !cfg.waitForFeedback
              ? []
              : wb == null
              ? [subscribe]
              : [wb.openTopic, wb.closeTopic],
          path: cfg.statePath,
          positionPath: positions.isEmpty ? null : cfg.positionPath,
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
            for (final position in positions)
              CarAction(
                'POSITION_$position',
                '$position%',
                position == 0 ? 'rollerClosed' : 'rollerOpen',
                [
                  command(
                    cfg.positionTemplate.replaceAll('{value}', '$position'),
                  ),
                ],
                position: position,
              ),
          ],
        );
      }

      switch (config) {
        case PluginPanelConfig c when c.pluginId == 'wiredash.video':
          // Only expose identity/presentation to the car host. Camera URLs,
          // recorder addresses and secure login references remain on the phone.
          result.add(
            CarControl(
              id: panel.id,
              name: panel.name,
              kind: 'video',
              sectionId: panel.sectionId,
              waitForFeedback: false,
              actions: const [CarAction('VIEW', 'Video', 'video', [])],
            ),
          );
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
              onIcon: c.onIconCodepoint,
              offIcon: c.offIconCodepoint,
            ),
          );
        case ButtonConfig c:
          result.add(
            CarControl(
              id: panel.id,
              name: panel.name,
              kind: 'button',
              sectionId: panel.sectionId,
              waitForFeedback: false,
              actions: [
                CarAction(
                  'PRESS',
                  panel.name,
                  'send',
                  [command(c.payload)],
                  iconCodepoint: c.iconCodepoint,
                  colorArgb: c.colorArgb,
                ),
              ],
            ),
          );
        case CoverConfig c:
          result.add(cover(panel.id, panel.name, c));
        case OptionsConfig c:
          // Radio/combo/multi-state panels include curtain-position buttons.
          // Match their saved values exactly; only legacy direction controls
          // use the historical OPEN/CLOSE/STOP normalization.
          final directions = c.options.every(
            (o) =>
                const ['OPEN', 'CLOSE', 'STOP'].contains(o.match.toUpperCase()),
          );
          if (c.options.isNotEmpty) {
            result.add(
              CarControl(
                id: panel.id,
                name: panel.name,
                kind: directions ? 'cover' : 'options',
                sectionId: panel.sectionId,
                topics: [subscribe],
                path: c.jsonPath,
                actions: [
                  for (final (index, option) in c.options.indexed)
                    CarAction(
                      directions ? option.match.toUpperCase() : 'OPTION_$index',
                      option.label,
                      switch (option.match.toUpperCase()) {
                        'OPEN' => 'rollerOpen',
                        'CLOSE' => 'rollerClosed',
                        'STOP' => 'stop',
                        _ => 'rollerOpen',
                      },
                      [command(option.payload)],
                      stateMatch: directions ? null : option.match,
                    ),
                ],
              ),
            );
          }
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
                  sectionId: panel.sectionId,
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
            final state =
                c.profile.feature('state') ??
                c.profile.normal
                    .where(
                      (f) =>
                          f.name == 'state' &&
                          f.parent == 'cover' &&
                          f.settable,
                    )
                    .firstOrNull;
            final position = c.profile.position;
            bool shown(DeviceFeature? feature) =>
                feature?.settable == true &&
                (c.display.properties == null ||
                    c.display.properties!.contains(feature!.property));
            final hasState = shown(state);
            final hasPosition = shown(position);
            if (hasState || hasPosition) {
              result.add(
                cover(
                  panel.id,
                  panel.name,
                  CoverConfig(
                    statePath: state?.property ?? 'state',
                    openPayload: jsonEncode({
                      state?.property ?? 'state': 'OPEN',
                    }),
                    closePayload: jsonEncode({
                      state?.property ?? 'state': 'CLOSE',
                    }),
                    stopPayload: jsonEncode({
                      state?.property ?? 'state': 'STOP',
                    }),
                    openButton: CoverButtonConfig(visible: hasState),
                    closeButton: CoverButtonConfig(visible: hasState),
                    stopButton: CoverButtonConfig(visible: hasState),
                    positionPath: position?.property ?? 'position',
                    positionTemplate:
                        '{${jsonEncode(position?.property ?? 'position')}:{value}}',
                  ),
                  positionSupported: hasPosition,
                ),
              );
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
