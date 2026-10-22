import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/theme/dashboard_accent.dart';
import '../../../data/repositories/dashboard_repo.dart';
import '../../../data/database/tables/panels.dart';
import '../../panels/widgets/property_widget_selector.dart';
import '../models/wirenboard_panel_suggestion.dart';
import '../models/wirenboard_device.dart';
import '../wirenboard_dashboard_importer.dart';

Future<bool> showAddWirenBoardPanelSheet(
  BuildContext context, {
  required String connectionId,
  required WirenBoardDevice device,
  WirenBoardControl? control,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _AddWirenBoardPanelSheet(
        connectionId: connectionId,
        device: device,
        control: control,
      ),
    ) ==
    true;

class _AddWirenBoardPanelSheet extends ConsumerStatefulWidget {
  const _AddWirenBoardPanelSheet({
    required this.connectionId,
    required this.device,
    this.control,
  });
  final String connectionId;
  final WirenBoardDevice device;
  final WirenBoardControl? control;

  @override
  ConsumerState<_AddWirenBoardPanelSheet> createState() =>
      _AddWirenBoardPanelSheetState();
}

class _AddWirenBoardPanelSheetState
    extends ConsumerState<_AddWirenBoardPanelSheet> {
  final _form = GlobalKey<FormState>();
  final _label = TextEditingController();
  String? _dashboardId;
  PanelType? _widgetType;
  bool _initialized = false;
  bool _saving = false;
  bool _allowCommands = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _label.text =
          (widget.control?.title(
            Localizations.localeOf(context).languageCode,
          ) ??
          widget.device.title(Localizations.localeOf(context).languageCode));
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (!_form.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    final l10n = context.l10n;
    try {
      final dashboards = await ref
          .read(dashboardRepoProvider)
          .getByConnection(widget.connectionId);
      final chosen =
          dashboards.where((d) => d.id == _dashboardId).firstOrNull ??
          dashboards.firstOrNull;
      final id =
          chosen?.id ??
          await ref
              .read(dashboardRepoProvider)
              .create(
                connectionId: widget.connectionId,
                name: l10n.dashDefaultName,
                colorSeed: defaultDashboardSeed,
                iconCodepoint: Icons.home.codePoint,
              );
      if (!mounted) return;
      final importer = ref.read(wirenBoardDashboardImporterProvider(id));
      if (widget.control case final control?) {
        await importer.addControl(
          widget.device,
          control,
          label: _label.text.trim(),
          widgetType: _widgetType,
          allowCommands: _allowCommands,
        );
      } else {
        await importer.addDevice(widget.device, label: _label.text.trim());
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.sceneAddedToDashboard(chosen?.name ?? l10n.dashDefaultName),
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.wbAutoAddFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final loaded = ref.watch(
      dashboardsForConnectionProvider(widget.connectionId),
    );
    final dashboards = loaded.valueOrNull;
    final control = widget.control;
    final suggestion = control == null
        ? null
        : suggestWirenBoardPanel(
            widget.device,
            control,
            language: Localizations.localeOf(context).languageCode,
            allowCommands: _allowCommands,
          );
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.deviceAddToDashboard,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                control == null
                    ? l10n.wbControlCount(widget.device.controls.length)
                    : widget.device.title(
                        Localizations.localeOf(context).languageCode,
                      ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _label,
                enabled: !_saving,
                decoration: InputDecoration(labelText: l10n.addTileName),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? l10n.fieldRequired : null,
              ),
              if (control != null) ...[
                const SizedBox(height: 16),
                PropertyWidgetSelector(
                  choices: suggestion!.widgetChoices,
                  value: _widgetType ?? suggestion.type,
                  showCommandOverride: control.readOnly,
                  allowCommands: _allowCommands,
                  onAllowCommandsChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _allowCommands = value;
                          _widgetType = null;
                        }),
                  onChanged: _saving
                      ? null
                      : (type) => setState(() => _widgetType = type),
                ),
              ],
              const SizedBox(height: 16),
              if (dashboards != null && dashboards.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _dashboardId ?? dashboards.first.id,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.navDashboards),
                  items: [
                    for (final d in dashboards)
                      DropdownMenuItem(value: d.id, child: Text(d.name)),
                  ],
                  onChanged: _saving
                      ? null
                      : (id) => setState(() => _dashboardId = id),
                )
              else if (loaded.hasError)
                Text(l10n.wbAutoAddFailed)
              else if (dashboards == null)
                const LinearProgressIndicator()
              else
                Text(l10n.dashDefaultName),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving || dashboards == null ? null : _add,
                child: Text(_saving ? l10n.saving : l10n.addTileAdd),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
