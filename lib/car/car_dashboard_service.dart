import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart' as mc;

import '../data/database/database.dart';
import '../data/database/daos/dashboard_dao.dart';
import '../data/database/daos/panel_dao.dart';
import '../data/database/daos/section_dao.dart';
import '../l10n/app_localizations.dart';
import '../mqtt/json_path.dart';
import '../mqtt/mqtt_manager.dart';
import '../mqtt/mqtt_status.dart';
import 'car_control.dart';

class _Pending {
  _Pending(this.action, this.sentAt, this.generation);
  final CarAction action;
  final DateTime sentAt;
  final int generation;
  Timer? timer;
}

/// A read-only view of saved dashboards for the native Android Auto host.
/// Reuses the headless engine's broker managers and secure connection setup.
/// Watching and reconnecting never publishes control commands.
class CarDashboardService {
  CarDashboardService({
    required this.database,
    required this.manager,
    required this.localizations,
    DateTime Function()? now,
    Timer Function(Duration, void Function())? schedule,
  }) : now = now ?? DateTime.now,
       schedule = schedule ?? Timer.new;
  final Future<AppDatabase> Function() database;
  final Future<MqttManager?> Function(String) manager;
  final Future<AppLocalizations> Function() localizations;
  final DateTime Function() now;
  final Timer Function(Duration, void Function()) schedule;
  Future<void> _tail = Future.value();
  MqttManager? _manager;
  Dashboard? _dashboard;
  List<CarControl> _controls = [];
  List<Section> _sections = [];
  final _subscriptions = <String, StreamSubscription<MqttRxMessage>>{};
  final _states = <String, MqttRxMessage>{};
  final _pending = <String, _Pending>{};
  final _failed = <String>{};

