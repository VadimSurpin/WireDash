import 'package:flutter/material.dart';

import '../../../data/database/tables/connections.dart';
import '../discovery/address_check.dart';
import '../discovery/broker_probe.dart';
import 'protocol_dropdown.dart';

/// Shared broker-form field helpers, used by both the guided-connect wizard
/// and the manual connection form.

/// When the protocol changes and the port still holds the previous protocol's
/// default, swap it to the new protocol's default.
void applyProtocolPortDefault(
  TextEditingController port,
  MqttProtocol from,
  MqttProtocol to,
) {
  if (port.text == ProtocolDropdown.defaultPort(from).toString()) {
    port.text = ProtocolDropdown.defaultPort(to).toString();
  }
}

/// Fills the host/port/protocol fields from a [BrokerScanSheet] result.
void applyScanResult({
  required TextEditingController host,
  required TextEditingController port,
  required ValueChanged<MqttProtocol> onProtocol,
  required ProbeResult result,
}) {
  host.text = result.host;
  port.text = result.port.toString();
  onProtocol(result.port == 8883 ? MqttProtocol.tcpSsl : MqttProtocol.tcp);
}

/// Web pages, not brokers: Home Assistant (8123) always, and the usual web
/// ports when the host was a browser link.
const _webPorts = {80, 443, 8080, 8123};

/// Cleans up a browser link or `host:port` typed into the host field before
/// a TCP connection (2.7.1). `http://192.168.1.20:8123/lovelace` becomes host
/// `192.168.1.20` on the protocol's broker port: the hint says "the address
/// you open Home Assistant with", and that address is a link. A port typed
/// with the host moves to the port field unless it is a web page's port; a
/// web port left in the port field is swapped for the broker port. WebSocket
/// connections are left alone. Returns true when anything changed.
bool tidyBrokerAddress({
  required TextEditingController host,
  required TextEditingController port,
  required MqttProtocol protocol,
  required ValueChanged<MqttProtocol> onProtocol,
}) {
  if (protocol == MqttProtocol.ws || protocol == MqttProtocol.wss) {
    return false;
  }
  final text = host.text.trim();
  final link = RegExp(r'^https?://', caseSensitive: false).hasMatch(text);
  var newHost = text;
  int? linkPort;
  if (text.contains('://') ||
      text.contains('/') ||
      ':'.allMatches(text).length == 1) {
    final parsed = hostFromAddressInput(text);
    if (parsed != null) {
      newHost = parsed.host;
      linkPort = parsed.port;
    }
  }
  var newProtocol = protocol;
  var newPort = port.text.trim();
  final typedPort = int.tryParse(newPort);
  if (linkPort != null && !_webPorts.contains(linkPort)) {
    newPort = '$linkPort';
    if (linkPort == 8883) newProtocol = MqttProtocol.tcpSsl;
  } else if (typedPort == 8123 ||
      (link && typedPort != null && _webPorts.contains(typedPort)) ||
      linkPort != null) {
    newPort = '${ProtocolDropdown.defaultPort(newProtocol)}';
  }
  final changed =
      newHost != host.text || newPort != port.text || newProtocol != protocol;
  host.text = newHost;
  port.text = newPort;
  if (newProtocol != protocol) onProtocol(newProtocol);
  return changed;
}
