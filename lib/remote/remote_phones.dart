import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/l10n/l10n_ext.dart';
import '../data/repositories/backup_files.dart';
import '../l10n/app_localizations.dart';
import '../mqtt/providers/mqtt_manager_provider.dart';
import 'remote_home.dart';
import 'remote_pairing.dart';
import 'remote_setup.dart';

/// The Home's phones on the relay; null when the relay can't be asked.
final remotePhonesProvider = FutureProvider.autoDispose.family<List<RemotePhone>?, String>(
    (ref, connectionId) => ref.watch(remoteSetupProvider).phones(connectionId));

/// Phones with remote access, adding one by QR code, and the key backup
/// (3.1, zigdash-3.0.md §5). Shown on the Remote screen once remote is on.
class RemotePhonesSection extends ConsumerWidget {
  const RemotePhonesSection({super.key, required this.connectionId});
  final String connectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final phones = ref.watch(remotePhonesProvider(connectionId));
    final ml = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(l10n.remotePhones.toUpperCase(), style: theme.textTheme.labelLarge),
        ...switch (phones) {
          AsyncData(:final value?) => [
              for (final p in value)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(p.thisPhone ? Icons.smartphone : Icons.phone_android_outlined),
                  title: Text(p.thisPhone ? l10n.remoteThisPhone : l10n.remoteOtherPhone),
                  subtitle: Text(l10n.remotePhoneAdded(ml.formatMediumDate(p.created))),
                  trailing: p.thisPhone
                      ? null
                      : IconButton(
                          tooltip: l10n.remoteRemovePhone,
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => _remove(context, ref, p),
                        ),
                ),
            ],
          AsyncData() || AsyncError() => [Text(l10n.remoteUnreachable)],
          _ => [const LinearProgressIndicator()],
        },
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          key: const Key('remote-add-phone'),
          onPressed: () => _addPhone(context, ref),
          icon: const Icon(Icons.qr_code_2),
          label: Text(l10n.remoteAddPhone),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const Key('remote-backup'),
          onPressed: () => _backup(context, ref),
          icon: const Icon(Icons.key_outlined),
          label: Text(l10n.remoteBackupSave),
        ),
      ],
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, RemotePhone p) async {
    final l10n = context.l10n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.remoteRemovePhoneConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.remoteRemovePhone)),
        ],
      ),
    );
    if (yes != true) return;
    await ref.read(remoteSetupProvider).removePhone(connectionId, p.username);
    ref.invalidate(remotePhonesProvider(connectionId));
  }

  Future<void> _addPhone(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final login = await ref.read(remoteSetupProvider).newPhone(connectionId);
    if (!context.mounted) return;
    if (login == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.remoteAddPhoneFailed)));
      return;
    }
    ref.invalidate(remotePhonesProvider(connectionId));
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.remoteAddPhone),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                color: Colors.white, // a QR code needs a light quiet zone in dark mode too
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  key: const Key('remote-qr'),
                  data: RemotePairing.link(login),
                  size: 240,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(l10n.remoteAddPhoneHint),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(MaterialLocalizations.of(ctx).closeButtonLabel)),
        ],
      ),
    );
  }

  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final passphrase = await askPassphrase(context, l10n, confirm: true);
    if (passphrase == null) return;
    final home = await ref.read(remoteHomeStoreProvider).read(connectionId);
    if (home == null) return;
    final saved = await ref.read(backupFilesProvider).save('zigdash-remote-key.json', RemotePairing.backup(home, passphrase));
    if (saved) messenger.showSnackBar(SnackBar(content: Text(l10n.remoteBackupSaved)));
  }
}

/// Asks for the backup passphrase; with [confirm], twice, and at least 8 characters.
Future<String?> askPassphrase(BuildContext context, AppLocalizations l10n, {bool confirm = false}) {
  final a = TextEditingController(), b = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final ok = a.text.length >= 8 && (!confirm || a.text == b.text);
        return AlertDialog(
          title: Text(l10n.remoteBackupPassphrase),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(confirm ? l10n.remoteBackupPassphraseHint : l10n.remoteBackupPassphraseAsk),
              TextField(
                key: const Key('passphrase-1'),
                controller: a,
                obscureText: true,
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
              if (confirm)
                TextField(
                  key: const Key('passphrase-2'),
                  controller: b,
                  obscureText: true,
                  decoration: InputDecoration(labelText: l10n.remoteBackupPassphraseAgain),
                  onChanged: (_) => setState(() {}),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
            FilledButton(onPressed: ok ? () => Navigator.pop(ctx, a.text) : null, child: Text(MaterialLocalizations.of(ctx).okButtonLabel)),
          ],
        );
      },
    ),
  );
}

/// Restores a Home's remote login from a backup file onto this phone.
Future<bool> restoreRemoteBackup(BuildContext context, WidgetRef ref, String connectionId) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  String? text;
  try {
    text = await ref.read(backupFilesProvider).open();
  } on FormatException {
    text = null;
  }
  if (text == null || !context.mounted) return false;
  if (!RemotePairing.isBackup(text)) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.remoteBackupWrongFile)));
    return false;
  }
  final passphrase = await askPassphrase(context, l10n);
  if (passphrase == null) return false;
  final home = RemotePairing.restore(text, passphrase);
  if (home == null) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.remoteBackupWrong)));
    return false;
  }
  await ref.read(remoteSetupProvider).adopt(connectionId, home);
  ref.invalidate(remoteHomeProvider(connectionId));
  ref.invalidate(mqttManagerProvider(connectionId));
  return true;
}
