import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../data/database/tables/panels.dart';
import '../../devices/device_profile.dart';
import '../../devices/device_tiles.dart';
import '../../discovery/models/device_panel_suggestion.dart';
import '../../discovery/models/wirenboard_device.dart';
import '../../discovery/models/wirenboard_panel_suggestion.dart';
import '../../discovery/models/z2m_device.dart';
import '../../discovery/providers/discovery_provider.dart';
import '../../discovery/providers/wirenboard_discovery_provider.dart';
import '../../discovery/wirenboard_device_groups.dart';
import 'device_tile_panel.dart' show deviceClassIcon;

typedef PanelDevicePick = ({Z2mDevice? z2m, PanelSuggestion? suggestion});

/// Selects topics for the existing tile from either discovery source.
class PanelDevicePicker extends ConsumerStatefulWidget {
  const PanelDevicePicker({
    super.key,
    required this.connectionId,
    required this.base,
    required this.type,
  });

  final String connectionId;
  final String base;
  final PanelType type;

  @override
  ConsumerState<PanelDevicePicker> createState() => _PanelDevicePickerState();
}

class _PanelDevicePickerState extends ConsumerState<PanelDevicePicker> {
  String _query = '';

  void _pickProperty(WirenBoardDevice device, WirenBoardControl control) {
    final suggestion = suggestWirenBoardPanel(
      device,
      control,
      language: context.l10n.localeName,
    );
    final selected = suggestion.widgetChoices
        .where((choice) => choice.type == widget.type)
        .firstOrNull;
    Navigator.pop<PanelDevicePick>(context, (
      z2m: null,
      suggestion: selected == null
          ? suggestion
          : suggestWirenBoardPanel(
              device,
              control,
              language: context.l10n.localeName,
              widgetType: selected.type,
            ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final args = (connectionId: widget.connectionId, base: widget.base);
    final z2m = ref.watch(bridgeDevicesStreamProvider(args));
    final wb = ref.watch(classifiedWirenBoardDevicesProvider(args));
    final devices = z2m.valueOrNull ?? const <Z2mDevice>[];
    final wbDevices = wb.valueOrNull ?? const <WirenBoardDevice>[];
    bool matches(String text) => text.toLowerCase().contains(_query);
    final shown = devices.where((d) => matches(d.friendlyName));
    final wbShown = wbDevices.where(
      (d) =>
          matches(d.id) ||
          matches(d.title(l10n.localeName)) ||
          d.controls.any(
            (c) => matches(c.id) || matches(c.title(l10n.localeName)),
          ),
    );
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SearchBar(
                hintText: l10n.addTileSearch,
                leading: const Icon(Icons.search),
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
              ),
            ),
            if (z2m.isLoading || wb.isLoading) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                children: [
                  if (shown.isEmpty &&
                      wbShown.isEmpty &&
                      !z2m.isLoading &&
                      !wb.isLoading)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.devicesNoMatch,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (shown.isNotEmpty)
                    ExpansionTile(
                      key: ValueKey('z2m-$_query'),
                      initiallyExpanded: _query.isNotEmpty,
                      title: const Text('Zigbee2MQTT'),
                      children: [
                        for (final device in shown)
                          ListTile(
                            leading: Icon(
                              deviceClassIcon(
                                classifyExposes(device.rawExposes).deviceClass,
                              ),
                            ),
                            title: Text(device.friendlyName),
                            subtitle: deviceModelLabel(device) == null
                                ? null
                                : Text(deviceModelLabel(device)!),
                            onTap: () => Navigator.pop<PanelDevicePick>(
                              context,
                              (z2m: device, suggestion: null),
                            ),
                          ),
                      ],
                    ),
                  for (final group in WirenBoardDeviceGroup.values)
                    if (wbShown.any((d) => d.group == group))
                      ExpansionTile(
                        key: ValueKey('wb-${group.name}-$_query'),
                        initiallyExpanded: _query.isNotEmpty,
                        title: Text(wirenBoardGroupLabel(group, l10n)),
                        children: [
                          for (final device in wbShown.where(
                            (d) => d.group == group,
                          ))
                            ExpansionTile(
                              key: ValueKey('wb-device:${device.id}-$_query'),
                              initiallyExpanded: _query.isNotEmpty,
                              title: Text(device.title(l10n.localeName)),
                              subtitle: Text(
                                l10n.wbControlCount(device.controls.length),
                              ),
                              trailing: widget.type == PanelType.device
                                  ? IconButton(
                                      tooltip: l10n.wbAddWholeDevice,
                                      icon: const Icon(Icons.check),
                                      onPressed: () =>
                                          Navigator.pop<PanelDevicePick>(
                                            context,
                                            (
                                              z2m: null,
                                              suggestion:
                                                  suggestWirenBoardDevicePanel(
                                                    device,
                                                    language: l10n.localeName,
                                                  ),
                                            ),
                                          ),
                                    )
                                  : null,
                              children: [
                                for (final control in device.controls)
                                  if (_query.isEmpty ||
                                      matches(device.id) ||
                                      matches(device.title(l10n.localeName)) ||
                                      matches(control.id) ||
                                      matches(control.title(l10n.localeName)))
                                    ListTile(
                                      key: ValueKey(
                                        'wb-property:${device.id}/${control.id}',
                                      ),
                                      title: Text(
                                        control.title(l10n.localeName),
                                      ),
                                      subtitle: control.unit == null
                                          ? null
                                          : Text(control.unit!),
                                      onTap: () =>
                                          _pickProperty(device, control),
                                    ),
                              ],
                            ),
                        ],
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
