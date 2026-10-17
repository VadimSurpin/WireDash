import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart' as mc;

import '../../mqtt/mqtt_manager.dart';
import '../../mqtt/providers/mqtt_manager_provider.dart';
import '../settings/providers/settings_controller.dart';
import 'app_recorder.dart';
import 'history_config.dart';
import 'history_record.dart';
import 'history_service.dart';

/// "Record history on this device" for one Home (2.9.1): off until the user
/// turns it on, stored on this device only, so exactly one device records.
class HistoryRecordHereSetting extends FamilyNotifier<bool, String> {
  String get _key => 'history_record_here_$arg';

  @override
  bool build(String arg) =>
      ref.read(sharedPreferencesProvider).getBool(_key) ?? false;

  Future<void> set(bool on) async {
    state = on;
    await ref.read(sharedPreferencesProvider).setBool(_key, on);
  }
}

final historyRecordHereProvider =
    NotifierProvider.family<HistoryRecordHereSetting, bool, String>(
      HistoryRecordHereSetting.new,
    );

/// The wall clock the recorder uses; tests replace it.
final historyRecorderNowProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

/// Records the Home's history while ZigDash is open on this device, when
/// the user chose this device (docs/design/history-without-node-red.md).
/// It writes what the Node-RED recorder writes: the heartbeat that tells
/// every phone a recorder is there, and the day records.
class AppHistoryRecorder extends ConsumerStatefulWidget {
  const AppHistoryRecorder({super.key, required this.connectionId});

  final String connectionId;

  @override
  ConsumerState<AppHistoryRecorder> createState() => _AppHistoryRecorderState();
}

class _AppHistoryRecorderState extends ConsumerState<AppHistoryRecorder> {
  final _folder = HistoryFolder();
  MqttManager? _mgr;
  Timer? _tick;
  final _subs = <String, StreamSubscription<MqttRxMessage>>{};
  bool _running = false;

  DateTime _now() => ref.read(historyRecorderNowProvider)();

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      historyRecordHereProvider(widget.connectionId),
      (_, on) => on ? _start() : _stop(switchedOff: true),
      fireImmediately: true,
    );
  }

  /// Only while recording: a Home that doesn't record here pays nothing.
  ProviderSubscription<AsyncValue<String>>? _config;

  Future<void> _start() async {
    if (_running) return;
    _running = true;
    final mgr = await ref.read(mqttManagerProvider(widget.connectionId).future);
    if (!mounted || !_running) return;
    _mgr = mgr;
    _publish(historyBridgeTopic, 'online');
    // Today's records come back retained: the slots recorded before a
    // restart of the app.
    final today = historyDate(_now());
    _listen('zigdash/history/+/+/$today', (m) {
      final parts = m.topic.split('/');
      if (parts.length != 5) return;
      _folder.restore(parts[2], parts[3], parts[4], m.payload);
    });
    _config = ref.listenManual(
      historyRetainedConfigProvider(widget.connectionId),
      (_, next) => _configure(next.valueOrNull ?? ''),
      fireImmediately: true,
    );
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => _flush());
  }

  void _configure(String retained) {
    if (!_running || _mgr == null) return;
    final readings = decodeHistoryReadings(retained);
    _folder.configure(readings);
    final topics = {for (final r in readings) r.topic};
    for (final t in _subs.keys.toList()) {
      if (t.startsWith('zigdash/') || topics.contains(t)) continue;
      _subs.remove(t)?.cancel();
      _mgr!.unsubscribe(t);
    }
    for (final t in topics) {
      if (_subs.containsKey(t)) continue;
      _listen(t, (m) {
        final Object? state;
        try {
          state = jsonDecode(m.payload);
        } on FormatException {
          return;
        }
        if (state is Map) {
          _folder.record(m.topic, Map<String, Object?>.from(state), _now());
        }
      });
    }
  }

  void _listen(String topic, void Function(MqttRxMessage) on) {
    _subs[topic] = _mgr!.subscribe(topic).listen(on);
  }

  void _flush() {
    if (!mounted || !_running) return;
    _folder.tick(_now()).forEach(_publish);
    // Reasserted each minute, as the Node-RED flow does every 30 s, so a
    // stale "offline" can't hide the graphs while this device records.
    _publish(historyBridgeTopic, 'online');
  }

  void _publish(String topic, String payload) => _mgr?.publish(
    topic,
    payload,
    '',
    qos: mc.MqttQos.atLeastOnce,
    retain: true,
  );

  /// [switchedOff]: the user turned recording off here (not the app
  /// closing): the open slot is published and the heartbeat says offline,
  /// so phones offer the Node-RED set-up again. A Node-RED recorder, if
  /// there is one, says online again within 30 s.
  void _stop({bool switchedOff = false}) {
    if (!_running) return;
    if (switchedOff) {
      _flush();
      _publish(historyBridgeTopic, 'offline');
    }
    _running = false;
    _config?.close();
    _config = null;
    _tick?.cancel();
    _tick = null;
    for (final e in _subs.entries) {
      e.value.cancel();
      _mgr?.unsubscribe(e.key);
    }
    _subs.clear();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
