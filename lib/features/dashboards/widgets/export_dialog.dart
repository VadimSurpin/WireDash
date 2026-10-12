import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../data/repositories/backup_files.dart';
import '../../../data/repositories/backup_service.dart';
import '../../../data/repositories/connection_repo.dart';

/// The Export dashboards dialog: copy the JSON, or save it as a .json file
/// through Android's file picker.
Future<void> showExportDashboardsDialog(
  BuildContext context,
  WidgetRef ref,
  String connectionId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final json = await ref
      .read(backupServiceProvider)
      .exportConnection(connectionId);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.dashExportTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: SelectableText(
            json,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.dashExportClose),
        ),
        TextButton.icon(
          icon: const Icon(Icons.copy),
          label: Text(l10n.dashExportCopy),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: json));
            if (ctx.mounted) Navigator.pop(ctx);
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.dashExportCopied)),
            );
          },
        ),
        // A .json file through Android's file picker: Drive, Downloads, a
        // USB stick (asked for in a Play review).
        FilledButton.icon(
          icon: const Icon(Icons.save_alt),
          label: Text(l10n.dashExportSaveFile),
          onPressed: () async {
            final home = ref
                .read(connectionByIdProvider(connectionId))
                .valueOrNull;
            final saved = await ref
                .read(backupFilesProvider)
                .save(backupFileName(home?.name ?? '', DateTime.now()), json);
            if (!saved) return;
            if (ctx.mounted) Navigator.pop(ctx);
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.dashExportSaved)),
            );
          },
        ),
      ],
    ),
  );
}
