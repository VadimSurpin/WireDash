import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics.dart';
import '../../core/l10n/l10n_ext.dart';
import '../../core/router/routes.dart';
import '../../data/database/daos/device_registry_dao.dart';
import '../../data/database/database.dart';
import '../../data/repositories/connection_repo.dart';
import '../../data/repositories/dashboard_repo.dart';
import '../../data/repositories/panel_repo.dart';
import '../../data/repositories/section_repo.dart';
import '../../l10n/app_localizations.dart';
import '../devices/devices_providers.dart';
import '../discovery/providers/discovery_provider.dart';
import 'ha_client.dart';
import 'ha_import_apply.dart';
import 'ha_import_controller.dart';

/// Import names and rooms from Home Assistant into a home
/// (docs/design/ha-import.md): where Home Assistant is and a token, then a
/// preview, then the import. The token lives in its text field and is
/// handed to Home Assistant once; nothing keeps it.
class HaImportScreen extends ConsumerStatefulWidget {
  const HaImportScreen({
    super.key,
    required this.connectionId,
    @visibleForTesting this.controller,
  });
  final String connectionId;

  /// A controller in a given state, for screenshots; otherwise the screen
  /// makes its own.
  final HaImportController? controller;

  @override
  ConsumerState<HaImportScreen> createState() => _HaImportScreenState();
}

class _HaImportScreenState extends ConsumerState<HaImportScreen> {
  HaImportController? _controller;
  final _address = TextEditingController();
  final _token = TextEditingController();

  @override
  void dispose() {
    if (widget.controller == null) _controller?.dispose();
    _address.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final given = widget.controller?.value;
    if (given is HaImportAsk) _address.text = given.address;
  }

  HaImportController _make(String host) {
    final l10n = context.l10n;
    final base =
        ref.read(homeBaseTopicProvider(widget.connectionId)) ?? 'zigbee2mqtt';
    final db = ref.read(appDatabaseProvider);
    final applier = HaImportApplier(
      dashboards: ref.read(dashboardRepoProvider),
      sections: ref.read(sectionRepoProvider),
      panels: ref.read(panelRepoProvider),
      registry: DeviceRegistryDao(db),
    );
    _address.text = host;
    return HaImportController(
      address: host,
      reader: readHaRegistry,
      devices: () async {
        try {
          return await ref.read(
            discoveredDevicesProvider((
              connectionId: widget.connectionId,
              base: base,
            )).future,
          );
        } catch (_) {
          return null;
        }
      },
      writer: (plan, {required makeDashboards, required skipRooms}) =>
          applier.apply(
            connectionId: widget.connectionId,
            plan: plan,
            makeDashboards: makeDashboards,
            skipRooms: skipRooms,
            base: base,
            homeName: l10n.dashDefaultName,
            otherRoomsName: l10n.haImportOtherRooms,
            noRoomName: l10n.haImportNoRoom,
          ),
    );
  }

  HaImportController _own(String host) =>
      _make('$host:8123')..addListener(_track);

  /// The `ha_import` event for each step that counts: counts only.
  void _track() {
    final event = switch (_controller?.value) {
      HaImportAsk(:final problem?)
          when problem != HaImportProblem.noAddress &&
              problem != HaImportProblem.noToken =>
        HaImportEvent(HaImportStep.failed, error: problem),
      HaImportPreview(:final plan, skip: final s) when s.isEmpty =>
        HaImportEvent(
          HaImportStep.preview,
          devices: plan.matched,
          rooms: plan.rooms,
          zhaOnly: plan.zhaOnly,
        ),
      HaImportDone(:final result) => HaImportEvent(
        HaImportStep.imported,
        renamed: result.renamed,
        dashboards: result.dashboardIds.length,
        devices: result.tiles,
      ),
      _ => null,
    };
    if (event != null) ref.read(analyticsProvider).track(event);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final home = ref
        .watch(connectionsStreamProvider)
        .valueOrNull
        ?.where((c) => c.id == widget.connectionId)
        .firstOrNull;
    if (home == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.haImportTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final controller = _controller ??= widget.controller ?? _own(home.host);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.haImportTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ValueListenableBuilder<HaImportState>(
            valueListenable: controller,
            builder: (context, state, _) => switch (state) {
              HaImportAsk() => _Ask(
                state: state,
                address: _address,
                token: _token,
                onRead: () => controller.read(_address.text, _token.text),
              ),
              HaImportReading() || HaImportApplying() => _Busy(
                text: state is HaImportReading
                    ? l10n.haImportReading
                    : l10n.haImportApplying,
              ),
              HaImportPreview() => _Preview(
                state: state,
                onRoom: controller.toggleRoom,
                onDashboards: controller.setMakeDashboards,
                onApply: () {
                  // The token has done its job: drop it before writing.
                  _token.clear();
                  controller.apply();
                },
                onBack: controller.back,
              ),
              HaImportDone(:final result) => _Done(
                result: result,
                onOpen: () =>
                    context.go(Routes.homeDashboards(widget.connectionId)),
              ),
            },
          ),
        ),
      ),
    );
  }
}

