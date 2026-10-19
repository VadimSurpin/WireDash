import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/router/routes.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shortcuts/shortcut_service.dart' show appChannel;
import '../../connections/discovery/hub_probe.dart';
import '../../connections/discovery/no_network.dart';
import '../../panels/widgets/device_tile_panel.dart' show ltr;
import '../../settings/screens/settings_screen.dart' show privacyPolicyUrl;
import '../../support/community.dart' show CommunityLink;
import '../../support/get_help_screen.dart' show GetHelpLink;
import '../first_run.dart';
import 'recommendation_policy.dart';
import 'setup_candidate.dart';
import 'setup_coordinator.dart';
import 'setup_error_guidance.dart';
import 'setup_analytics.dart';
import 'setup_providers.dart';

/// The discovery-first onboarding flow: renders [SetupCoordinator] state and
/// forwards user intents. No network work or persistence happens here.
class SetupScreen extends ConsumerWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(setupStateProvider);
    final coordinator = ref.watch(setupCoordinatorProvider);
    final state = asyncState.valueOrNull ?? coordinator.state;
    final l10n = context.l10n;

    // No "ready" screen: a finished setup opens its dashboard directly.
    ref.listen(setupStateProvider, (previous, next) {
      final s = next.valueOrNull;
      if (s == null) return;
      final step = setupStepFor(
        previous?.valueOrNull,
        s,
        platform: coordinator.platform,
      );
      if (step != null) ref.read(analyticsProvider).track(step);
      if (s is SetupComplete) {
        context.go(Routes.homeDashboards(s.result.connectionId));
      }
    });

    void manual() {
      ref.read(analyticsProvider).track(const SetupStep(SetupStepKind.manual));
      context.push(Routes.guidedConnect);
    }

    // Manual entry filled in with a hub the scan found (2.5).
    void manualTo(HubFound hub) {
      ref.read(analyticsProvider).track(const SetupStep(SetupStepKind.manual));
      context.push(Routes.guidedConnectTo(hub.host, 1883));
    }

    Future<void> tryDemo() async {
      ref.read(analyticsProvider).track(const SetupStep(SetupStepKind.demo));
      final id = await ref.read(firstRunProvider).startDemo();
      if (context.mounted) context.go(Routes.homeDashboards(id));
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.setupWelcomeTitle)),
      body: SafeArea(
        child: switch (state) {
          SetupIdle() => _Welcome(
            onFind: coordinator.startScan,
            onManual: manual,
          ),
          SetupScanning() => _Scanning(
            state: state,
            onSelect: coordinator.selectCandidate,
            onPlatform: coordinator.setPlatform,
            onManual: manual,
          ),
          SetupScanEmpty() => _ScanEmpty(
            state: state,
            onRetry: coordinator.retry,
            onPlatform: coordinator.setPlatform,
            onCheckAddress: coordinator.checkAddress,
            onManual: manual,
            onManualTo: manualTo,
            onDemo: tryDemo,
          ),
          SetupVerifying() => const _Verifying(),
          SetupNeedsAuth() => _AuthPrompt(
            state: state,
            onSubmit: coordinator.submitCredentials,
            onDemo: tryDemo,
          ),
          SetupFailed(kind: SetupErrorKind.notZigbee2Mqtt) => _NoZigbee2Mqtt(
            base: coordinator.base,
            onRetry: coordinator.retryWithBase,
            onDemo: tryDemo,
            onManual: manual,
          ),
          SetupFailed(kind: SetupErrorKind.scanFailed) => _NoNetwork(
            state: state,
            onManual: manual,
          ),
          SetupFailed() => _Failure(
            state: state,
            onRetry: coordinator.retry,
            onManual: manual,
          ),
          SetupReview() => _Review(
            state: state,
            onToggle: coordinator.toggleDevice,
            onCreate: coordinator.createDashboard,
          ),
          SetupCreating() => _Review(
            state: state.review,
            busy: true,
            onToggle: (_) {},
            onCreate: () {},
          ),
          // Navigation to the dashboard is under way (see ref.listen above).
          SetupComplete() => const SizedBox.shrink(),
        },
      ),
    );
  }
}

