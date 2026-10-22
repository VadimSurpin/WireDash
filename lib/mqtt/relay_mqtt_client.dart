// Reaches a Home through the ZigDash relay when its broker can't be reached
// (3.1, zigdash-3.0.md §5).
//
// Looks like an mqtt_client [mc.MqttClient] to MqttManager, but underneath
// is one MQTT-over-WebSocket connection to the relay with this phone's relay
// login:
//   - it subscribes to homes/<id>/s/# (device states, retained and sealed)
//     and homes/<id>/hub (whether the hub is connected);
//   - every relay message is unsealed with the Home's key and handed up under
//     its real topic, so dashboards, tiles and history work unchanged;
//   - every publish is sealed with its real topic and the time, and sent to
//     homes/<id>/c, where ZigDash Engine on the hub checks and applies it;
//   - subscriptions are local only: all retained states arrive on connect.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:mqtt_client/mqtt_client.dart' as mc;
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:typed_data/typed_data.dart' as typed;

import '../remote/remote_home.dart';
import '../remote/remote_seal.dart';

typedef RelayTransportFactory = mc.MqttClient Function(RemoteHome home, String clientId);

mc.MqttClient defaultRelayTransport(RemoteHome home, String clientId) {
  final uri = Uri.parse(home.url);
  final client = MqttServerClient.withPort(
    '${uri.scheme}://${uri.host}${uri.path}',
    clientId,
    uri.hasPort ? uri.port : (uri.scheme == 'wss' ? 443 : 80),
  )
    ..useWebSocket = true
    ..websocketProtocols = ['mqtt']
    ..secure = false; // TLS comes from the wss:// scheme for WebSockets
  return client;
}

class RelayMqttClient extends mc.MqttClient {
  RelayMqttClient(this.home, String clientId, {RelayTransportFactory? transport})
      : _transport = (transport ?? defaultRelayTransport)(home, clientId),
        super(home.url, clientId);

  final RemoteHome home;
  final mc.MqttClient _transport;

  /// Whether ZigDash Engine on the hub is connected to the relay; null until known.
  bool? hubOnline;
  final _hub = StreamController<bool>.broadcast();
  Stream<bool> get hubOnline$ => _hub.stream;

  final _updates = StreamController<List<mc.MqttReceivedMessage<mc.MqttMessage>>>();
  StreamSubscription<Object?>? _sub;

  @override
  mc.MqttClientConnectionStatus? get connectionStatus => _transport.connectionStatus;

  @override
  Stream<List<mc.MqttReceivedMessage<mc.MqttMessage>>>? get updates => _updates.stream;

  @override
  Stream<mc.MqttPublishMessage>? get published => _transport.published;

  @override
  void logging({required bool on, bool logPayloads = true}) => _transport.logging(on: on);

  @override
  set keepAlivePeriod(int value) => _transport.keepAlivePeriod = value;

  @override
  set connectTimeoutPeriod(int value) => _transport.connectTimeoutPeriod = value;

  @override
  set autoReconnect(bool value) => _transport.autoReconnect = value;

  /// The Home's relay login is used; the broker login passed in is not.
  @override
  Future<mc.MqttClientConnectionStatus?> connect([String? username, String? password]) async {
    _transport.connectionMessage = mc.MqttConnectMessage()
        .withClientIdentifier(clientIdentifier)
        .startClean();
    _transport.onDisconnected = () => onDisconnected?.call();
    _transport.pongCallback = () => pongCallback?.call();
    final status = await _transport.connect(home.username, home.password);
    if (_transport.connectionStatus?.state == mc.MqttConnectionState.connected) {
      await _sub?.cancel();
      _sub = _transport.updates?.listen(_onRelay);
      _transport.subscribe('${home.prefix}/s/#', mc.MqttQos.atMostOnce);
      _transport.subscribe('${home.prefix}/hub', mc.MqttQos.atLeastOnce);
    }
    return status;
  }

  void _onRelay(List<mc.MqttReceivedMessage<mc.MqttMessage>> events) {
    final out = <mc.MqttReceivedMessage<mc.MqttMessage>>[];
    for (final e in events) {
      final pub = e.payload;
      if (pub is! mc.MqttPublishMessage) continue;
      final bytes = Uint8List.fromList(pub.payload.message.toList());
      if (e.topic == '${home.prefix}/hub') {
        hubOnline = utf8.decode(bytes, allowMalformed: true) == 'online';
        _hub.add(hubOnline!);
        continue;
      }
      if (!e.topic.startsWith('${home.prefix}/s/')) continue;
      final inner = RemoteSeal.unseal(home.key, bytes);
      final topic = inner?['topic'];
      final payload = inner?['payload'];
      if (topic is! String || payload is! String) continue;
      final data = typed.Uint8Buffer()..addAll(utf8.encode(payload));
      final message = mc.MqttPublishMessage().toTopic(topic).publishData(data);
      out.add(mc.MqttReceivedMessage<mc.MqttMessage>(topic, message));
    }
    if (out.isNotEmpty && !_updates.isClosed) _updates.add(out);
  }

  /// Local only: every retained state already arrived with `homes/<id>/s/#`.
  @override
  mc.Subscription? subscribe(String topic, mc.MqttQos qosLevel) {
    onSubscribed?.call(topic);
    return null;
  }

  @override
  void unsubscribe(String topic, {expectAcknowledge = false}) {}

  /// Sealed with its real topic and the time, to `homes/<id>/c`.
  @override
  int publishMessage(String topic, mc.MqttQos qualityOfService, typed.Uint8Buffer data, {bool retain = false}) {
    if (_transport.connectionStatus?.state != mc.MqttConnectionState.connected) return -1;
    final sealed = RemoteSeal.seal(home.key, {
      'topic': topic,
      'payload': utf8.decode(data.toList(), allowMalformed: true),
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    final buffer = typed.Uint8Buffer()..addAll(sealed);
    return _transport.publishMessage('${home.prefix}/c', mc.MqttQos.atLeastOnce, buffer);
  }

  @override
  void disconnect() {
    _sub?.cancel();
    _sub = null;
    _transport.disconnect();
  }
}
