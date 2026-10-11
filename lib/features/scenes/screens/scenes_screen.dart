import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/utils/material_icon.dart';
import '../../../data/database/database.dart';
import '../../../data/database/tables/panels.dart';
import '../../../data/repositories/dashboard_repo.dart';
import '../../../data/repositories/panel_repo.dart';
import '../../discovery/models/z2m_device.dart';
import '../../panels/models/panel_config.dart';
import '../../settings/providers/settings_controller.dart'
    show sharedPreferencesProvider;
import '../all_shutters.dart';
import '../models/scene.dart';
import '../scenes_providers.dart';
import '../../home/home_shell.dart';

/// Lists a connection's scenes: the built-in "All shutters" scenes when the
/// Home has shutters (all_shutters.dart), then the saved ones. Tap a scene
/// to activate it; the FAB creates a new one by capturing device state.
class ScenesScreen extends ConsumerWidget {
  const ScenesScreen({
    super.key,
    required this.connectionId,
    this.onEdit,
    this.selectedId,
  });

  final String connectionId;

  /// Opens a scene's editor in the detail pane (list-detail) instead of
  /// pushing it; null for a new scene.
  final ValueChanged<String?>? onEdit;
  final String? selectedId;

  Future<void> _activate(
    BuildContext context,
    WidgetRef ref,
    Scene scene,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final sent = await runScene(ref, connectionId, scene);
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(
        sent > 0 ? l10n.scenesActivated(scene.name) : l10n.scenesActivateOffline,
      ),
    ));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Scene scene,
  ) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.sceneDeleteTitle),
        content: Text(l10n.sceneDeleteMessage(scene.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.sceneDeleteAction),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(sceneRepoProvider).delete(scene.id);
    }
  }

  /// Adds a scene-activation tile to a dashboard the user picks.
  Future<void> _addToDashboard(
    BuildContext context,
    WidgetRef ref,
    Scene scene,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final dashboards =
        await ref.read(dashboardRepoProvider).getByConnection(connectionId);
    if (!context.mounted) return;
    if (dashboards.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.scenesNone)));
      return;
    }
    final chosen = await showModalBottomSheet<Dashboard>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final d in dashboards)
              ListTile(
                leading: Icon(
                  materialIcon(d.iconCodepoint),
                ),
                title: Text(d.name),
                onTap: () => Navigator.pop(sheetCtx, d),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    await ref.read(panelRepoProvider).create(
          dashboardId: chosen.id,
          name: scene.name,
          type: PanelType.scene,
          topic: '',
          width: PanelWidth.small,
          config: SceneConfig(sceneId: scene.id),
        );
    messenger.showSnackBar(
        SnackBar(content: Text(l10n.sceneAddedToDashboard(chosen.name))));
  }

  /// Which of the Home's shutters the built-ins act on: all, unless unticked
  /// here. Saved at once, by device address.
  Future<void> _whichShutters(
    BuildContext context,
    WidgetRef ref,
    List<Z2mDevice> shutters,
  ) async {
    final l10n = context.l10n;
    final prefs = ref.read(sharedPreferencesProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final excluded = excludedShutters(prefs, connectionId);
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: Text(l10n.sceneWhichShutters,
                      style: Theme.of(ctx).textTheme.titleMedium),
                  subtitle: Text(l10n.sceneWhichShuttersHint),
                ),
                for (final d in shutters)
                  CheckboxListTile(
                    title: Text(d.friendlyName),
                    value: !excluded.contains(shutterKey(d)),
                    onChanged: (on) async {
                      await setShutterExcluded(prefs, connectionId,
                          key: shutterKey(d), excluded: on != true);
                      setSheetState(() {});
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
    // The list's counts read the preferences; redraw once the sheet closes.
    ref.invalidate(scenesForConnectionProvider(connectionId));
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 4),
        child: Text(text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                )),
      );

  Widget _builtInTile(
    BuildContext context,
    WidgetRef ref,
    Scene scene,
    List<Z2mDevice> shutters,
  ) {
    final l10n = context.l10n;
    final excluded =
        excludedShutters(ref.read(sharedPreferencesProvider), connectionId);
    final included = includedShutters(shutters, excluded).length;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Color(scene.colorSeed),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        child: Icon(materialIcon(scene.iconCodepoint)),
      ),
      title: Text(scene.name),
      subtitle: Text(l10n.sceneShuttersCount(included)),
      onTap: () => _activate(context, ref, scene),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'which') {
            _whichShutters(context, ref, shutters);
          } else if (v == 'dashboard') {
            _addToDashboard(context, ref, scene);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'which', child: Text(l10n.sceneWhichShutters)),
          PopupMenuItem(
              value: 'dashboard', child: Text(l10n.sceneAddToDashboard)),
        ],
      ),
    );
  }

  Widget _savedTile(BuildContext context, WidgetRef ref, Scene scene) {
    final l10n = context.l10n;
    final count = SceneAction.decodeList(scene.actions).length;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Color(scene.colorSeed),
        foregroundColor: Colors.white,
        child: Icon(
          materialIcon(scene.iconCodepoint),
        ),
      ),
      selected: scene.id == selectedId,
      title: Text(scene.name),
      subtitle: Text(l10n.sceneActionsCount(count)),
      onTap: () => _activate(context, ref, scene),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'edit') {
            final edit = onEdit;
            if (edit != null) {
              edit(scene.id);
            } else {
              context.push(
                '/connections/$connectionId/scenes/${scene.id}/edit',
              );
            }
          } else if (v == 'delete') {
            _confirmDelete(context, ref, scene);
          } else if (v == 'dashboard') {
            _addToDashboard(context, ref, scene);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'edit', child: Text(l10n.sceneEditAction)),
          PopupMenuItem(
              value: 'dashboard', child: Text(l10n.sceneAddToDashboard)),
          PopupMenuItem(value: 'delete', child: Text(l10n.sceneDeleteAction)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scenesAsync = ref.watch(scenesForConnectionProvider(connectionId));
    final shutters = ref.watch(homeShuttersProvider(connectionId));

    return Scaffold(
      appBar: AppBar(
        title: HomeTitle(connectionId: connectionId),
        actions: const [SettingsAction()],
      ),
      body: scenesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (scenes) {
          final builtIn = [
            for (final s in scenes)
              if (allShuttersCommand(s.id) != null) s,
          ];
          final saved = [
            for (final s in scenes)
              if (allShuttersCommand(s.id) == null) s,
          ];
          final showBuiltIn =
              builtIn.isNotEmpty && shutters != null && shutters.isNotEmpty;
          final none = Padding(
            padding: const EdgeInsets.all(32),
            child: Text(l10n.scenesNone, textAlign: TextAlign.center),
          );
          if (!showBuiltIn && saved.isEmpty) return Center(child: none);
          return ListView(
            children: [
              if (showBuiltIn) ...[
                _header(context, l10n.scenesAllShutters),
                for (final s in builtIn) _builtInTile(context, ref, s, shutters),
                _header(context, l10n.scenesYours),
              ],
              if (saved.isEmpty) none,
              for (final s in saved) _savedTile(context, ref, s),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => onEdit != null
            ? onEdit!(null)
            : context.push('/connections/$connectionId/scenes/new'),
        icon: const Icon(Icons.add),
        label: Text(l10n.scenesNewButton),
      ),
    );
  }
}