/// Maps a guidance key from [SetupGuidance] to its localized string.
String _guidanceText(AppLocalizations l10n, String key) => switch (key) {
  'setupErrUnreachableTitle' => l10n.setupErrUnreachableTitle,
  'setupErrUnreachableBody' => l10n.setupErrUnreachableBody,
  'setupErrUnreachableAction' => l10n.setupErrUnreachableAction,
  'setupErrPortClosedTitle' => l10n.setupErrPortClosedTitle,
  'setupErrPortClosedBody' => l10n.setupErrPortClosedBody,
  'setupErrPortClosedAction' => l10n.setupErrPortClosedAction,
  'setupErrAuthRequiredTitle' => l10n.setupErrAuthRequiredTitle,
  'setupErrAuthRequiredBody' => l10n.setupErrAuthRequiredBody,
  'setupErrAuthRequiredAction' => l10n.setupErrAuthRequiredAction,
  'setupErrAuthRejectedTitle' => l10n.setupErrAuthRejectedTitle,
  'setupErrAuthRejectedBody' => l10n.setupErrAuthRejectedBody,
  'setupErrAuthRejectedAction' => l10n.setupErrAuthRejectedAction,
  'setupErrNotZ2mTitle' => l10n.setupErrNotZ2mTitle,
  'setupErrNotZ2mBody' => l10n.setupErrNotZ2mBody,
  'setupErrNotZ2mAction' => l10n.setupErrNotZ2mAction,
  'setupErrNoDevicesTitle' => l10n.setupErrNoDevicesTitle,
  'setupErrNoDevicesBody' => l10n.setupErrNoDevicesBody,
  'setupErrNoDevicesAction' => l10n.setupErrNoDevicesAction,
  'setupErrScanFailedTitle' => l10n.setupErrScanFailedTitle,
  'setupErrScanFailedBody' => l10n.setupErrScanFailedBody,
  'setupErrScanFailedAction' => l10n.setupErrScanFailedAction,
  'setupErrSaveFailedTitle' => l10n.setupErrSaveFailedTitle,
  'setupErrSaveFailedBody' => l10n.setupErrSaveFailedBody,
  'setupErrSaveFailedAction' => l10n.setupErrSaveFailedAction,
  'setupErrLoginNoAnswerTitle' => l10n.setupErrLoginNoAnswerTitle,
  'setupErrLoginNoAnswerBody' => l10n.setupErrLoginNoAnswerBody,
  'setupErrLoginNoAnswerAction' => l10n.setupErrLoginNoAnswerAction,
  // Missing until 2.8.2: the unknown screen read "Try again" three times.
  'setupErrUnknownTitle' => l10n.setupErrUnknownTitle,
  'setupErrUnknownBody' => l10n.setupErrUnknownBody,
  _ => l10n.setupErrUnknownAction,
};

/// The first setup screen. With an analytics key in the build and no choice
/// made yet, it carries the one usage-data question for new installs: a box
/// ticked by default (ADR 0007), recorded either way when the user moves on.
class _Welcome extends ConsumerStatefulWidget {
  const _Welcome({required this.onFind, required this.onManual});
  final VoidCallback onFind;
  final VoidCallback onManual;

  @override
  ConsumerState<_Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends ConsumerState<_Welcome> {
  bool _share = true;

  bool get _asking =>
      ref.watch(analyticsAvailableProvider) &&
      ref.watch(analyticsConsentProvider) == AnalyticsConsent.unasked;

  Future<void> _then(VoidCallback next) async {
    if (_asking) {
      await ref.read(analyticsConsentProvider.notifier).set(_share);
    }
    next();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    void onFind() => _then(widget.onFind);
    void onManual() => _then(widget.onManual);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 32),
        Icon(
          Icons.home_outlined,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          l10n.setupWelcomeHeadline,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(
          l10n.setupWelcomeBody,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: onFind,
          icon: const Icon(Icons.wifi_find),
          label: Text(l10n.setupFindMySetup),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: onManual, child: Text(l10n.setupManualEntry)),
        if (_asking) ...[
          const SizedBox(height: 24),
          CheckboxListTile(
            value: _share,
            onChanged: (v) => setState(() => _share = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.analyticsSetupCheckbox),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => launchUrl(
                usageDataPolicyUrl,
                mode: LaunchMode.externalApplication,
              ),
              child: Text(l10n.analyticsWhatsShared),
            ),
          ),
        ],
      ],
    );
  }
}

