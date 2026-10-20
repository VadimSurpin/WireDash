import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/core/storage/secure_storage.dart';
import 'package:zigdash/data/database/daos/connection_dao.dart';
import 'package:zigdash/data/database/database.dart';
import 'package:zigdash/data/database/tables/connections.dart';
import 'package:zigdash/data/repositories/connection_repo.dart';

class _MemSecure implements SecureStore {
  final m = <String, String>{};
  @override
  Future<void> writePassword(String id, String pw) async => m[id] = pw;
  @override
  Future<String?> readPassword(String id) async => m[id];
  @override
  Future<void> deletePassword(String id) async => m.remove(id);
}

void main() {
  test(
    'signing in again replaces the address and the stored sign-in only',
    () async {
      final db = AppDatabase.test(NativeDatabase.memory());
      addTearDown(db.close);
      final secure = _MemSecure();
      final repo = ConnectionRepo(ConnectionDao(db), secure);
      final id = await repo.create(
        name: 'Casa',
        host: 'http://192.168.68.52:8123',
        port: 8123,
        protocol: MqttProtocol.ws,
        password: 'refresh:old',
        autoConnect: true,
        transport: ConnectionTransport.homeAssistant,
      );
      await repo.setBaseTopic(id, 'z2m');

      await repo.setHomeAssistantSignIn(
        id,
        address: Uri.parse('https://abc.ui.nabu.casa'),
        signIn: 'refresh:new',
      );

      final row = (await repo.getById(id))!;
      expect(row.host, 'https://abc.ui.nabu.casa');
      expect(row.port, 443);
      expect(row.protocol, MqttProtocol.wss);
      expect(row.transport, ConnectionTransport.homeAssistant);
      expect(row.name, 'Casa');
      expect(row.autoConnect, isTrue);
      expect(row.z2mBaseTopic, 'z2m');
      expect(secure.m[id], 'refresh:new');
    },
  );
}
