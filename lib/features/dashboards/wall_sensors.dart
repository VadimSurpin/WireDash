import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../mqtt/providers/mqtt_manager_provider.dart';
import '../settings/providers/settings_controller.dart';

/// One state message from a device of the Home: its friendly name and the
/// decoded payload. [seq] makes every message distinct, so a motion sensor
/// repeating `occupancy: true` still counts each time.
typedef WallStateEvent = ({int seq, String name, Map<String, Object?> state});

typedef WallSensorArgs = ({String connectionId, String base});

/// Every device state message under the Home's base topic (no bridge
/// topics, no availability), for wake on motion and alarm takeover
/// (wall-tablet-2.9.md §4, §6). Listened to only while one of them is on.
final wallStateEventsProvider = StreamProvider.autoDispose
    .family<WallStateEvent, WallSensorArgs>((ref, args) async* {
      final mgr = await ref.read(mqttManagerProvider(args.connectionId).future);
      final pattern = '${args.base}/#';
      final stream = mgr.subscribe(pattern);
      ref.onDispose(() => mgr.unsubscribe(pattern));
      var seq = 0;
      await for (final msg in stream) {
        final topic = msg.topic;
        if (topic.length <= args.base.length + 1) continue;
        final name = topic.substring(args.base.length + 1);
        if (name.startsWith('bridge') || name.contains('/')) continue;
        final Object? decoded;
        try {
          decoded = jsonDecode(msg.payload);
        } on FormatException {
          continue;
        }
        if (decoded is! Map) continue;
        yield (
          seq: seq++,
          name: name,
          state: Map<String, Object?>.from(decoded),
        );
      }
    });

/// Someone is here: motion or presence detected, or a door or window opened
/// (Zigbee2MQTT reports a closed contact as `contact: true`).
bool wakesFor(Map<String, Object?> state) =>
    state['occupancy'] == true ||
    state['presence'] == true ||
    state['contact'] == false;

/// What alarm takeover reacts to (wall-tablet-2.9.md §6).
enum WallAlarmKind { leak, smoke, gas, co }

const _alarmProperties = {
  'water_leak': WallAlarmKind.leak,
  'smoke': WallAlarmKind.smoke,
  'gas': WallAlarmKind.gas,
  'carbon_monoxide': WallAlarmKind.co,
};

/// The alarms a state reports as active.
Set<WallAlarmKind> alarmsIn(Map<String, Object?> state) => {
  for (final e in _alarmProperties.entries)
    if (state[e.key] == true) e.value,
};

/// One device's alarm on the wall.
typedef WallAlarm = ({String name, WallAlarmKind kind});

/// Which alarms show: an alarm fires when a device starts reporting it, OK
/// puts it away, and it fires again only after that device has cleared and
/// reported it anew. Pure, so the order of events is easy to test.
class WallAlarmTracker {
  final _active = <String, Set<WallAlarmKind>>{};
  final _acknowledged = <String>{};

  /// The alarms on screen, oldest first.
  final List<WallAlarm> showing = [];

  /// Takes [state] from device [name]; true when what shows changed.
  bool update(String name, Map<String, Object?> state) {
    final now = alarmsIn(state);
    final before = _active[name] ?? const {};
    var changed = false;
    for (final kind in now.difference(before)) {
      final key = '$name/${kind.name}';
      if (_acknowledged.contains(key)) continue;
      showing.add((name: name, kind: kind));
      changed = true;
    }
    for (final kind in before.difference(now)) {
      _acknowledged.remove('$name/${kind.name}');
    }
    // A sensor that reports only some properties keeps the others' state.
    final reported = {
      for (final e in _alarmProperties.entries)
        if (state.containsKey(e.key)) e.value,
    };
    _active[name] = {...before.difference(reported), ...now};
    return changed;
  }

  /// OK on the alarm in front.
  void acknowledge() {
    if (showing.isEmpty) return;
    final a = showing.removeAt(0);
    _acknowledged.add('${a.name}/${a.kind.name}');
  }
}

/// The sensors that wake one dashboard's wall display, by IEEE address so a
/// rename keeps them. Empty: only touch wakes it.
class WallMotionSensorsSetting extends FamilyNotifier<List<String>, String> {
  String get _key => 'wall_motion_sensors_$arg';

  @override
  List<String> build(String arg) =>
      ref.read(sharedPreferencesProvider).getStringList(_key) ?? const [];

  Future<void> set(List<String> ieees) async {
    state = List.unmodifiable(ieees);
    await ref.read(sharedPreferencesProvider).setStringList(_key, ieees);
  }
}

final wallMotionSensorsProvider =
    NotifierProvider.family<WallMotionSensorsSetting, List<String>, String>(
      WallMotionSensorsSetting.new,
    );

/// Alarm takeover for one dashboard's wall display: off until turned on;
/// the sound is on unless turned off.
class WallAlarmSetting extends FamilyNotifier<({bool on, bool sound}), String> {
  String get _onKey => 'wall_alarms_$arg';
  String get _soundKey => 'wall_alarm_sound_$arg';

  @override
  ({bool on, bool sound}) build(String arg) {
    final prefs = ref.read(sharedPreferencesProvider);
    return (
      on: prefs.getBool(_onKey) ?? false,
      sound: prefs.getBool(_soundKey) ?? true,
    );
  }

  Future<void> setOn(bool on) async {
    state = (on: on, sound: state.sound);
    await ref.read(sharedPreferencesProvider).setBool(_onKey, on);
  }

  Future<void> setSound(bool sound) async {
    state = (on: state.on, sound: sound);
    await ref.read(sharedPreferencesProvider).setBool(_soundKey, sound);
  }
}

final wallAlarmProvider =
    NotifierProvider.family<WallAlarmSetting, ({bool on, bool sound}), String>(
      WallAlarmSetting.new,
    );