class _Scanning extends StatelessWidget {
  const _Scanning({
    required this.state,
    required this.onSelect,
    required this.onPlatform,
    required this.onManual,
  });
  final SetupScanning state;
  final ValueChanged<SetupCandidate> onSelect;
  final ValueChanged<SetupPlatform?> onPlatform;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final progress = state.progress;
    final hint = switch (state.platform) {
      _ when state.done => l10n.setupScanDoneHint,
      SetupPlatform.homeAssistant => l10n.setupScanHintHa,
      SetupPlatform.smlight => l10n.setupScanHintSmlight,
      SetupPlatform.piOrDocker => l10n.setupScanHintPi,
      _ => l10n.setupScanningHint,
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            state.done ? l10n.setupScanDoneTitle : l10n.setupScanningTitle,
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        Text(hint, style: theme.textTheme.bodyMedium),
        if (!state.done) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: progress == null || progress.total == 0
                ? 0
                : progress.checked / progress.total,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.setupScanProgress(
              progress?.checked ?? 0,
              progress?.total ?? 0,
            ),
            style: theme.textTheme.bodySmall,
          ),
        ],
        // Kept after the scan ends (2.7.1): a fast scan used to hide the
        // question before anyone could answer it.
        const SizedBox(height: 20),
        _PlatformChips(
          value: state.platform,
          onChanged: onPlatform,
          done: state.done,
        ),
        const SizedBox(height: 16),
        for (final h in state.hubs)
          Card(
            child: ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(_hubSeen(l10n, h)),
              subtitle: Text(l10n.setupHubSeenHint),
            ),
          ),
        for (final c in state.candidates)
          Card(
            child: ListTile(
              leading: const Icon(Icons.router_outlined),
              title: Text(_candidateTitle(l10n, state.kinds[c.host])),
              subtitle: Text('${c.host}:${c.port} · ${c.protocol.name}'),
              onTap: () => onSelect(c),
            ),
          ),
        TextButton(onPressed: onManual, child: Text(l10n.setupManualEntry)),
      ],
    );
  }
}

String _hubSeen(AppLocalizations l10n, HubFound hub) => switch (hub.kind) {
  HubKind.homeAssistant => l10n.setupHubSeenHa(hub.host),
  HubKind.zigbee2mqtt => l10n.setupHubSeenZ2m(hub.host),
  HubKind.smlight => l10n.setupHubSeenSmlight(hub.host),
};

/// A candidate card's title: what its machine is when the scan could tell
/// (2.7.1), else the generic "Possible connection found".
String _candidateTitle(AppLocalizations l10n, HubKind? kind) => switch (kind) {
  HubKind.homeAssistant => l10n.setupPlatformHa,
  HubKind.smlight => l10n.setupPlatformSmlight,
  HubKind.zigbee2mqtt => 'Zigbee2MQTT',
  null => l10n.setupCandidateFound,
};

/// "Where does Zigbee2MQTT run?", asked while the scan runs and on the empty
/// result (2.5). Tapping the chosen chip again clears the answer.
class _PlatformChips extends StatelessWidget {
  const _PlatformChips({
    required this.value,
    required this.onChanged,
    this.done = false,
  });
  final SetupPlatform? value;
  final ValueChanged<SetupPlatform?> onChanged;

  /// The scan has ended: the question drops its "While we look".
  final bool done;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = {
      SetupPlatform.homeAssistant: l10n.setupPlatformHa,
      SetupPlatform.smlight: l10n.setupPlatformSmlight,
      SetupPlatform.piOrDocker: l10n.setupPlatformPi,
      SetupPlatform.notSure: l10n.setupPlatformNotSure,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          done ? l10n.setupPlatformQuestionDone : l10n.setupPlatformQuestion,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final p in SetupPlatform.values)
              ChoiceChip(
                label: Text(labels[p]!),
                selected: value == p,
                onSelected: (on) => onChanged(on ? p : null),
              ),
          ],
        ),
      ],
    );
  }
}

