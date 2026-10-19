import 'no_network.dart';

export 'no_network.dart';

/// Web fallback: no LAN IP introspection in the browser.
Future<String?> wifiIpv4() async => null;

Future<({String name, String ip})?> homeIpv4() async => null;

Future<bool> vpnActive() async => false;

Future<NoNetwork> noNetworkReason() async => NoNetwork.unknown;
