import 'broker_probe.dart';
import 'hub_probe.dart';

/// The address check (2.6.2): on an empty scan the user types the address
/// they use for their hub (an IP, a name, or the link from their browser)
/// and setup checks that one machine for an MQTT broker and a hub page.
/// The address itself stays on the phone; only the outcome is counted.
enum AddressOutcome {
  /// An MQTT broker answered on 1883 or 8883: setup verifies it.
  broker,

  /// A hub's web page answered but no broker did: the empty result names it.
  hub,

  /// The address resolved and is local, but nothing answered.
  nothing,

  /// The name could not be looked up (`.local` names often can't on Android).
  notResolved,

  /// The address is not on a home network (a remote link like Nabu Casa).
  notLocal,

  /// Nothing usable was typed.
  invalid,
}

/// What checking one address found.
class AddressCheckResult {
  const AddressCheckResult(this.outcome, {this.broker, this.hub});

  const AddressCheckResult.nothing() : this(AddressOutcome.nothing);

  final AddressOutcome outcome;
  final ProbeResult? broker;
  final HubFound? hub;
}

/// Checks [host] (a name or an IP) for a broker and a hub page; [webPort]
/// is the port the user typed with it, if any, else the usual hub ports are
/// tried. Never throws.
typedef AddressChecker =
    Future<AddressCheckResult> Function(String host, int? webPort);

/// What the user typed, reduced to a host and the port they typed with it.
///
/// Accepts `192.168.1.20`, `homeassistant.local`, `homeassistant.local:8123`,
/// `http://192.168.1.20:8123/lovelace` and so on. Null when nothing usable
/// is there. The host comes back lowercased without scheme, path or
/// credentials.
({String host, int? port})? hostFromAddressInput(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'http://$text';
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (host.isEmpty) return null;
  // Uri keeps the IPv6 brackets off the host; nothing else to strip.
  return (host: host, port: uri.hasPort ? uri.port : null);
}

/// True when [host] is a dotted IPv4 literal.
bool isIpv4Literal(String host) {
  final parts = host.split('.');
  if (parts.length != 4) return false;
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255 || p.isEmpty) return false;
  }
  return true;
}
