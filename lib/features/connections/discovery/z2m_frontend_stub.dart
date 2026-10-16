/// No sockets on web: Zigbee2MQTT's web API is never asked.
Future<Map<String, dynamic>?> fetchZ2mMqttConfig(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 5),
}) async => null;
