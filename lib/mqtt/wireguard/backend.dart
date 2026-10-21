import 'backend_stub.dart'
    if (dart.library.ui) 'backend_flutter.dart'
    as platform;

/// A private, authenticated loopback route to one target in the WG network.
abstract interface class WireGuardForwarder {
  int get port;
  List<int> get token;
  Future<void> close();
}

abstract interface class WireGuardBackend {
  bool get supported;
  Future<void> validate(String config);
  Future<WireGuardForwarder> open(
    String config,
    String host,
    int port,
    int timeoutMs,
  );
}

WireGuardBackend createWireGuardBackend() => platform.createBackend();
