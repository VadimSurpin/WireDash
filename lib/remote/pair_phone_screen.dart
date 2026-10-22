import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/l10n_ext.dart';
import '../core/router/routes.dart';
import '../data/repositories/connection_repo.dart';
import '../mqtt/providers/mqtt_manager_provider.dart';
import 'remote_pairing.dart';
import 'remote_setup.dart';

/// Opened by the camera app from another phone's QR code
/// (zigdash://remote/pair-phone?c=…): gives one of this phone's Homes the
/// remote login it carries.
class PairPhoneScreen extends ConsumerWidget {
  const PairPhoneScreen({super.key, required this.code});
  final String? code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final login = RemotePairing.fromCode(code);
    final homes = ref.watch(connectionsStreamProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.remotePairTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (login == null)
            Text(l10n.remotePairInvalid)
          else if (homes == null)
            const LinearProgressIndicator()
          else if (homes.isEmpty)
            Text(l10n.remotePairNoHomes)
          else ...[
            Text(l10n.remotePairBody, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 12),
            for (final h in homes)
              ListTile(
                key: Key('pair-home-${h.id}'),
                leading: const Icon(Icons.home_outlined),
                title: Text(h.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await ref.read(remoteSetupProvider).adopt(h.id, login);
                  ref.invalidate(remoteHomeProvider(h.id));
                  ref.invalidate(mqttManagerProvider(h.id));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.remotePairDone(h.name))));
                  context.go(Routes.homeDashboards(h.id));
                },
              ),
          ],
        ],
      ),
    );
  }
}
