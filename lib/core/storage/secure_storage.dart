import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _passwordPrefix = 'mqtt_pw::';
const _wireGuardPrefix = 'wireguard::';

class SecureStore {
  SecureStore(this._storage);
  final FlutterSecureStorage _storage;

  Future<String?> readPassword(String connectionId) =>
      _storage.read(key: '$_passwordPrefix$connectionId');

  Future<void> writePassword(String connectionId, String password) =>
      _storage.write(key: '$_passwordPrefix$connectionId', value: password);

  Future<void> deletePassword(String connectionId) =>
      _storage.delete(key: '$_passwordPrefix$connectionId');

  Future<String?> readWireGuard(String connectionId) =>
      _storage.read(key: '$_wireGuardPrefix$connectionId');

  Future<void> writeWireGuard(String connectionId, String config) =>
      _storage.write(key: '$_wireGuardPrefix$connectionId', value: config);

  Future<void> deleteWireGuard(String connectionId) =>
      _storage.delete(key: '$_wireGuardPrefix$connectionId');
}

/// The password store as the app configures it; also used by the headless
/// shortcut engine, which has no Riverpod container.
SecureStore createSecureStore() => SecureStore(
  const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  ),
);

final secureStorageProvider = Provider<SecureStore>(
  (ref) => createSecureStore(),
);