class _ScanEmpty extends StatelessWidget {
  const _ScanEmpty({
    required this.state,
    required this.onRetry,
    required this.onPlatform,
    required this.onManual,
    required this.onCheckAddress,
    required this.onManualTo,
    required this.onDemo,
  });
  final SetupScanEmpty state;
  final VoidCallback onRetry;
  final ValueChanged<SetupPlatform?> onPlatform;
  final ValueChanged<String> onCheckAddress;
  final VoidCallback onManual;
  final ValueChanged<HubFound> onManualTo;
  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final hub = state.hub;
    final platform = state.platform;
    final haHub = hub?.kind == HubKind.homeAssistant;
    final (title, body) = hub != null
        ? switch (hub.kind) {
            HubKind.homeAssistant => (
              l10n.setupNoBrokerHaTitle,
              l10n.setupNoBrokerHaBody(hub.host),
            ),
            HubKind.zigbee2mqtt => (
              l10n.setupNoBrokerZ2mTitle,
              l10n.setupNoBrokerZ2mBody(hub.host),
            ),
            HubKind.smlight => (
              l10n.setupNoBrokerSmlightTitle,
              l10n.setupNoBrokerSmlightBody(hub.host),
            ),
          }
        : switch (platform) {
            SetupPlatform.homeAssistant => (
              l10n.setupNoCandidatesTitle,
              l10n.setupNotFoundHa,
            ),
            SetupPlatform.smlight => (
              l10n.setupNoCandidatesTitle,
              l10n.setupNotFoundSmlight,
            ),
            SetupPlatform.piOrDocker => (
              l10n.setupNoCandidatesTitle,
              l10n.setupNotFoundPi,
            ),
            _ => (l10n.setupNoCandidatesTitle, l10n.setupNoCandidatesBody),
          };
    final guideFor = hub != null
        ? switch (hub.kind) {
            HubKind.homeAssistant => SetupPlatform.homeAssistant,
            HubKind.zigbee2mqtt => SetupPlatform.piOrDocker,
            HubKind.smlight => SetupPlatform.smlight,
          }
        : platform;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Semantics(
          liveRegion: true,
          child: Text(title, style: theme.textTheme.titleMedium),
        ),
        // 2.6.7: a VPN on the phone hides the home network from the scan.
        // One 2.6.4 user scanned with a VPN up, found nothing and left.
        if (state.network?.vpn ?? false) ...[
          const SizedBox(height: 12),
          _VpnHint(text: l10n.setupVpnHint),
        ],
        // 2.8.1: almost nothing answered on the whole network. A home with
        // a hub has dozens of devices; a phone on a guest network, or kept
        // apart by the router, sees only a few (two users on 2026-10-16).
        if (!(state.network?.vpn ?? false) &&
            hub == null &&
            (state.tried?.aliveHosts ?? 99) <= 5) ...[
          const SizedBox(height: 12),
          _VpnHint(text: l10n.setupIsolatedHint),
        ],
        const SizedBox(height: 8),
        // Once Zigbee2MQTT has said where its broker is (2.7.2), its answer
        // replaces the general guess.
        if (state.z2m?.status != Z2mAnswerStatus.localOnly &&
            state.z2m?.status != Z2mAnswerStatus.unreachable)
          Text(body, style: theme.textTheme.bodyLarge),
        // 2.6.6: two of the first users to reach this screen left within
        // seconds of it. Many Home Assistant users run ZHA, not Zigbee2MQTT,
        // and no broker will ever answer for them; say so, and offer the demo.
        if (haHub) ...[
          const SizedBox(height: 12),
          Text(l10n.setupNoBrokerHaZha, style: theme.textTheme.bodyMedium),
        ],
        if (state.z2m case final z?) ...[
          const SizedBox(height: 12),
          _Z2mAnswerNote(answer: z),
        ],
        const SizedBox(height: 12),
        _SetupGuides(only: guideFor),
        // No hub found: the address question comes first and its Check is
        // the primary action (2.6.4: five users saw it under the chips and
        // none typed into it); the chips and Try again follow.
        if (hub == null) ...[
          const SizedBox(height: 20),
          _AddressField(
            platform: platform,
            check: state.address,
            onCheck: onCheckAddress,
          ),
          const SizedBox(height: 20),
          _PlatformChips(value: platform, onChanged: onPlatform),
        ],
        const SizedBox(height: 24),
        // Home Assistant with nothing on port 1883: connecting to it again
        // cannot work, so Try again (after installing Mosquitto) leads and
        // the demo sits right under it for ZHA users.
        if (haHub) ...[
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.setupTryAgain),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onDemo,
            icon: const Icon(Icons.play_circle_outline),
            label: Text(l10n.onboardingDemo),
          ),
        ] else ...[
          if (hub != null) ...[
            FilledButton.icon(
              onPressed: () => onManualTo(hub),
              icon: const Icon(Icons.login),
              label: Text(l10n.setupConnectTo(hub.host)),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.setupTryAgain),
          ),
        ],
        GetHelpLink(
          onPressed: () =>
              context.push(Routes.getHelpFrom(HelpFrom.noConnection.name)),
        ),
        const CommunityLink(from: HelpFrom.noConnection),
        const SizedBox(height: 8),
        if (haHub)
          TextButton(
            onPressed: () => onManualTo(hub),
            child: Text(l10n.setupConnectTo(hub!.host)),
          )
        else ...[
          TextButton(onPressed: onManual, child: Text(l10n.setupManualEntry)),
          TextButton(onPressed: onDemo, child: Text(l10n.onboardingDemo)),
        ],
      ],
    );
  }
}

