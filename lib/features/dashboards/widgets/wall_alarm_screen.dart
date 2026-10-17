import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/theme/signal_colors.dart';
import '../wall_sensors.dart';

/// Alarm takeover (wall-tablet-2.9.md §6): the whole wall screen in the
/// attention colour, what happened and where, until someone taps OK.
class WallAlarmScreen extends StatelessWidget {
  const WallAlarmScreen({
    super.key,
    required this.kind,
    required this.deviceName,
    required this.onOk,
  });

  final WallAlarmKind kind;
  final String deviceName;
  final VoidCallback onOk;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = SignalColors.of(context);
    final text = Theme.of(context).textTheme;
    final what = switch (kind) {
      WallAlarmKind.leak => l10n.wallAlarmLeak,
      WallAlarmKind.smoke => l10n.wallAlarmSmoke,
      WallAlarmKind.gas => l10n.wallAlarmGas,
      WallAlarmKind.co => l10n.wallAlarmCo,
    };
    final icon = switch (kind) {
      WallAlarmKind.leak => Icons.water_drop_outlined,
      WallAlarmKind.smoke => Icons.local_fire_department_outlined,
      WallAlarmKind.gas || WallAlarmKind.co => Icons.warning_amber_rounded,
    };
    return Semantics(
      liveRegion: true,
      child: Material(
        color: colors.attention,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 96, color: colors.onAttention),
                  const SizedBox(height: 24),
                  Text(
                    what,
                    textAlign: TextAlign.center,
                    style: text.displayMedium?.copyWith(
                      color: colors.onAttention,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    deviceName,
                    textAlign: TextAlign.center,
                    style: text.headlineSmall?.copyWith(
                      color: colors.onAttention,
                    ),
                  ),
                  const SizedBox(height: 40),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.onAttention,
                      foregroundColor: colors.attention,
                      minimumSize: const Size(200, 64),
                      textStyle: text.titleLarge,
                    ),
                    onPressed: onOk,
                    child: Text(l10n.wallAlarmOk),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
