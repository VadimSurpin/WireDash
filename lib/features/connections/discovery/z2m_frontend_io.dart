import 'dart:async';
import 'dart:io';

import 'z2m_frontend.dart';

/// Reads the `mqtt` settings from Zigbee2MQTT's web API at `ws://host:port/api`.
/// Zigbee2MQTT sends `bridge/info` among its first frames on connect; the
/// socket closes as soon as it arrives. Null when nothing answers in
/// [timeout], or the page wants its own token (it closes the socket then).
Future<Map<String, dynamic>?> fetchZ2mMqttConfig(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  WebSocket? socket;
  try {
    socket = await WebSocket.connect('ws://$host:$port/api').timeout(timeout);
    return await socket
        .where((frame) => frame is String)
        .map((frame) => z2mMqttConfigOf(frame as String))
        .firstWhere((mqtt) => mqtt != null, orElse: () => null)
        .timeout(timeout);
  } catch (_) {
    return null;
  } finally {
    unawaited(socket?.close());
  }
}
