import 'broker_probe.dart';

/// Web fallback: raw TCP scanning isn't possible in the browser, so the prober
/// finds nothing (the scan UI is hidden on web anyway).
HostProber createHostProber() => _NoopProber();

HostProber createPatientHostProber() => _NoopProber();

class _NoopProber extends HostProber {
  @override
  Future<ProbeResult?> probe(String host, int port) async => null;
}
