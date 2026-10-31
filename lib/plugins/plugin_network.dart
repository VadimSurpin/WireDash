import 'dart:async';
import 'dart:io';
import 'package:wiredash_plugin_api/wiredash_plugin_api.dart';
import '../mqtt/wireguard/backend.dart';

/// Share the home's userspace tunnel with HTTP and native RTSP players. RTSP
/// uses interleaved TCP, so media and control travel on the same routed socket.
class HomePluginNetwork implements PluginNetwork {
  HomePluginNetwork(this.configuration, {WireGuardBackend? backend})
    : backend = backend ?? createWireGuardBackend();
  final Future<String?> Function() configuration;
  final WireGuardBackend backend;
  Future<Socket> _connect(String host, int port, {String? tunnelConfig}) async {
    final config = tunnelConfig ?? await configuration();
    if (config == null) {
      return Socket.connect(host, port, timeout: const Duration(seconds: 15));
    }
    final route = await backend.open(config, host, port, 15000);
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        route.port,
        timeout: const Duration(seconds: 15),
      );
      socket.add(route.token);
      await socket.flush();
      unawaited(
        socket.done.then(
          (_) => route.close(),
          onError: (Object _) => route.close(),
        ),
      );
      return socket;
    } catch (_) {
      await route.close();
      rethrow;
    }
  }

  @override
  HttpClient createHttpClient() {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    client.connectionFactory = (uri, proxyHost, proxyPort) {
      Socket? connecting;
      var cancelled = false;
      final future = () async {
        var socket = await _connect(uri.host, uri.port);
        connecting = socket;
        if (cancelled) {
          socket.destroy();
          throw const SocketException('Connection cancelled');
        }
        if (uri.scheme == 'https') {
          socket = await SecureSocket.secure(socket, host: uri.host);
          connecting = socket;
          if (cancelled) {
            socket.destroy();
            throw const SocketException('Connection cancelled');
          }
        }
        return socket;
      }();
      return Future.value(
        ConnectionTask.fromSocket(future, () {
          cancelled = true;
          connecting?.destroy();
        }),
      );
    };
    return client;
  }

  @override
  Future<PluginStreamLease> openStream(Uri source) async {
    final config = await configuration();
    if (config == null) {
      return const DirectPluginNetwork().openStream(source);
    }
    if (source.scheme != 'rtsp') {
      throw UnsupportedError('Use RTSP over TCP for embedded WireGuard.');
    }
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final lease = _ForwardedStream(
      source.replace(host: '127.0.0.1', port: server.port),
      server,
    );
    server.listen((local) async {
      lease.sockets.add(local);
      try {
        final remote = await _connect(
          source.host,
          source.port,
          tunnelConfig: config,
        );
        if (lease.closed) {
          remote.destroy();
          local.destroy();
          return;
        }
        lease.sockets.add(remote);
        unawaited(
          remote
              .addStream(local)
              .whenComplete(() {
                remote.destroy();
                local.destroy();
              })
              .catchError((Object _) {}),
        );
        unawaited(
          local
              .addStream(remote)
              .whenComplete(() {
                remote.destroy();
                local.destroy();
              })
              .catchError((Object _) {}),
        );
      } catch (_) {
        local.destroy();
      }
    });
    return lease;
  }
}

class _ForwardedStream implements PluginStreamLease {
  _ForwardedStream(this.uri, this.server);
  @override
  final Uri uri;
  final ServerSocket server;
  final sockets = <Socket>[];
  bool closed = false;
  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await server.close();
    for (final socket in sockets) {
      socket.destroy();
    }
    sockets.clear();
  }
}
