import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/core/storage/secure_storage.dart';
import 'package:wiredash/data/database/daos/connection_dao.dart';
import 'package:wiredash/data/database/database.dart';
import 'package:wiredash/data/database/tables/connections.dart';
import 'package:wiredash/data/repositories/connection_repo.dart';

/// In-memory SecureStore stub (no platform channel in unit tests).
class _MemSecure implements SecureStore {
  final _wireGuard = <String, String>{};
  @override
  Future<String?> readWireGuard(String id) async => _wireGuard[id];
  @override
  Future<void> writeWireGuard(String id, String config) async =>
      _wireGuard[id] = config;
  @override
  Future<void> deleteWireGuard(String id) async => _wireGuard.remove(id);

  final _m = <String, String>{};
  @override
  Future<void> writePassword(String id, String pw) async => _m[id] = pw;
  @override
  Future<String?> readPassword(String id) async => _m[id];
  @override
  Future<void> deletePassword(String id) async => _m.remove(id);
}

void main() {
  test(
    'WireGuard marker survives without keys and deleting home removes keys',
    () async {
      final db = AppDatabase.test(NativeDatabase.memory());
      addTearDown(db.close);
      final secure = _MemSecure();
      final repo = ConnectionRepo(ConnectionDao(db), secure);
      final id = await repo.create(
        name: 'WG home',
        host: '10.20.0.1',
        port: 1883,
        protocol: MqttProtocol.tcp,
        transport: ConnectionTransport.wireGuard,
        wireGuardConfig: 'private configuration',
      );
      expect(
        (await repo.getById(id))!.transport,
        ConnectionTransport.wireGuard,
      );
      expect(await repo.readWireGuard(id), 'private configuration');
      await secure.deleteWireGuard(id);
      expect(
        (await repo.getById(id))!.transport,
        ConnectionTransport.wireGuard,
      );
      await secure.writeWireGuard(id, 'replacement configuration');
      await repo.delete(id);
      expect(await secure.readWireGuard(id), isNull);
    },
  );
  test('create + read back persists remoteHost', () async {
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ConnectionRepo(ConnectionDao(db), _MemSecure());

    final id = await repo.create(
      name: 'home',
      host: '192.168.7.210',
      port: 1883,
      protocol: MqttProtocol.tcp,
      remoteHost: 'smhub.tailnet.ts.net',
    );

    final row = await repo.getById(id);
    expect(row!.remoteHost, 'smhub.tailnet.ts.net');
  });

  test('null remoteHost stays null', () async {
    final db = AppDatabase.test(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ConnectionRepo(ConnectionDao(db), _MemSecure());

    final id = await repo.create(
      name: 'home',
      host: '192.168.7.210',
      port: 1883,
      protocol: MqttProtocol.tcp,
    );
    final row = await repo.getById(id);
    expect(row!.remoteHost, isNull);
  });
}
