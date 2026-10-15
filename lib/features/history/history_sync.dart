import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/daos/device_registry_dao.dart';
import '../../data/database/database.dart';
import 'history_service.dart';

/// The devices on a Home's dashboards; changes when tiles come or go.
final _linkedIeeesProvider = StreamProvider.autoDispose
    .family<Set<String>, String>(
      (ref, connectionId) => DeviceRegistryDao(
        ref.watch(appDatabaseProvider),
      ).watchLinkedIeees(connectionId),
    );

/// Invisible, on the dashboard: while the Home's recorder runs, keeps its
/// config in step with the dashboards (2.7). Publishes only when the
/// retained config differs from what the dashboards say now, a couple of
/// seconds after the last change, so editing a dashboard sends one update.
class HistorySync extends ConsumerStatefulWidget {
  const HistorySync({super.key, required this.connectionId});

  final String connectionId;

  @override
  ConsumerState<HistorySync> createState() => _HistorySyncState();
}

class _HistorySyncState extends ConsumerState<HistorySync> {
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final id = widget.connectionId;
    // Everything else is watched only once a recorder answers, so a Home
    // without one costs a single retained subscription.
    ref.listenManual(historyRecorderOnlineProvider(id), (_, next) {
      if (next.valueOrNull == true && !_watching) {
        _watching = true;
        ref.listenManual(historyRetainedConfigProvider(id), (_, _) => _soon());
        ref.listenManual(_linkedIeeesProvider(id), (_, _) => _soon());
      }
      _soon();
    });
  }

  bool _watching = false;

  void _soon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _sync);
  }

  Future<void> _sync() async {
    if (!mounted) return;
    final id = widget.connectionId;
    final online = ref.read(historyRecorderOnlineProvider(id)).valueOrNull;
    if (online != true) return;
    final current = ref.read(historyRetainedConfigProvider(id)).valueOrNull;
    await ref.read(historyServiceProvider).publishConfig(id, current: current);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
