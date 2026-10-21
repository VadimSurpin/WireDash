import 'backend.dart';

WireGuardBackend createBackend() => _UnsupportedBackend();

class _UnsupportedBackend implements WireGuardBackend {
  @override
  Future<void> validate(String config) async => throw UnsupportedError(
    'Embedded WireGuard is available on Android only.',
  );

  @override
  Future<WireGuardForwarder> open(
    String config,
    String host,
    int port,
    int timeoutMs,
  ) async => throw UnsupportedError(
    'Embedded WireGuard is available on Android only.',
  );
}
