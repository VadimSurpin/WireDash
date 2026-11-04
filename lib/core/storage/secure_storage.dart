import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _passwordPrefix = 'mqtt_pw::';
const _wireGuardPrefix = 'wireguard::';

// Keep the existing Android store name explicit. The headless backend watches
// this file's metadata to avoid decrypting unchanged settings on every tap.
const secureStoragePreferencesName = 'FlutterSecureStorage';

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
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      sharedPreferencesName: secureStoragePreferencesName,
    ),
  ),
);

final secureStorageProvider = Provider<SecureStore>(
  (ref) => createSecureStore(),
);
