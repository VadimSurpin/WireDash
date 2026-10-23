import 'package:flutter/material.dart';

import '../../devices/screens/devices_screen.dart';

export '../widgets/add_device_sheet.dart'
    show AddDeviceSheet, showAddDeviceSheet, deviceClassLabel;

/// Add a tile from the same categorized device list used by the Devices tab.
class AddTileScreen extends StatelessWidget {
  const AddTileScreen({
    super.key,
    required this.connectionId,
    required this.dashboardId,
    required this.onCustomTile,
  });
  final String connectionId;
  final String dashboardId;
  final void Function(BuildContext context) onCustomTile;

  @override
  Widget build(BuildContext context) => DevicesScreen(
    connectionId: connectionId,
    dashboardId: dashboardId,
    onCustomTile: onCustomTile,
  );
}
