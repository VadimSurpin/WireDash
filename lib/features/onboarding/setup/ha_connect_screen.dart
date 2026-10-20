import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../l10n/app_localizations.dart';
import '../../ha_import/ha_auth.dart';
import 'ha_connect.dart';
import 'setup_providers.dart';

/// "Connect through Home Assistant" (docs/design/ha-route.md): the address,
/// a sign-in (Home Assistant's login page, or a pasted token), a check,
/// then back to setup, which reviews the devices.
class HaConnectScreen extends ConsumerStatefulWidget {
  const HaConnectScreen({super.key, this.initialHost, this.controller});

  /// The Home Assistant the scan saw, if any.
  final String? initialHost;

  /// Tests pass one; the screen builds its own otherwise.
  final HaConnectController? controller;

  @override
  ConsumerState<HaConnectScreen> createState() => _HaConnectScreenState();
}

class _HaConnectScreenState extends ConsumerState<HaConnectScreen> {
  late final HaConnectController _controller = widget.controller ?? _make();
  final _address = TextEditingController();
  final _token = TextEditingController();

  @override
  void initState() {
    super.initState();
    _address.text = switch (_controller.value) {
      HaConnectAsk(:final address) when address.isNotEmpty => address,
      _ => widget.initialHost ?? '',
    };
    _controller.addListener(_onState);
  }

  HaConnectController _make() => HaConnectController(
    address: widget.initialHost ?? '',
    onEvent: (event) => ref.read(analyticsProvider).track(event),
    adopt: (address, signIn) => ref
        .read(setupCoordinatorProvider)
        .adoptHomeAssistant(address: address, signIn: signIn),
    signIn: (base) => signInToHa(
      base,
      browser: (url) => FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: haCallbackScheme,
      ),
    ),
  );

  void _onState() {
    if (!mounted) return;
    if (_controller.value is HaConnectDone) {
      // Setup shows the review (or why it failed) from here.
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onState);
    if (widget.controller == null) _controller.dispose();
    _address.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = _controller.value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.haConnectTitle)),
      body: SafeArea(
        child: switch (state) {
          HaConnectAsk() => _Ask(
            state: state,
            address: _address,
            token: _token,
            canSignIn: _controller.canSignIn,
            onSignIn: () => _controller.signInAndConnect(_address.text),
            onToken: () =>
                _controller.connectWithToken(_address.text, _token.text),
          ),
          HaConnectChecking() || HaConnectDone() => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(l10n.haConnectChecking),
              ],
            ),
          ),
        },
      ),
    );
  }
}

class _Ask extends StatefulWidget {
  const _Ask({
    required this.state,
    required this.address,
    required this.token,
    required this.canSignIn,
    required this.onSignIn,
    required this.onToken,
  });
  final HaConnectAsk state;
  final TextEditingController address;
  final TextEditingController token;
  final bool canSignIn;
  final VoidCallback onSignIn;
  final VoidCallback onToken;

  @override
  State<_Ask> createState() => _AskState();
}

class _AskState extends State<_Ask> {
  var _tokenOpen = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final problem = widget.state.problem;
    // The token opens by itself when it is the way forward.
    final tokenOpen =
        _tokenOpen ||
        !widget.canSignIn ||
        problem == HaConnectProblem.signInRefused ||
        problem == HaConnectProblem.badToken ||
        problem == HaConnectProblem.noToken ||
        problem == HaConnectProblem.notAdmin;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.haConnectIntro, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 16),
        TextField(
          controller: widget.address,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: l10n.haImportAddress,
            helperText: l10n.haConnectAddressHelp,
            helperMaxLines: 5,
            errorText: problem == HaConnectProblem.noAddress
                ? l10n.haImportNoAddress
                : null,
          ),
        ),
        if (problem != null &&
            problem != HaConnectProblem.noAddress &&
            problem != HaConnectProblem.noToken) ...[
          const SizedBox(height: 16),
          Text(
            problemText(l10n, problem),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        if (widget.canSignIn) ...[
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: widget.onSignIn,
            icon: const Icon(Icons.login),
            label: Text(l10n.haImportSignIn),
          ),
          const SizedBox(height: 8),
          Text(l10n.haConnectSignInHelp, style: theme.textTheme.bodySmall),
          if (!tokenOpen)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => setState(() => _tokenOpen = true),
                child: Text(l10n.haImportOrToken),
              ),
            ),
        ],
        if (tokenOpen) ...[
          const SizedBox(height: 16),
          // Plain, not obscured: a pasted 180-character token has to be
          // checkable before it is kept.
          TextField(
            controller: widget.token,
            autocorrect: false,
            enableSuggestions: false,
            maxLines: 1,
            decoration: InputDecoration(
              labelText: l10n.haImportToken,
              helperText: l10n.haConnectTokenHelp,
              helperMaxLines: 12,
              errorText: problem == HaConnectProblem.noToken
                  ? l10n.haImportNoToken
                  : null,
            ),
            onSubmitted: (_) => widget.onToken(),
          ),
          const SizedBox(height: 16),
          widget.canSignIn
              ? OutlinedButton(
                  onPressed: widget.onToken,
                  child: Text(l10n.haConnectWithToken),
                )
              : FilledButton(
                  onPressed: widget.onToken,
                  child: Text(l10n.haConnectWithToken),
                ),
        ],
        const SizedBox(height: 24),
        Text(l10n.haConnectKeeps, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// What a failed try says, visible for tests.
String problemText(AppLocalizations l10n, HaConnectProblem p) => switch (p) {
  HaConnectProblem.noAddress => l10n.haImportNoAddress,
  HaConnectProblem.noToken => l10n.haImportNoToken,
  HaConnectProblem.unreachable => l10n.haImportUnreachable,
  HaConnectProblem.notHomeAssistant => l10n.haImportNotHa,
  HaConnectProblem.certificate => l10n.haImportCertificate,
  HaConnectProblem.signInRefused => l10n.haImportSignInRefused,
  HaConnectProblem.signInFailed => l10n.haConnectSignInFailed,
  HaConnectProblem.badToken => l10n.haImportBadToken,
  HaConnectProblem.notAdmin => l10n.haConnectNotAdmin,
  HaConnectProblem.noMqtt => l10n.haConnectNoMqtt,
};
