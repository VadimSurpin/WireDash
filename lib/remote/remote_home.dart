import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';


/// What one phone needs to reach a Home through the ZigDash relay: the
/// Home's relay id, this phone's relay login and the Home's key. Kept in
/// the phone's secure storage only; the key never reaches the relay.
class RemoteHome {
  const RemoteHome({
    required this.homeId,
    required this.url,
    required this.username,
    required this.password,
    required this.key,
  });

  final String homeId;

  /// wss://relay.zigdash.app/mqtt (or a test relay).
  final String url;
  final String username;
  final String password;

  /// The Home's 32-byte key.
  final Uint8List key;

  String get prefix => 'homes/$homeId';

  Map<String, Object?> toJson() => {
        'homeId': homeId,
        'url': url,
        'username': username,
        'password': password,
        'key': base64.encode(key),
      };

  static RemoteHome? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      final key = base64.decode('${j['key']}');
      if (key.length != 32) return null;
      return RemoteHome(
        homeId: '${j['homeId']}',
        url: '${j['url']}',
        username: '${j['username']}',
        password: '${j['password']}',
        key: Uint8List.fromList(key),
      );
    } catch (_) {
      return null;
    }
  }
}

const _remotePrefix = 'remote_home::';

/// Remote homes by connection id, in secure storage.
class RemoteHomeStore {
  RemoteHomeStore(this._storage);
  final FlutterSecureStorage _storage;

  Future<RemoteHome?> read(String connectionId) async {
    final raw = await _storage.read(key: '$_remotePrefix$connectionId');
    if (raw == null) return null;
    try {
      return RemoteHome.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String connectionId, RemoteHome home) =>
      _storage.write(key: '$_remotePrefix$connectionId', value: jsonEncode(home.toJson()));

  Future<void> delete(String connectionId) => _storage.delete(key: '$_remotePrefix$connectionId');
}

RemoteHomeStore createRemoteHomeStore() => RemoteHomeStore(
      const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true)),
    );

final remoteHomeStoreProvider = Provider<RemoteHomeStore>((ref) => createRemoteHomeStore());