/// What Zigbee2MQTT's web page said about its broker (2.7.2): asking, a
/// broker that listens only on its own machine (with the lines that open
/// it), or one that did not answer where Zigbee2MQTT uses it.
class _Z2mAnswerNote extends StatelessWidget {
  const _Z2mAnswerNote({required this.answer});
  final Z2mAnswer answer;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final server = ltr(answer.server);
    return switch (answer.status) {
      Z2mAnswerStatus.asking => Row(
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(l10n.setupZ2mAsking, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
      Z2mAnswerStatus.localOnly => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.setupZ2mLocalOnlyTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.setupZ2mLocalOnlyBody(server),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(
                'listener 1883\nallow_anonymous true',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.setupZ2mLocalOnlyNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
          ],
        ),
      ),
      Z2mAnswerStatus.unreachable => Text(
        l10n.setupZ2mUnreachable(server),
        style: theme.textTheme.bodyMedium,
      ),
      Z2mAnswerStatus.broker ||
      Z2mAnswerStatus.noAnswer => const SizedBox.shrink(),
    };
  }
}

/// The VPN note on the empty result: tinted so it reads before the body.
class _VpnHint extends StatelessWidget {
  const _VpnHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.vpn_lock, color: scheme.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The address check (2.6.2): "where do you open Home Assistant?" (or the
/// hub's address, by the platform answer), a field for whatever the user
/// types, and the outcome under it. The scanner guesses subnets; the user
/// knows the address.
class _AddressField extends StatefulWidget {
  const _AddressField({
    required this.platform,
    required this.check,
    required this.onCheck,
  });
  final SetupPlatform? platform;
  final AddressCheckState? check;
  final ValueChanged<String> onCheck;

  @override
  State<_AddressField> createState() => _AddressFieldState();
}

class _AddressFieldState extends State<_AddressField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final check = widget.check;
    final checking = check?.status == AddressCheckStatus.checking;
    final question = switch (widget.platform) {
      SetupPlatform.homeAssistant => l10n.setupAddressQuestionHa,
      SetupPlatform.smlight => l10n.setupAddressQuestionSmlight,
      SetupPlatform.piOrDocker => l10n.setupAddressQuestionPi,
      _ => l10n.setupAddressQuestionAny,
    };
    final String? outcome = switch (check?.status) {
      AddressCheckStatus.nothing => l10n.setupAddressNothing(check!.host),
      AddressCheckStatus.notResolved => l10n.setupAddressNotResolved(
        check!.host,
      ),
      AddressCheckStatus.notLocal => l10n.setupAddressNotLocal(check!.host),
      AddressCheckStatus.invalid => l10n.setupAddressInvalid,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(question, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          enabled: !checking,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: l10n.setupAddressHint,
            hintMaxLines: 2,
            errorText: outcome,
            errorMaxLines: 4,
          ),
          // Every address-field user in the 2.6.4 data tapped Check on an
          // empty field first; an empty submit does nothing now.
          onSubmitted: (text) {
            if (text.trim().isNotEmpty) widget.onCheck(text);
          },
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => FilledButton.icon(
            onPressed: checking || value.text.trim().isEmpty
                ? null
                : () => widget.onCheck(_controller.text),
            icon: checking
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.travel_explore),
            label: Text(l10n.setupAddressCheck),
          ),
        ),
      ],
    );
  }
}

