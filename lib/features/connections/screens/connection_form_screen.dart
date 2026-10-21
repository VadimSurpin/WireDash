import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../onboarding/first_run.dart';
import '../../../data/database/tables/connections.dart';
import '../../../data/repositories/connection_repo.dart';
import '../../../mqtt/broker_config.dart';
import '../../../mqtt/providers/mqtt_manager_provider.dart';
import '../../../shortcuts/shortcut_service.dart' show forgetShortcutHome;
import '../diagnostics/connect_diagnostics.dart';
import '../diagnostics/connect_diagnostics_provider.dart';
import '../widgets/broker_fields.dart';
import '../widgets/wireguard_fields.dart';
import '../widgets/diagnostics_ladder_view.dart';
import '../widgets/protocol_dropdown.dart';
import 'broker_help_sheet.dart';
import 'broker_scan_sheet.dart';

class ConnectionFormScreen extends ConsumerStatefulWidget {
  const ConnectionFormScreen({super.key, this.connectionId});

  /// Null for "create", non-null for "edit".
  final String? connectionId;

  @override
  ConsumerState<ConnectionFormScreen> createState() =>
      _ConnectionFormScreenState();
}

class _ConnectionFormScreenState extends ConsumerState<ConnectionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '1883');
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _keepAlive = TextEditingController(text: '60');
  final _remoteHost = TextEditingController();
  final _wireGuard = TextEditingController();
  bool get _useWireGuard => _transport == ConnectionTransport.wireGuard;

  MqttProtocol _protocol = MqttProtocol.tcp;
  bool _autoConnect = false;
  bool _loaded = false;
  bool _saving = false;
  bool _testing = false;
  bool _passwordExists = false;

  /// How the home connects (2.10); a Home Assistant home shows its address
  /// read-only: the sign-in is replaced by deleting the home and
  /// connecting again, never by typing a broker.
  ConnectionTransport _transport = ConnectionTransport.mqtt;
  bool get _viaHa => _transport == ConnectionTransport.homeAssistant;

  bool get _isEdit => widget.connectionId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _load();
    } else {
      _loaded = true;
    }
  }

  Future<void> _load() async {
    final repo = ref.read(connectionRepoProvider);
    final c = await repo.getById(widget.connectionId!);
    if (c == null || !mounted) return;
    final pw = await repo.readPassword(c.id);
    final wireGuard = await repo.readWireGuard(c.id);
    if (!mounted) return;
    setState(() {
      _name.text = c.name;
      _host.text = c.host;
      _port.text = c.port.toString();
      _protocol = c.protocol;
      _username.text = c.username ?? '';
      _passwordExists = pw != null && pw.isNotEmpty;
      _keepAlive.text = c.keepAliveSeconds.toString();
      _remoteHost.text = c.remoteHost ?? '';
      _autoConnect = c.autoConnect;
      _transport = transportOf(c.transport);
      _wireGuard.text = wireGuard ?? '';
      _loaded = true;
    });
  }

  void _onProtocolChanged(MqttProtocol p) {
    applyProtocolPortDefault(_port, _protocol, p);
    setState(() => _protocol = p);
  }

  /// Opens the network scan; on a tapped result, fills host/port/protocol.
  Future<void> _findBrokers() async {
    final result = await BrokerScanSheet.show(context);
    if (result == null || !mounted) return;
    setState(
      () => applyScanResult(
        host: _host,
        port: _port,
        onProtocol: (p) => _protocol = p,
        result: result,
      ),
    );
  }

  void _tidyAddress() => setState(
    () => tidyBrokerAddress(
      host: _host,
      port: _port,
      protocol: _protocol,
      onProtocol: (p) => _protocol = p,
    ),
  );

  Future<void> _save() async {
    if (!_viaHa) _tidyAddress();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(connectionRepoProvider);
    final port = int.parse(_port.text);
    final keepAlive = int.parse(_keepAlive.text);
    final passwordToWrite = _password.text.isEmpty && _isEdit
        ? null
        : _password.text;

    try {
      if (_useWireGuard) {
        if (!await validateWireGuardForForm(context, _wireGuard.text)) {
          if (mounted) setState(() => _testing = false);
          return;
        }
      }
      if (_isEdit) {
        await repo.update(
          id: widget.connectionId!,
          transport: _transport,
          wireGuardConfig: _useWireGuard ? _wireGuard.text : null,
          name: _name.text.trim(),
          host: _host.text.trim(),
          port: port,
          protocol: _protocol,
          username: _username.text.trim().isEmpty
              ? null
              : _username.text.trim(),
          password: passwordToWrite,
          keepAliveSeconds: keepAlive,
          autoConnect: _autoConnect,
          remoteHost: _remoteHost.text.trim().isEmpty
              ? null
              : _remoteHost.text.trim(),
        );
        ref.invalidate(mqttManagerProvider(widget.connectionId!));
        await forgetShortcutHome(widget.connectionId!);
      } else {
        final id = await repo.create(
          transport: _transport,
          wireGuardConfig: _useWireGuard ? _wireGuard.text : null,
          name: _name.text.trim(),
          host: _host.text.trim(),
          port: port,
          protocol: _protocol,
          username: _username.text.trim().isEmpty
              ? null
              : _username.text.trim(),
          password: _password.text.isEmpty ? null : _password.text,
          keepAliveSeconds: keepAlive,
          autoConnect: _autoConnect,
          remoteHost: _remoteHost.text.trim().isEmpty
              ? null
              : _remoteHost.text.trim(),
        );
        // A new real home counts as completing setup: it ends first run and
        // removes the demo home. Bookkeeping failures must not block saving.
        try {
          await ref.read(firstRunProvider).finish(id);
        } catch (_) {}
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.connTestFailed(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    _tidyAddress();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _testing = true);

    final cfg = BrokerConfig(
      transport: _transport,
      wireGuardConfig: _useWireGuard ? _wireGuard.text : null,
      id: 'test-${DateTime.now().microsecondsSinceEpoch}',
      host: _host.text.trim(),
      port: int.parse(_port.text),
      protocol: _protocol,
      username: _username.text.trim().isEmpty ? null : _username.text.trim(),
      keepAliveSeconds: int.parse(_keepAlive.text),
      remoteHost: _remoteHost.text.trim().isEmpty
          ? null
          : _remoteHost.text.trim(),
    );
    final diagnostics = ref.read(connectDiagnosticsProvider);

    try {
      if (_useWireGuard) {
        if (!await validateWireGuardForForm(context, _wireGuard.text)) {
          if (mounted) setState(() => _testing = false);
          return;
        }
      }
      final password = _password.text.isEmpty && _isEdit
          ? await ref
                    .read(connectionRepoProvider)
                    .readPassword(widget.connectionId!) ??
                ''
          : _password.text;
      final report = await diagnostics.run(config: cfg, password: password);
      if (!mounted) return;
      setState(() => _testing = false);
      _showLadderSheet(report);
    } catch (e) {
      // The ladder reports per-step failures itself; an unexpected throw just
      // falls back to the old generic failure message.
      if (!mounted) return;
      setState(() => _testing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.connTestFailed(e.toString()))),
      );
    }
  }

  /// Shows the diagnostic ladder for the just-run test. Retry re-runs the
  /// ladder with the current form values.
  void _showLadderSheet(DiagnosticsReport report) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DiagnosticsLadderView(
                steps: report.steps,
                showTriedHint: true,
                candidatesTried: report.candidatesTried,
              ),
              const SizedBox(height: 16),
              if (report.connected)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.check),
                    label: Text(context.l10n.connTestOk),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: Text(context.l10n.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _testConnection();
                        },
                        icon: const Icon(Icons.refresh),
                        label: Text(context.l10n.retry),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _wireGuard.dispose();
    _name.dispose();
    _host.dispose();
    _remoteHost.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    _keepAlive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? context.l10n.connEdit : context.l10n.connNew),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? context.l10n.saving : context.l10n.save),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                labelText: context.l10n.connName,
                hintText: context.l10n.connNameHint,
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? context.l10n.fieldRequired
                  : null,
            ),
            const SizedBox(height: 12),
            if (_viaHa) ...[
              _HaHomeCard(
                address: _host.text,
                onSignInAgain: () async {
                  await context.push(
                    Routes.haConnectAgain(widget.connectionId!, _host.text),
                  );
                  if (mounted) _load();
                },
              ),
              const SizedBox(height: 12),
            ] else ...[
              ProtocolDropdown(value: _protocol, onChanged: _onProtocolChanged),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _host,
                      decoration: InputDecoration(
                        labelText: context.l10n.connLocalHost,
                        hintText: context.l10n.connHostHint,
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? context.l10n.fieldRequired
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.l10n.connPort,
                      ),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < 1 || n > 65535) {
                          return context.l10n.connPortRange;
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.wifi_find, size: 18),
                    label: Text(context.l10n.connFindBrokers),
                    onPressed: _useWireGuard ? null : _findBrokers,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => BrokerHelpSheet.show(context),
                    child: Text(context.l10n.connHowToFind),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _username,
                decoration: InputDecoration(
                  labelText: context.l10n.connUsernameOptional,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.l10n.connPasswordOptional,
                  hintText: _isEdit && _passwordExists
                      ? context.l10n.connPasswordKeepHint
                      : null,
                ),
              ),
              const SizedBox(height: 12),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.connAutoConnect),
              value: _autoConnect,
              onChanged: (v) => setState(() => _autoConnect = v),
            ),
            const SizedBox(height: 4),
            // The test ladder is MQTT-shaped; a Home Assistant home was
            // checked when it was connected.
            if (!_viaHa) ...[
              OutlinedButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: Text(context.l10n.connTestButton),
              ),
              const SizedBox(height: 4),
            ],
            if (!_viaHa) WireGuardFields(
              controller: _wireGuard,
              enabled: _useWireGuard,
              busy: _saving || _testing,
              onChanged: (value) => setState(() => _transport = value
                  ? ConnectionTransport.wireGuard : ConnectionTransport.mqtt),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(context.l10n.advanced),
              children: [
                TextFormField(
                  controller: _remoteHost,
                  decoration: InputDecoration(
                    labelText: _viaHa
                        ? context.l10n.haHomeRemote
                        : context.l10n.connRemoteHost,
                    hintText: _viaHa
                        ? 'https://xyz.ui.nabu.casa'
                        : context.l10n.connRemoteHostHint,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _keepAlive,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.l10n.connKeepAlive,
                  ),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n < 5 || n > 3600) {
                      return context.l10n.connKeepAliveRange;
                    }
                    return null;
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A home that connects through Home Assistant: where, and how to change
/// the sign-in (docs/design/ha-route.md).
class _HaHomeCard extends StatelessWidget {
  const _HaHomeCard({required this.address, required this.onSignInAgain});
  final String address;
  final VoidCallback onSignInAgain;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.home_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.haHomeConnected,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(address, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(
              l10n.haHomeChange,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: onSignInAgain,
                icon: const Icon(Icons.login),
                label: Text(l10n.haHomeSignInAgain),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
