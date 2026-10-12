import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics.dart';
import '../../core/l10n/l10n_ext.dart';
import '../../data/database/database.dart';
import '../dashboards/wall_display.dart';
import '../dashboards/widgets/export_dialog.dart';
import 'kiosk.dart';
import 'kiosk_pin_dialogs.dart';

/// The Wall display sheet for one dashboard (kiosk-2.6.md): keep the screen
/// on and hide the bars, Fullscreen, Dim after, and the Kiosk lock with its
/// PIN and Android screen pinning.
Future<void> showWallDisplaySheet(
  BuildContext context,
  String connectionId,
  Dashboard dashboard,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Over the navigation bar too, not inside the home shell's body.
    useRootNavigator: true,
    builder: (_) =>
        WallDisplaySheet(connectionId: connectionId, dashboard: dashboard),
  );
}

class WallDisplaySheet extends ConsumerWidget {
  const WallDisplaySheet({
    super.key,
    required this.connectionId,
    required this.dashboard,
  });

  final String connectionId;
  final Dashboard dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final id = dashboard.id;
    final wall = ref.watch(wallDisplayProvider(id));
    final fullscreen = ref.watch(wallFullscreenProvider(id));
    final dim = ref.watch(wallDimProvider(id));
    final kiosk = ref.watch(kioskProvider);
    final locked = kiosk.dashboardId == id;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
        children: [
          ListTile(
            title: Text(l10n.wallSheetTitle, style: theme.textTheme.titleLarge),
            subtitle: Text(l10n.wallSheetSubtitle),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.light_mode_outlined),
            title: Text(l10n.wallKeepOn),
            subtitle: Text(l10n.wallKeepOnSubtitle),
            value: wall,
            onChanged: (on) =>
                ref.read(wallDisplayProvider(id).notifier).set(on),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fullscreen),
            title: Text(l10n.wallFullscreen),
            subtitle: Text(l10n.wallFullscreenSubtitle),
            value: fullscreen,
            onChanged: (on) =>
                ref.read(wallFullscreenProvider(id).notifier).set(on),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_medium_outlined),
            title: Text(l10n.wallDimAfter),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  for (final m in wallDimChoices)
                    ButtonSegment(
                      value: m,
                      label: Text(
                        m == 0 ? l10n.wallDimOff : l10n.wallDimMinutes(m),
                      ),
                    ),
                ],
                selected: {dim},
                onSelectionChanged: (s) =>
                    ref.read(wallDimProvider(id).notifier).set(s.first),
              ),
            ),
          ),
          const Divider(height: 24),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: Text(l10n.kioskLock),
            subtitle: Text(l10n.kioskLockSubtitle),
            value: locked,
            onChanged: (on) => on
                ? _startKiosk(context, ref)
                : ref.read(kioskProvider.notifier).stop(),
          ),
          ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: Text(l10n.kioskPin),
            subtitle: Text(
              kiosk.hasPin ? l10n.kioskPinSet : l10n.kioskPinNotSet,
            ),
            trailing: Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => _setPin(context, ref),
                  child: Text(
                    kiosk.hasPin ? l10n.kioskPinChange : l10n.kioskPinSet,
                  ),
                ),
                if (kiosk.hasPin)
                  TextButton(
                    onPressed: () =>
                        ref.read(kioskProvider.notifier).clearPin(),
                    child: Text(l10n.kioskPinRemove),
                  ),
              ],
            ),
          ),
          if (!kiosk.hasPin)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.kioskPinForgotBody,
                    style: theme.textTheme.bodySmall,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.save_alt),
                    label: Text(l10n.kioskExportBackup),
                    onPressed: () =>
                        showExportDashboardsDialog(context, ref, connectionId),
                  ),
                ],
              ),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.push_pin_outlined),
            title: Text(l10n.kioskOsPin),
            subtitle: Text(l10n.kioskOsPinSubtitle),
            value: kiosk.osPinning,
            onChanged: (on) =>
                ref.read(kioskProvider.notifier).setOsPinning(on),
          ),
        ],
      ),
    );
  }

  Future<void> _setPin(BuildContext context, WidgetRef ref) async {
    final pin = await askNewKioskPin(context);
    if (pin == null) return;
    await ref.read(kioskProvider.notifier).setPin(pin);
  }

  /// Turning the lock on: Fullscreen and a 5-minute Dim unless the user
  /// already chose, then kiosk starts and the sheet closes.
  Future<void> _startKiosk(BuildContext context, WidgetRef ref) async {
    final id = dashboard.id;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final fullscreen = ref.read(wallFullscreenProvider(id).notifier);
    if (!fullscreen.chosen) await fullscreen.set(true);
    final dim = ref.read(wallDimProvider(id).notifier);
    if (!dim.chosen) await dim.set(5);
    final kiosk = ref.read(kioskProvider);
    await ref.read(kioskProvider.notifier).start(connectionId, id);
    ref
        .read(analyticsProvider)
        .track(
          KioskStarted(
            pin: kiosk.hasPin,
            osPinning: kiosk.osPinning,
            dimMinutes: ref.read(wallDimProvider(id)),
          ),
        );
    if (!context.mounted) return;
    Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.kioskOn)));
  }
}

/// Leaves kiosk from the dashboard's title: the PIN when one is set, else a
/// plain confirmation. Returns true when kiosk was turned off.
Future<bool> leaveKiosk(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final kiosk = ref.read(kioskProvider.notifier);
  // The store itself, not the cached flag: right after launch the flag is
  // still being read, and this is the lock.
  final hasPin = await ref.read(kioskPinStoreProvider).read() != null;
  if (!context.mounted) return false;
  bool ok;
  if (hasPin) {
    ok = await askKioskPin(context, kiosk.checkPin);
  } else {
    ok =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.kioskLeaveTitle),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.kioskStay),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.kioskLeave),
              ),
            ],
          ),
        ) ??
        false;
  }
  if (ok) await kiosk.stop();
  return ok;
}
