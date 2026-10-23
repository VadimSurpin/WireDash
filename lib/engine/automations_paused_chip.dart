import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/l10n_ext.dart';
import '../core/router/routes.dart';
import '../features/settings/providers/settings_controller.dart' show sharedPreferencesProvider;
import 'engine_providers.dart';
import 'engine_status.dart';

/// On the dashboard when the Home's Engine is installed but paused or
/// stopped itself (CONTEXT.md: Automations paused). Only Homes that set
/// the Engine up on this phone listen, so the dashboard opens no extra
/// subscriptions for everyone else.
class AutomationsPausedBanner extends ConsumerWidget {
  const AutomationsPausedBanner({super.key, required this.connectionId});

  final String connectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!engineKnownInstalled(ref.watch(sharedPreferencesProvider), connectionId)) {
      return const SizedBox.shrink();
    }
    final view = ref.watch(engineViewProvider(connectionId)).valueOrNull;
    final phase = view?.phase;
    if (phase != HubEnginePhase.paused && phase != HubEnginePhase.stoppedSelf) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: InkWell(
        onTap: () => context.go(Routes.homeAutomations(connectionId)),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12),
          child: Row(
            children: [
              Icon(Icons.pause_circle_outline, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  phase == HubEnginePhase.stoppedSelf ? l10n.engineStoppedTitle : l10n.automationsPausedTitle,
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onErrorContainer),
            ],
          ),
        ),
      ),
    );
  }
}
