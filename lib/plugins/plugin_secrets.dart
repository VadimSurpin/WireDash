import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Separate from MQTT credentials so existing stores and integrations keep
/// their interface. Secrets are local; dashboard backups store references only.
class PluginSecretStore {
  PluginSecretStore(this.storage);
  final FlutterSecureStorage storage;
  Future<String?> read(String plugin, String key) =>
      storage.read(key: 'plugin::$plugin::$key');
  Future<void> write(String plugin, String key, String value) =>
      storage.write(key: 'plugin::$plugin::$key', value: value);
  Future<void> delete(String plugin, String key) =>
      storage.delete(key: 'plugin::$plugin::$key');
}

final pluginSecretsProvider = Provider<PluginSecretStore>(
  (ref) => PluginSecretStore(
    const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  ),
);
