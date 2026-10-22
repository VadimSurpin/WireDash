import 'package:mqtt_client/mqtt_client.dart' as mc;
import 'package:mqtt_client/mqtt_server_client.dart';

import '../data/database/tables/connections.dart';
import 'broker_config.dart';
import 'client_factory.dart';
import 'ha_address.dart';
import 'endpoint.dart';
import 'ha_mqtt_client.dart';
import 'relay_mqtt_client.dart';

mc.MqttClient buildPlatformClient(
  BrokerConfig config,
  String clientId, {
  String? host,
}) {
  final target = host ?? config.host;
  final relay = config.relay;
  if (target == relayCandidateHost && relay != null) {
    return RelayMqttClient(relay, clientId);
  }
  if (config.viaHomeAssistant) {
    final base = haBaseUri(target);
    if (base == null) {
      throw UnsupportedError('Not a Home Assistant address: $target');
    }
    return HaMqttClient(haWebSocketUri(base), clientId);
  }
  final ws = isWebSocketProtocol(config.protocol);
  final client = MqttServerClient.withPort(
    ws ? webSocketServer(config.protocol, target) : target,
    clientId,
    config.port,
  );
  client.secure = isSecureProtocol(config.protocol);
  if (ws) {
    client.useWebSocket = true;
    client.websocketProtocols = ['mqtt'];
  }
  return client;
}

/// mqtt_client's WebSocket connection only accepts a ws:// or wss:// URL and
/// rejected a bare host with "incorrect scheme", so WS/WSS connections on
/// Android never connected. A scheme the user already typed is kept.
String webSocketServer(MqttProtocol protocol, String host) {
  if (host.startsWith('ws://') || host.startsWith('wss://')) return host;
  final scheme = protocol == MqttProtocol.wss ? 'wss' : 'ws';
  return '$scheme://$host';
}