class _Ask extends StatelessWidget {
  const _Ask({
    required this.state,
    required this.address,
    required this.token,
    required this.onRead,
  });
  final HaImportAsk state;
  final TextEditingController address;
  final TextEditingController token;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final problem = state.problem;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.haImportIntro, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 16),
        TextField(
          controller: address,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: l10n.haImportAddress,
            helperText: l10n.haImportAddressHelp,
            helperMaxLines: 5,
            errorText: problem == HaImportProblem.noAddress
                ? l10n.haImportNoAddress
                : null,
          ),
        ),
        const SizedBox(height: 16),
        // Plain, not obscured: a pasted 180-character token has to be
        // checkable, and it is handed to Home Assistant once.
        TextField(
          controller: token,
          autocorrect: false,
          enableSuggestions: false,
          maxLines: 1,
          decoration: InputDecoration(
            labelText: l10n.haImportToken,
            helperText: l10n.haImportTokenHelp,
            helperMaxLines: 12,
            errorText: problem == HaImportProblem.noToken
                ? l10n.haImportNoToken
                : null,
          ),
          onSubmitted: (_) => onRead(),
        ),
        if (problem != null &&
            problem != HaImportProblem.noAddress &&
            problem != HaImportProblem.noToken) ...[
          const SizedBox(height: 16),
          Text(
            _problemText(l10n, problem),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(onPressed: onRead, child: Text(l10n.haImportRead)),
        const SizedBox(height: 16),
        Text(l10n.haImportAutomations, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

String _problemText(AppLocalizations l10n, HaImportProblem p) => switch (p) {
  HaImportProblem.noAddress => l10n.haImportNoAddress,
  HaImportProblem.noToken => l10n.haImportNoToken,
  HaImportProblem.unreachable => l10n.haImportUnreachable,
  HaImportProblem.notHomeAssistant => l10n.haImportNotHa,
  HaImportProblem.badToken => l10n.haImportBadToken,
  HaImportProblem.certificate => l10n.haImportCertificate,
  HaImportProblem.failed => l10n.haImportFailed,
  HaImportProblem.noDevices => l10n.haImportNoDevices,
};

class _Busy extends StatelessWidget {
  const _Busy({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Semantics(liveRegion: true, child: Text(text)),
      ],
    ),
  );
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.state,
    required this.onRoom,
    required this.onDashboards,
    required this.onApply,
    required this.onBack,
  });
  final HaImportPreview state;
  final ValueChanged<String?> onRoom;
  final ValueChanged<bool> onDashboards;
  final VoidCallback onApply;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final plan = state.plan;
    if (state.empty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            plan.zhaOnly ? l10n.haImportZhaOnly : l10n.haImportNothing,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          OutlinedButton(onPressed: onBack, child: Text(l10n.haImportBack)),
        ],
      );
    }
    final floored = plan.dashboards.any((d) => d.floor != null);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            l10n.haImportFound(plan.matched),
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.haImportRenameNote, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: state.makeDashboards,
          onChanged: onDashboards,
          title: Text(l10n.haImportMakeDashboards),
        ),
        for (final board in plan.dashboards) ...[
          const SizedBox(height: 8),
          Text(
            board.floor ??
                (floored ? l10n.haImportOtherRooms : l10n.dashDefaultName),
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          for (final room in board.rooms)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: !state.skip.contains(room.name),
              onChanged: state.makeDashboards ? (_) => onRoom(room.name) : null,
              title: Text(room.name ?? l10n.haImportNoRoom),
              subtitle: Text(
                room.devices.map((d) => d.name).join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        const SizedBox(height: 24),
        FilledButton(onPressed: onApply, child: Text(l10n.haImportApply)),
        TextButton(onPressed: onBack, child: Text(l10n.haImportBack)),
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.result, required this.onOpen});
  final HaImportResult result;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(
          Icons.check_circle,
          size: 56,
          color: Theme.of(context).colorScheme.tertiary,
        ),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(
            l10n.haImportDone(result.renamed, result.dashboardIds.length),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: onOpen, child: Text(l10n.haImportOpen)),
      ],
    );
  }
}