/// "Your broker works, but Zigbee2MQTT isn't publishing here": check the base
/// topic on the same broker, see setup guides, or try the demo meanwhile.
class _NoZigbee2Mqtt extends StatefulWidget {
  const _NoZigbee2Mqtt({
    required this.base,
    required this.onRetry,
    required this.onDemo,
    required this.onManual,
  });
  final String base;
  final ValueChanged<String> onRetry;
  final VoidCallback onDemo;
  final VoidCallback onManual;

  @override
  State<_NoZigbee2Mqtt> createState() => _NoZigbee2MqttState();
}

class _NoZigbee2MqttState extends State<_NoZigbee2Mqtt> {
  late final _baseController = TextEditingController(text: widget.base);

  @override
  void dispose() {
    _baseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Semantics(
          liveRegion: true,
          child: Text(l10n.setupNoZ2mTitle, style: theme.textTheme.titleLarge),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.setupNoZ2mBody(widget.base),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        Text(l10n.setupBaseTopicQuestion, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _baseController,
                decoration: InputDecoration(labelText: l10n.discoverBaseTopic),
                onSubmitted: widget.onRetry,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => widget.onRetry(_baseController.text),
              child: Text(l10n.retry),
            ),
          ],
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: GetHelpLink(
            onPressed: () => context.push(
              Routes.getHelpFrom(
                HelpFrom.setupError.name,
                error: SetupErrorKind.notZigbee2Mqtt.name,
              ),
            ),
          ),
        ),
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: CommunityLink(from: HelpFrom.setupError),
        ),
        const SizedBox(height: 16),
        Text(l10n.setupGuidesTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        const _SetupGuides(),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: widget.onDemo,
          icon: const Icon(Icons.play_circle_outline),
          label: Text(l10n.setupTryDemoMeanwhile),
        ),
        TextButton(
          onPressed: widget.onManual,
          child: Text(l10n.setupManualEntry),
        ),
      ],
    );
  }
}

class _Verifying extends StatelessWidget {
  const _Verifying();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(context.l10n.setupVerifyingTitle),
          ),
        ],
      ),
    );
  }
}

class _AuthPrompt extends StatefulWidget {
  const _AuthPrompt({
    required this.state,
    required this.onSubmit,
    required this.onDemo,
  });
  final SetupNeedsAuth state;
  final void Function(String username, String password) onSubmit;
  final VoidCallback onDemo;

  @override
  State<_AuthPrompt> createState() => _AuthPromptState();
}

