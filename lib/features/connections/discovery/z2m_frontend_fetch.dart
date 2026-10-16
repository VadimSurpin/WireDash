// Platform-conditional reader of Zigbee2MQTT's web API: a WebSocket on
// `dart:io` platforms, a null-returning stub on web.
export 'z2m_frontend_stub.dart' if (dart.library.io) 'z2m_frontend_io.dart';
