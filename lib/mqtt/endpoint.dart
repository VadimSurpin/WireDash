import 'broker_config.dart';

/// Which address a live MQTT connection is using.
enum MqttEndpoint { local, remote }

/// One ordered connect attempt: a host and the timeout to give it.
typedef MqttCandidate = ({MqttEndpoint kind, String host, int timeoutMs});

/// Short probe for the LAN host when a remote fallback exists — fail fast so we
/// can try the remote address quickly when away from home.
const int localProbeTimeoutMs = 3000;

/// Normal connect timeout (matches the previous single-host behavior).
const int standardConnectTimeoutMs = 5000;

/// A Home Assistant connect is a token refresh, TLS, the sign-in and a
/// probe subscription, often over the internet: more than an MQTT CONNECT.
const int homeAssistantConnectTimeoutMs = 12000;
const int wireGuardConnectTimeoutMs = 15000;

/// Local-first ordered candidates for [config]. With a remote host set, the LAN
/// host is tried first with a short timeout, then the remote host. Without one,
/// a single local candidate with the standard timeout (unchanged behavior).
List<MqttCandidate> endpointCandidates(BrokerConfig config) {
  final remote = config.remoteHost?.trim();
  final standard = config.viaHomeAssistant
      ? homeAssistantConnectTimeoutMs
      : config.viaWireGuard
      ? wireGuardConnectTimeoutMs
      : standardConnectTimeoutMs;
  if (remote == null || remote.isEmpty) {
    return [(kind: MqttEndpoint.local, host: config.host, timeoutMs: standard)];
  }
  return [
    (
      kind: MqttEndpoint.local,
      host: config.host,
      timeoutMs: config.viaWireGuard
          ? wireGuardConnectTimeoutMs
          : localProbeTimeoutMs,
    ),
    (kind: MqttEndpoint.remote, host: remote, timeoutMs: standard),
  ];
}