class _AuthPromptState extends State<_AuthPrompt> {
  // Zigbee2MQTT's own username, when its web page said (2.7.2).
  late final _username = TextEditingController(
    text: widget.state.suggestedUser ?? '',
  );
  final _password = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final username = _username.text.trim();
    if (username.isEmpty) return;
    widget.onSubmit(username, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final body = widget.state.rejected
        ? l10n.setupAuthRejectedBody
        : l10n.setupAuthBody(widget.state.candidate.host);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Semantics(
          liveRegion: true,
          child: Text(l10n.setupAuthTitle, style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: widget.state.rejected
              ? theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                )
              : theme.textTheme.bodyMedium,
        ),
        // After a rejected login, the one place that surely holds a working
        // login: the one Zigbee2MQTT itself uses (2.7.1; a user left after
        // a rejected login with no idea which one was wanted).
        if (widget.state.rejected) ...[
          const SizedBox(height: 8),
          Text(l10n.setupAuthRejectedZ2m, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 12),
        _LoginHint(platform: widget.state.platform),
        // 2.8.1: people stopped here without typing. Say where the login
        // goes before asking for it.
        const SizedBox(height: 12),
        _LoginTrust(onDemo: widget.onDemo),
        const SizedBox(height: 16),
        // The broker refused anonymous access, so the username is not
        // optional here: the button waits for one (2.6.4; a user tapped it
        // eight times on an empty field before typing).
        TextField(
          controller: _username,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.connUsername),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: InputDecoration(labelText: l10n.connPasswordOptional),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 24),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _username,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty ? null : _submit,
            child: Text(l10n.setupErrAuthRequiredAction),
          ),
        ),
        GetHelpLink(
          onPressed: () => context.push(
            Routes.getHelpFrom(
              HelpFrom.setupError.name,
              error:
                  (widget.state.rejected
                          ? SetupErrorKind.authRejected
                          : SetupErrorKind.authRequired)
                      .name,
            ),
          ),
        ),
        const CommunityLink(from: HelpFrom.setupError),
      ],
    );
  }
}

/// Why typing the MQTT login here is safe, with the policy and the demo
/// for anyone who wants to look first (2.8.1).
class _LoginTrust extends StatelessWidget {
  const _LoginTrust({required this.onDemo});
  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.setupAuthTrust,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                onPressed: () => launchUrl(
                  privacyPolicyUrl,
                  mode: LaunchMode.externalApplication,
                ),
                child: Text(l10n.setupAuthWhatKept),
              ),
              TextButton(
                onPressed: onDemo,
                child: Text(l10n.setupAuthDemoFirst),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Where the MQTT login lives, so nobody types their hub's web password
/// here (setup-help-2.5.md, login step). One line for the platform the user
/// named; all three when they didn't.
class _LoginHint extends StatelessWidget {
  const _LoginHint({required this.platform});
  final SetupPlatform? platform;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final lines = switch (platform) {
      SetupPlatform.homeAssistant => [l10n.setupAuthHintHa],
      SetupPlatform.piOrDocker => [l10n.setupAuthHintPi],
      SetupPlatform.smlight => [l10n.setupAuthHintSmlight],
      SetupPlatform.notSure || null => [
        l10n.setupAuthHintHa,
        l10n.setupAuthHintPi,
        l10n.setupAuthHintSmlight,
      ],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.setupAuthWhich, style: style),
        for (final line in lines) ...[
          const SizedBox(height: 4),
          Text(line, style: style),
        ],
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({
    required this.state,
    required this.onRetry,
    required this.onManual,
  });
  final SetupFailed state;
  final VoidCallback onRetry;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final guidance = guidanceFor(state.kind);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(
            _guidanceText(l10n, guidance.titleKey),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _guidanceText(l10n, guidance.explanationKey),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: Text(_guidanceText(l10n, guidance.actionKey)),
        ),
        GetHelpLink(
          onPressed: () => context.push(
            Routes.getHelpFrom(
              HelpFrom.setupError.name,
              error: state.kind.name,
            ),
          ),
        ),
        const CommunityLink(from: HelpFrom.setupError),
        const SizedBox(height: 8),
        TextButton(onPressed: onManual, child: Text(l10n.setupManualEntry)),
      ],
    );
  }
}

/// No home address to scan from (2.9.4): says why (mobile data, no
/// network), opens the Wi-Fi panel, and waits; the coordinator scans again
/// by itself once Wi-Fi is back, so there is no Try again to tap repeatedly.
class _NoNetwork extends StatelessWidget {
  const _NoNetwork({required this.state, required this.onManual});
  final SetupFailed state;
  final VoidCallback onManual;

