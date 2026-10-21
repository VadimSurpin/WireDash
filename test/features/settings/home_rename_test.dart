import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/core/storage/secure_storage.dart';
import 'package:zigdash/data/database/daos/connection_dao.dart';
import 'package:zigdash/data/database/daos/dashboard_dao.dart';
import 'package:zigdash/data/database/database.dart';
import 'package:zigdash/data/database/tables/connections.dart';
import 'package:zigdash/data/repositories/connection_repo.dart';
import 'package:zigdash/data/repositories/dashboard_repo.dart';
import 'package:zigdash/features/settings/home_rename.dart';

class _MemSecure implements SecureStore {
  final _wireGuard = <String, String>{};
  @override
  Future<String?> readWireGuard(String id) async => _wireGuard[id];
  @override
  Future<void> writeWireGuard(String id, String config) async => _wireGuard[id] = config;
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

// Renaming a Home renames the dashboards still named after it (2.4.1).

void main() {
  late AppDatabase db;
  late ConnectionRepo connections;
  late DashboardRepo dashboards;
  final t = DateTime(2026, 10, 11);

  setUp(() async {
    db = AppDatabase.test(NativeDatabase.memory());
    connections = ConnectionRepo(ConnectionDao(db), _MemSecure());
    dashboards = DashboardRepo(DashboardDao(db));
    await db.into(db.connections).insert(ConnectionsCompanion.insert(
        id: 'c1', name: '10.0.2.2', host: '10.0.2.2', port: 1883,
        protocol: MqttProtocol.tcp, createdAt: t, updatedAt: t));
    for (final (id, name) in [
      ('byHost', '10.0.2.2'),
      ('mine', 'Upstairs'),
    ]) {
      await db.into(db.dashboards).insert(DashboardsCompanion.insert(
          id: id, connectionId: 'c1', name: name, colorSeed: 7,
          iconCodepoint: 42, createdAt: t, updatedAt: t));
    }
  });
  tearDown(() => db.close());

  test('a dashboard named after the host follows; a named one stays', () async {
    final home = (await connections.getById('c1'))!;
    await renameHome(connections, dashboards, home, 'Beach house');
    expect((await connections.getById('c1'))!.name, 'Beach house');
    final byId = {for (final d in await dashboards.getByConnection('c1')) d.id: d};
    expect(byId['byHost']!.name, 'Beach house');
    expect(byId['byHost']!.colorSeed, 7, reason: 'only the name changes');
    expect(byId['mine']!.name, 'Upstairs');
  });

  test('a dashboard named after the old Home name follows too', () async {
    var home = (await connections.getById('c1'))!;
    await renameHome(connections, dashboards, home, 'Beach house');
    home = (await connections.getById('c1'))!;
    await renameHome(connections, dashboards, home, 'Cabin');
    final byId = {for (final d in await dashboards.getByConnection('c1')) d.id: d};
    expect(byId['byHost']!.name, 'Cabin');
    expect(byId['mine']!.name, 'Upstairs');
  });
}
