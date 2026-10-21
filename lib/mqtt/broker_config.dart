import '../data/database/tables/connections.dart';

/// Plain-Dart broker config consumed by [MqttManager]. Decoupled from Drift
/// so the manager (and the smoke harness in bin/) does not transitively pull
/// in dart:ui via drift_flutter.
class BrokerConfig {
  const BrokerConfig({
    required this.id,
    required this.host,
    required this.port,
    required this.protocol,
    this.username,
    this.keepAliveSeconds = 60,
    this.remoteHost,
    this.transport = ConnectionTransport.mqtt,
    this.wireGuardConfig,
  });

  final String id;
  final String host;
  final int port;
  final MqttProtocol protocol;
  final String? username;
  final int keepAliveSeconds;

  /// Optional fallback address (e.g. a Tailscale MagicDNS name) tried after
  /// [host] is unreachable. Reuses [port], [protocol], and credentials.
  final String? remoteHost;

  /// How to reach the home. For [ConnectionTransport.homeAssistant], [host]
  /// (and [remoteHost]) are Home Assistant addresses and the password slot
  /// carries the sign-in (see `HaMqttClient`).
  final ConnectionTransport transport;

  /// Loaded from encrypted storage, never the connection row or a backup.
  /// A WireGuard transport with a missing config fails closed.
  final String? wireGuardConfig;

  bool get viaWireGuard => transport == ConnectionTransport.wireGuard;

  bool get viaHomeAssistant => transport == ConnectionTransport.homeAssistant;
}