  Future<T> _serial<T>(Future<T> Function() work) {
    final next = _tail.then((_) => work());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<Map<String, Object?>> catalog() => _serial(() async {
    final db = await database();
    final homes = await db.select(db.connections).get();
    final result = <Map<String, Object?>>[];
    final l10n = await localizations();
    for (final home in homes) {
      for (final dash in await DashboardDao(db).getByConnection(home.id)) {
        final controls = carControls(
          dash,
          await PanelDao(db).getByDashboard(dash.id),
          l10n,
        );
        if (controls.isNotEmpty) {
          result.add({'id': dash.id, 'name': dash.name, 'home': home.name});
        }
      }
    }
    return {'dashboards': result};
  });

  Future<Map<String, Object?>> open(String id) => _serial(() => _open(id));

  Future<Map<String, Object?>> _open(String id) async {
    final db = await database();
    final dash = await DashboardDao(db).getById(id);
    if (dash == null) {
      await _close();
      return {'outcome': 'removed'};
    }
    final mgr = await manager(dash.connectionId);
    if (mgr == null) {
      await _close();
      return {'outcome': 'removed'};
    }
    final l10n = await localizations();
    if (_dashboard?.id != id || !identical(mgr, _manager)) {
      await _close();
      _manager = mgr;
      _dashboard = dash;
      // Android can suspend both the tunnel and the MQTT receive path while
      // the car app is hidden. Establish a fresh session when reopening it.
      mgr.reconnectNow(force: true);
    }
    _dashboard = dash;
    final previous = {for (final c in _controls) c.id: c.commandSignature};
    _sections = await SectionDao(db).getByDashboard(id);
    final panels = await PanelDao(db).getByDashboard(id);
    final knownSections = _sections.map((s) => s.id).toSet();
    // Match the phone: unsectioned/orphaned tiles first, then saved section
    // order, retaining panel order inside each section.
    _controls = carControls(dash, [
      for (final panel in panels)
        if (!knownSections.contains(panel.sectionId)) panel,
      for (final section in _sections)
        for (final panel in panels)
          if (panel.sectionId == section.id) panel,
    ], l10n);
    for (final c in _controls) {
      if (previous[c.id] != c.commandSignature) {
        _finish(c.id);
        _failed.remove(c.id);
      }
    }
    final topics = _controls.expand((c) => c.topics).toSet();
    for (final topic in _subscriptions.keys.toList()) {
      if (!topics.contains(topic)) {
        await _subscriptions.remove(topic)!.cancel();
        mgr.unsubscribe(topic);
        _states.remove(topic);
      }
    }
    for (final topic in topics) {
      _subscriptions.putIfAbsent(
        topic,
        () => mgr.subscribe(topic).listen((message) {
          if (!identical(_manager, mgr)) return;
          _states[message.topic] = message;
          for (final control in _controls) {
            final pending = _pending[control.id];
            if (pending != null && _confirms(control, pending)) {
              _finish(control.id);
            }
          }
        }),
      );
    }
    final ids = _controls.map((c) => c.id).toSet();
    for (final id in _pending.keys.toList()) {
      if (!ids.contains(id)) _finish(id);
    }
    return {
      'id': dash.id,
      'name': dash.name,
      'connected': mgr.isConnected && mgr.status == MqttStatus.connected,
      'status': mgr.status.name,
      'sections': [
        for (final section in _sections)
          if (_controls.any((c) => c.sectionId == section.id))
            {'id': section.id, 'name': section.name},
      ],
      'strings': {
        'on': l10n.panelStateOn,
        'off': l10n.panelStateOff,
        'open': l10n.panelCoverOpen,
        'close': l10n.panelCoverClose,
        'stop': l10n.panelCoverStop,
        'reconnecting': l10n.connectionReconnecting,
        'working': l10n.shortcutWorking,
        'unconfirmed': l10n.shortcutNotConfirmed,
        'sent': l10n.shortcutSceneSent,
      },
      'controls': [for (final control in _controls) _describe(control)],
    };
  }

  bool _fresh(MqttRxMessage? message) =>
      message != null &&
      _manager != null &&
      _manager!.isConnected &&
      _manager!.status == MqttStatus.connected &&
      message.connectionGeneration == _manager!.connectionGeneration;

  String? _value(CarControl c) {
    if (!c.waitForFeedback) return null;
    final binding = c.binding;
    if (binding != null) {
      final open = _states[binding.openTopic],
          close = _states[binding.closeTopic];
      if (!_fresh(open) || !_fresh(close)) return null;
      // Relay activity is direction feedback, never a claimed gate position.
      if (open!.payload == '1' && close!.payload == '0') return 'OPEN';
      if (close!.payload == '1' && open.payload == '0') return 'CLOSE';
      return 'STOP';
    }
    final message = c.topics.isEmpty ? null : _states[c.topics.first];
    if (!_fresh(message)) return null;
    final raw = extractByPath(message!.payload, c.path)?.toString();
    if (c.kind != 'cover') return raw;
    return switch (raw?.toUpperCase()) {
      'CLOSED' => 'CLOSE',
      'OPENED' => 'OPEN',
      'STOPPED' => 'STOP',
      final value => value,
    };
  }

  Map<String, Object?> _describe(CarControl c) {
    final value = _value(c);
    final state = c.kind == 'switch' && value != null
        ? (value == c.onMatch ? 'ON' : 'OFF')
        : value;
    return {
      'id': c.id,
      'name': c.name,
      'kind': c.kind,
      'sectionId': _sections.any((s) => s.id == c.sectionId)
          ? c.sectionId
          : null,
      'waitForFeedback': c.waitForFeedback,
      'state': state,
      'position': _position(c),
      'pending': _pending[c.id]?.action.id,
      'failed': c.waitForFeedback && _failed.contains(c.id),
      'actions': [for (final action in c.actions) action.toJson()],
    };
  }

  num? _position(CarControl c) {
    if (!c.waitForFeedback || c.positionPath == null || c.topics.isEmpty) {
      return null;
    }
    final message = _states[c.topics.first];
    if (!_fresh(message)) return null;
    final value = num.tryParse(
      '${extractByPath(message!.payload, c.positionPath)}',
    );
    return value != null && value.isFinite && value >= 0 && value <= 100
        ? value
        : null;
  }

  bool _confirms(CarControl c, _Pending p) {
    if (!c.waitForFeedback) return false;
    bool after(String topic, [String? value]) {
      final m = _states[topic];
      return _fresh(m) &&
          m!.connectionGeneration == p.generation &&
          m.receivedAt.isAfter(p.sentAt) &&
          (value == null
              ? const ['0', '1'].contains(m.payload)
              : m.payload == value);
    }

    final wb = c.binding;
    if (wb != null) {
      return switch (p.action.id) {
        'OPEN' => after(wb.openTopic),
        'CLOSE' => after(wb.closeTopic),
        'STOP' => after(wb.openTopic, '0') && after(wb.closeTopic, '0'),
        _ => false,
      };
    }
    if (c.topics.isEmpty) return false;
    final m = _states[c.topics.first];
    if (!_fresh(m) ||
        m!.connectionGeneration != p.generation ||
        !m.receivedAt.isAfter(p.sentAt)) {
      return false;
    }
    if (p.action.position != null) return _position(c) == p.action.position;
    final value = _value(c);
    if (value == null) return false;
    if (p.action.stateMatch != null) return value == p.action.stateMatch;
    if (c.kind == 'switch') {
      return (value == c.onMatch) == (p.action.id == 'ON');
    }
    final normalized = value.toUpperCase();
    return normalized == p.action.id ||
        (p.action.id == 'CLOSE' && normalized == 'CLOSED') ||
        (p.action.id == 'STOP' && normalized == 'STOPPED');
  }

  Future<Map<String, Object?>> command(
    String dashboardId,
    String controlId,
    String actionId, {
    int? expiresAt,
  }) {
    final deadline =
        expiresAt ??
        now().add(const Duration(seconds: 5)).millisecondsSinceEpoch;
    return _serial(() async {
      if (now().millisecondsSinceEpoch > deadline) {
        return {'outcome': 'unreachable'};
      }
      final snapshot = await _open(dashboardId);
      if (snapshot['outcome'] == 'removed') return snapshot;
      final control = _controls.where((c) => c.id == controlId).firstOrNull;
      final action = control?.actions
          .where((a) => a.id == actionId)
          .firstOrNull;
      if (control == null || action == null || action.commands.isEmpty) {
        return {'outcome': 'removed'};
      }
      final mgr = _manager!;
      if (!mgr.isConnected ||
          mgr.status != MqttStatus.connected ||
          now().millisecondsSinceEpoch > deadline) {
        return {'outcome': 'unreachable'};
      }
      _finish(controlId);
      _failed.remove(controlId);
      final pending = _Pending(action, now(), mgr.connectionGeneration);
      _pending[controlId] = pending;
      for (final command in action.commands) {
        mgr.publish(
          command.topic,
          command.payload,
          '',
          retain: command.retain,
          qos: mc.MqttQos.values[command.qos],
        );
      }
      pending.timer = schedule(
        Duration(seconds: control.waitForFeedback ? 15 : 1),
        () {
          if (!identical(_pending[controlId], pending)) return;
          if (control.waitForFeedback) _failed.add(controlId);
          _finish(controlId);
        },
      );
      return {'outcome': 'sent', 'waitForFeedback': control.waitForFeedback};
    });
  }

  void _finish(String id) => _pending.remove(id)?.timer?.cancel();

  Future<void> close() => _serial(_close);
  Future<void> _close() async {
    final mgr = _manager;
    _manager = null;
    _dashboard = null;
    for (final entry in _subscriptions.entries) {
      await entry.value.cancel();
      mgr?.unsubscribe(entry.key);
    }
    _subscriptions.clear();
    _states.clear();
    for (final p in _pending.values) {
      p.timer?.cancel();
    }
    _pending.clear();
    _failed.clear();
    _controls = [];
    _sections = [];
  }
}