  static Future<void> _openWifi() async {
    try {
      await appChannel.invokeMethod<bool>('openWifiSettings');
    } on PlatformException catch (_) {
      // No settings page to open: the text still says what to do.
    } on MissingPluginException catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final why = state.noNetwork ?? NoNetwork.unknown;
    final (title, body) = switch (why) {
      NoNetwork.mobileData => (
        l10n.setupNoWifiTitle,
        l10n.setupNoWifiMobileData,
      ),
      NoNetwork.offline => (l10n.setupNoWifiTitle, l10n.setupNoWifiOffline),
      NoNetwork.unknown => (
        l10n.setupErrScanFailedTitle,
        l10n.setupNoWifiUnknown,
      ),
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(Icons.wifi_off, size: 48, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _openWifi,
          icon: const Icon(Icons.wifi),
          label: Text(l10n.setupOpenWifiSettings),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.setupWaitingForWifi,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: onManual, child: Text(l10n.setupManualEntry)),
        GetHelpLink(
          onPressed: () => context.push(
            Routes.getHelpFrom(
              HelpFrom.setupError.name,
              error: state.kind.name,
            ),
          ),
        ),
        const CommunityLink(from: HelpFrom.setupError),
      ],
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({
    required this.state,
    required this.onToggle,
    required this.onCreate,
    this.busy = false,
  });
  final SetupReview state;
  final ValueChanged<String> onToggle;
  final VoidCallback onCreate;

  /// Saving: the list stays up and the button shows progress.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final rows = state.rows;
    final firstOther = rows.indexWhere((r) => r.group == ReviewGroup.other);
    final firstUnsupported = rows.indexWhere(
      (r) => r.group == ReviewGroup.unsupported,
    );

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  l10n.setupReviewSubtitle(rows.length),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < rows.length; i++) ...[
                if (i == firstOther) _GroupHeader(title: l10n.setupGroupOther),
                if (i == firstUnsupported)
                  _GroupHeader(title: l10n.setupGroupUnsupported),
                _DeviceRow(row: rows[i], onToggle: onToggle),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: state.selectedCount > 0 && !busy ? onCreate : null,
            icon: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.dashboard_outlined),
            label: Text(l10n.setupCreateWithCount(state.selectedCount)),
          ),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(title, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.row, required this.onToggle});
  final ReviewRow row;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final enabled = row.selectable;
    // CheckboxListTile owns the semantics: it exposes the row's checked
    // state, its label, and enabled/disabled (onChanged null ⇒ disabled).
    // A Semantics(selected:) wrapper here would be overridden by the tile's
    // own `selected: false` and is therefore dead code.
    return CheckboxListTile(
      value: row.selected,
      onChanged: enabled ? (_) => onToggle(row.device.friendlyName) : null,
      title: Text(row.device.displayName),
      subtitle: Text(
        [row.device.vendor, row.device.model].whereType<String>().join(' · '),
      ),
    );
  }
}

/// Where Zigbee2MQTT usually runs, each opening its setup guide in the
/// browser. Shown when nothing was found and when Zigbee2MQTT is missing;
/// with [only], just that platform's guide (the user's answer, 2.5).
class _SetupGuides extends StatelessWidget {
  const _SetupGuides({this.only});
  final SetupPlatform? only;

  static final _ha = Uri.parse(
    'https://www.zigbee2mqtt.io/guide/installation/03_ha_addon.html',
  );
  static final _linux = Uri.parse(
    'https://www.zigbee2mqtt.io/guide/installation/01_linux.html',
  );
  static final _smlight = Uri.parse(
    'https://smlight.tech/support/manuals/books/smhub',
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final all = {
      SetupPlatform.homeAssistant: _GuideLink(
        text: l10n.setupGuideHa,
        url: _ha,
      ),
      SetupPlatform.piOrDocker: _GuideLink(
        text: l10n.setupGuidePi,
        url: _linux,
      ),
      SetupPlatform.smlight: _GuideLink(
        text: l10n.setupGuideSmlight,
        url: _smlight,
      ),
    };
    final shown = all[only];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: shown != null ? [shown] : all.values.toList(),
    );
  }
}

class _GuideLink extends StatelessWidget {
  const _GuideLink({required this.text, required this.url});
  final String text;
  final Uri url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(text, style: theme.textTheme.bodyMedium),
      trailing: Icon(
        Icons.open_in_new,
        size: 20,
        color: theme.colorScheme.primary,
      ),
      onTap: () => launchUrl(url, mode: LaunchMode.externalApplication),
    );
  }
}
