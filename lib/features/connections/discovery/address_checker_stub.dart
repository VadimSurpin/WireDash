import 'address_check.dart';
import 'broker_probe.dart';
import 'hub_probe.dart';

/// Web fallback: the browser cannot probe the local network.
AddressChecker createAddressChecker({
  HostProber? prober,
  HubProber? hubProber,
  List<int> brokerPorts = const [1883, 8883],
}) =>
    (host, webPort) async => const AddressCheckResult.nothing();
