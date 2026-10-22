import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart' as mc;

import '../../../core/l10n/l10n_ext.dart';
import '../../../data/database/database.dart';
import '../../discovery/models/wirenboard_device.dart';
import '../../discovery/providers/wirenboard_discovery_provider.dart';
import '../../devices/device_profile.dart';
import '../../devices/device_state.dart';
import '../providers/panel_value_provider.dart';
import '../models/panel_config.dart';
import '../models/device_display_properties.dart';
import 'control_action.dart';
import 'device_tile_panel.dart';
import 'wirenboard_control_row.dart';

/// Uses the same dashboard card as Zigbee2MQTT, with WB scalar commands.
class WirenBoardDevicePanel extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final device = _currentDevice(ref, connectionId, config);
    final visible =
        config.display.properties ?? defaultWirenBoardDisplayProperties(device);
    final controls = device.controls
        .where((c) => visible.contains(c.id))
        .toList();
    final language = Localizations.localeOf(context).languageCode;
    final labels = {
      for (final c in controls)
        c.id: config.display.label(c.id, c.title(language)),
    };
    final features = <DeviceFeature>[];
    final values = <String, Object?>{};
    for (final control in controls) {
      final payload = ref
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
      final numeric = control.numeric;
      final toggle = control.type == 'switch' && !control.readOnly;
      features.add(
        DeviceFeature(
          type: toggle
              ? 'binary'
              : numeric
              ? 'numeric'
              : 'text',
          property: control.id,
          name: toggle ? 'state' : control.id,
          access: accessState | (toggle ? accessSet : 0),
          unit: control.unit,
          valueOn: '1',
          valueOff: '0',
        ),
      );
      if (payload != null) {
        final number = numeric ? num.tryParse(payload.toString()) : null;
        // WB scalar readings can contain NaN/Infinity, unlike JSON numbers.
        values[control.id] = number != null && number.isFinite
            ? number
            : payload;
      }
    }
    final hasSwitch = features.any((f) => f.name == 'state' && f.settable);
    final climate = device.controls.any(
      (c) => c.type == 'temperature' || c.type == 'rel_humidity',
    );
    final profile = DeviceProfile(
      deviceClass: hasSwitch
          ? DeviceClass.switchPlug
          : climate
          ? DeviceClass.climate
          : DeviceClass.generic,
      features: features,
    );
    final state = DeviceState(profile, values);
    return DeviceSummaryCard(
      name: panel.name,
      state: state,
      labels: labels,
      readings: [
        for (final control in controls)
          if (!(control.type == 'switch' && !control.readOnly))
            (
              id: control.id,
              label: labels[control.id]!,
              value: control.numeric
                  ? ltr(
                      wirenBoardValueLabel(
                        context,
                        control,
                        values[control.id],
                      ),
                    )
                  : wirenBoardValueLabel(context, control, values[control.id]),
            ),
      ],
      onToggle: (feature) {
        final control = device.controls.firstWhere(
          (c) => c.id == feature.property,
        );
        runControlAction(
          context,
          ref,
          connectionId,
          (manager) => manager.publish(
            '${control.topic}/on',
            state.isOn(feature) == true ? '0' : '1',
            '',
            qos: mc.MqttQos.values[panel.qos.clamp(0, 2)],
            retain: false,
          ),
        );
      },
      onOpen: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => WirenBoardDeviceControls(
          connectionId: connectionId,
          panel: panel,
          config: config,
        ),
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
                    label: config.display.labels[control.id],
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
