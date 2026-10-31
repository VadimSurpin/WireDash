import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wiredash_plugin_api/wiredash_plugin_api.dart';
import 'package:wiredash_video/wiredash_video.dart';
import '../core/storage/secure_storage.dart';
import '../data/repositories/connection_repo.dart';
import '../data/database/tables/connections.dart';
import 'plugin_network.dart';
import 'plugin_secrets.dart';

final panelPluginsProvider = Provider<Map<String, WireDashPanelPlugin>>(
  (ref) => {VideoPanelPlugin.pluginId: const VideoPanelPlugin()},
);

final pluginHostProvider =
    Provider.family<PluginHost, ({String connectionId, String pluginId})>((
      ref,
      key,
    ) {
      final store = ref.watch(secureStorageProvider);
      return _Host(
        ref.watch(pluginSecretsProvider),
        key.pluginId,
        HomePluginNetwork(() async {
          final connection = await ref
              .read(connectionRepoProvider)
              .getById(key.connectionId);
          if (connection == null) throw StateError('The home was removed.');
          if (transportOf(connection.transport) !=
              ConnectionTransport.wireGuard) {
            return null;
          }
          final config = await store.readWireGuard(key.connectionId);
          if (config == null || config.isEmpty) {
            throw StateError('Configure WireGuard for this home.');
          }
          return config;
        }),
      );
    });

class _Host implements PluginHost {
  _Host(this.store, this.pluginId, this.network);
  final PluginSecretStore store;
  final String pluginId;
  @override
  final PluginNetwork network;
  @override
  Future<String?> readSecret(String key) => store.read(pluginId, key);
  @override
  Future<void> writeSecret(String key, String value) =>
      store.write(pluginId, key, value);
  @override
  Future<void> deleteSecret(String key) => store.delete(pluginId, key);
}

class MissingPanelPlugin extends StatelessWidget {
  const MissingPanelPlugin({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.extension_off_outlined),
          Text(title),
          const Text(
            'This panel plugin is unavailable. Its settings are preserved.',
          ),
        ],
      ),
    ),
  );
}
