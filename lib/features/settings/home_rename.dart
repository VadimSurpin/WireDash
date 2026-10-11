import '../../data/database/database.dart';
import '../../data/repositories/connection_repo.dart';
import '../../data/repositories/dashboard_repo.dart';

/// Renames [home] to [name], and with it any of its dashboards still named
/// after the Home (its old name, or its address: a manual setup names the
/// first dashboard after the host). A dashboard the user named stays.
Future<void> renameHome(
  ConnectionRepo connections,
  DashboardRepo dashboards,
  Connection home,
  String name,
) async {
  await connections.rename(home.id, name);
  final followers = {home.name, home.host};
  for (final d in await dashboards.getByConnection(home.id)) {
    if (!followers.contains(d.name)) continue;
    await dashboards.update(
      id: d.id,
      name: name,
      topicPrefix: d.topicPrefix,
      colorSeed: d.colorSeed,
      iconCodepoint: d.iconCodepoint,
      locked: d.locked,
    );
  }
}
