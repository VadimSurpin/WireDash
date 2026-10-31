import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/plugins/plugin_network.dart';
import 'package:wiredash/mqtt/wireguard/backend.dart';

class _Backend implements WireGuardBackend {
  final routes = <_Forwarder>[];
  final destinations = <(String, int)>[];
  @override
  bool get supported => true;
  @override
  Future<void> validate(String config) async {}
  @override
  Future<WireGuardForwarder> open(
    String config,
    String host,
    int port,
    int timeoutMs,
  ) async {
    expect(config, 'private-config');
    destinations.add((host, port));
    final route = await _Forwarder.create();
    routes.add(route);
    return route;
  }
}

class _Forwarder implements WireGuardForwarder {
  _Forwarder(this.server);
  final ServerSocket server;
  final sockets = <Socket>[];
  final data = <int>[];
  bool closed = false;
  @override
  int get port => server.port;
  @override
  List<int> get token => List.filled(32, 7);
  static Future<_Forwarder> create() async {
    final result = _Forwarder(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    result.server.listen((socket) {
      result.sockets.add(socket);
      var authenticated = false;
      final pending = <int>[];
      socket.listen((bytes) {
        pending.addAll(bytes);
        if (!authenticated) {
          if (pending.length < 32) return;
          expect(pending.take(32).toList(), result.token);
          pending.removeRange(0, 32);
          authenticated = true;
        }
        result.data.addAll(pending);
        socket.add(pending);
        pending.clear();
      });
    });
    return result;
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await server.close();
    for (final socket in sockets) {
      socket.destroy();
    }
  }
}

void main() {
  test(
    'RTSP native player receives a loopback lease routed through the authenticated home tunnel',
    () async {
      final backend = _Backend();
      final network = HomePluginNetwork(
        () async => 'private-config',
        backend: backend,
      );
      final source = Uri.parse(
        'rtsp://viewer:secret@camera.internal:554/Streaming/Channels/102',
      );
      final lease = await network.openStream(source);
      expect(lease.uri.host, '127.0.0.1');
      expect(lease.uri.path, source.path);
      expect(lease.uri.userInfo, source.userInfo);
      final socket = await Socket.connect(lease.uri.host, lease.uri.port);
      final reply = socket.first;
      socket.add([1, 2, 3, 4]);
      await socket.flush();
      expect(await reply.timeout(const Duration(seconds: 3)), [1, 2, 3, 4]);
      expect(backend.destinations, [('camera.internal', 554)]);
      expect(backend.routes.single.data, [1, 2, 3, 4]);
      await lease.close();
      socket.destroy();
      for (final route in backend.routes) {
        await route.close();
      }
    },
  );
  test(
    'home WireGuard failures never fall back to a direct camera connection',
    () async {
      final network = HomePluginNetwork(
        () async => throw StateError('Tunnel unavailable'),
      );
      await expectLater(
        network.openStream(Uri.parse('rtsp://camera.internal:554/live')),
        throwsStateError,
      );
    },
  );
  test(
    'a home without embedded WireGuard retains the explicitly configured RTSP address',
    () async {
      final network = HomePluginNetwork(() async => null);
      final source = Uri.parse('rtsp://camera:8554/live');
      final lease = await network.openStream(source);
      expect(lease.uri, source);
      await lease.close();
    },
  );
}
