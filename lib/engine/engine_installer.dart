import 'dart:async';
import 'dart:convert';

import 'engine_status.dart';

/// The two things the installer needs from a Home's broker connection, so
/// it is tested without one. Backed by MqttManager in the app.
abstract interface class HubLink {
  Stream<String> listen(String topic);
  void publish(String topic, String payload, {bool retain = false});
}

/// How a Zigbee2MQTT request ended.
enum HubAnswer {
  ok,

  /// Zigbee2MQTT answered with an error.
  refused,

  /// No answer in time. For an extension save this means Zigbee2MQTT
  /// blocks extensions (2.11+ fresh installs never answer then).
  noAnswer,
}

/// Installs, starts and removes the Engine through Zigbee2MQTT's own
/// bridge requests (zigdash-3.0.md §2). The extension loads at once; no
/// restart.
class EngineInstaller {
  EngineInstaller(this._link, {required this.base, this.answerWithin = const Duration(seconds: 10)});

  final HubLink _link;
  final String base;
  final Duration answerWithin;

  int _tx = 0;

  /// Sends a bridge request and waits for its response (matched by
  /// transaction id).
  Future<(HubAnswer, String?)> request(String name, Map<String, Object?> payload,
      {Duration? within}) async {
    final tx = 'zigdash-${DateTime.now().millisecondsSinceEpoch}-${_tx++}';
    final done = Completer<(HubAnswer, String?)>();
    final sub = _link.listen('$base/bridge/response/$name').listen((raw) {
      if (done.isCompleted || raw.isEmpty) return;
      try {
        final j = jsonDecode(raw) as Map;
        if (j['transaction'] != null && j['transaction'] != tx) return;
        done.complete(j['status'] == 'ok'
            ? (HubAnswer.ok, null)
            : (HubAnswer.refused, '${j['error'] ?? ''}'));
      } catch (_) {}
    });
    try {
      _link.publish('$base/bridge/request/$name', jsonEncode({...payload, 'transaction': tx}));
      return await done.future.timeout(within ?? answerWithin,
          onTimeout: () => (HubAnswer.noAnswer, null));
    } finally {
      await sub.cancel();
    }
  }

  /// Saves (installs or updates) the Engine.
  Future<(HubAnswer, String?)> install(String source) =>
      request('extension/save', {'name': engineExtensionName, 'code': source});

  Future<(HubAnswer, String?)> remove() =>
      request('extension/remove', {'name': engineExtensionName});

  /// The consent step: allow external JavaScript, then restart Zigbee2MQTT
  /// and wait for it to come back online (about 30 s of no Zigbee).
  Future<HubAnswer> allowExtensionsAndRestart({Duration backWithin = const Duration(seconds: 120)}) async {
    final (opt, _) = await request('options', {
      'options': {
        'advanced': {'enable_external_js': true},
      },
    });
    if (opt != HubAnswer.ok) return opt;
    final back = Completer<void>();
    var wentOffline = false;
    final sub = _link.listen('$base/bridge/state').listen((raw) {
      final online = raw.contains('online');
      if (!online) wentOffline = true;
      if (online && wentOffline && !back.isCompleted) back.complete();
    });
    try {
      _link.publish('$base/bridge/request/restart', '{}');
      await back.future.timeout(backWithin);
      return HubAnswer.ok;
    } on TimeoutException {
      return HubAnswer.noAnswer;
    } finally {
      await sub.cancel();
    }
  }

  /// "Start again" after the Engine stopped itself.
  void startAgain() =>
      _link.publish(EngineTopics.control, jsonEncode({'cmd': 'start'}));
}
