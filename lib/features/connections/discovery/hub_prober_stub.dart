import 'hub_probe.dart';

HubProber createHubProber() => const _NoHubProber();

class _NoHubProber implements HubProber {
  const _NoHubProber();
  @override
  Future<HubKind?> probe(String host, int port) async => null;
}
