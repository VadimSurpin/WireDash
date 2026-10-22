import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/l10n_ext.dart';
import '../core/router/routes.dart';
import '../features/settings/providers/settings_controller.dart' show sharedPreferencesProvider;
import '../l10n/app_localizations.dart';
import 'engine_installer.dart';
import 'engine_providers.dart';
import 'engine_status.dart';

/// The Automations screen (zigdash-3.0.md §1, §2). Phase 1: the Engine's
/// install, consent and health. The list and editor arrive in phase 2.
class AutomationsScreen extends ConsumerStatefulWidget {
  const AutomationsScreen({super.key, required this.connectionId});

  final String connectionId;

  @override
  ConsumerState<AutomationsScreen> createState() => _AutomationsScreenState();
}

enum _Busy { none, installing, restarting }

class _AutomationsScreenState extends ConsumerState<AutomationsScreen> {
  _Busy _busy = _Busy.none;
  String? _error;

  Future<void> _install() async {
    setState(() {
      _busy = _Busy.installing;
      _error = null;
    });
    final l10n = context.l10n;
    try {
      final installer = await ref.read(engineInstallerProvider(widget.connectionId).future);
      final source = await ref.read(engineSourceProvider.future);
      final (answer, error) = await installer.install(source);
      if (!mounted) return;
      setState(() => _error = switch (answer) {
            HubAnswer.ok => null,
            HubAnswer.refused => l10n.engineInstallRefused(error ?? ''),
            HubAnswer.noAnswer => l10n.engineInstallNoAnswer,
          });
    } catch (_) {
      if (mounted) setState(() => _error = l10n.engineInstallNoAnswer);
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  Future<void> _consent() async {
    setState(() {
      _busy = _Busy.restarting;
      _error = null;
    });
    final l10n = context.l10n;
    await setEngineDeclined(ref.read(sharedPreferencesProvider), widget.connectionId, false);
    try {
      final installer = await ref.read(engineInstallerProvider(widget.connectionId).future);
      final answer = await installer.allowExtensionsAndRestart();
      if (!mounted) return;
      if (answer != HubAnswer.ok) {
        setState(() {
          _busy = _Busy.none;
          _error = l10n.engineConsentFailed;
        });
        return;
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = _Busy.none;
          _error = l10n.engineConsentFailed;
        });
      }
      return;
    }
    if (mounted) await _install();
  }

  Future<void> _decline() async {
    await setEngineDeclined(ref.read(sharedPreferencesProvider), widget.connectionId, true);
    ref.invalidate(engineViewProvider(widget.connectionId));
  }

  Future<void> _startAgain() async {
    final installer = await ref.read(engineInstallerProvider(widget.connectionId).future);
    installer.startAgain();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final view = ref.watch(engineViewProvider(widget.connectionId));
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.automationsTitle),
        actions: [
          if (view.valueOrNull?.phase == HubEnginePhase.running)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 16),
              child: Chip(label: Text(l10n.engineRunningOnHub)),
            ),
        ],
      ),
      body: view.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _Message(title: l10n.engineChecking, body: l10n.engineNoConnection),
        data: (v) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ..._body(context, l10n, v),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, AppLocalizations l10n, EngineView v) {
    if (_busy == _Busy.restarting) {
      return [_Progress(text: l10n.engineRestarting)];
    }
    if (_busy == _Busy.installing) {
      return [_Progress(text: l10n.engineInstalling)];
    }
    switch (v.phase) {
      case HubEnginePhase.checking:
        return [_Progress(text: l10n.engineChecking)];
      case HubEnginePhase.tooOld:
        return [
          _Message(
            title: l10n.engineTooOldTitle,
            body: l10n.engineTooOldBody(v.hub?.version ?? '?'),
          ),
        ];
      case HubEnginePhase.notInstalled:
        return [
          _Message(title: l10n.engineIntroTitle, body: l10n.engineIntroBody),
          _Bullets([
            l10n.engineIntroNothingByHand,
            l10n.engineIntroVersion(v.hub?.version ?? '?'),
            l10n.engineIntroRemove,
          ]),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('engine-install'),
            onPressed: _install,
            child: Text(l10n.engineInstall),
          ),
        ];
      case HubEnginePhase.needsConsent:
        if (v.declined) {
          return [
            _Message(title: l10n.engineDeclinedTitle, body: l10n.engineDeclinedBody),
            const SizedBox(height: 16),
            FilledButton.tonal(
              key: const Key('engine-allow-after-all'),
              onPressed: _consent,
              child: Text(l10n.engineAllowAfterAll),
            ),
          ];
        }
        return [
          _Message(title: l10n.engineConsentTitle, body: l10n.engineConsentBody),
          _Bullets([l10n.engineConsentOutage, l10n.engineConsentOpen, l10n.engineConsentUndo]),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('engine-consent'),
            onPressed: _consent,
            child: Text(l10n.engineConsentYes),
          ),
          TextButton(
            key: const Key('engine-decline'),
            onPressed: _decline,
            child: Text(l10n.engineConsentNo),
          ),
        ];
      case HubEnginePhase.paused:
        return [
          _Alert(
            title: l10n.automationsPausedTitle,
            body: l10n.automationsPausedBody,
            action: l10n.engineReinstall,
            onAction: _install,
          ),
        ];
      case HubEnginePhase.stoppedSelf:
        return [
          _Alert(
            title: l10n.engineStoppedTitle,
            body: l10n.engineStoppedBody,
            action: l10n.engineStartAgain,
            onAction: _startAgain,
            secondary: l10n.engineReportProblem,
            onSecondary: () => context.push(Routes.getHelpFrom('automations', home: widget.connectionId)),
          ),
        ];
      case HubEnginePhase.running:
        final r = v.report;
        return [
          _Message(
            title: l10n.engineRunningTitle,
            body: l10n.engineRunningBody(r?.rulesLoaded ?? 0),
          ),
          if (v.clockOff) ...[
            const SizedBox(height: 12),
            Text(l10n.engineClockOff, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if ((r?.rulesUnknown ?? const []).isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(l10n.engineRulesUnknown(r!.rulesUnknown.length)),
          ],
        ];
    }
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(body, style: theme.textTheme.bodyLarge),
      ],
    );
  }
}

class _Bullets extends StatelessWidget {
  const _Bullets(this.items);
  final List<String> items;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final i in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(i)),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _Alert extends StatelessWidget {
  const _Alert({
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
    this.secondary,
    this.onSecondary,
  });
  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;
  final String? secondary;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onErrorContainer)),
            const SizedBox(height: 8),
            Text(body, style: TextStyle(color: scheme.onErrorContainer)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonal(onPressed: onAction, child: Text(action)),
                if (secondary != null) TextButton(onPressed: onSecondary, child: Text(secondary!)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
