import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart' as mc;
import 'package:zigdash/data/database/tables/connections.dart';
import 'package:zigdash/mqtt/broker_config.dart';
import 'package:zigdash/mqtt/mqtt_manager.dart';
import 'package:zigdash/mqtt/wireguard/backend.dart';
import 'package:zigdash/mqtt/wireguard/wireguard_mqtt_client.dart';

// Transport-only test double: validates the native route's token and forwards
// to a local broker. The app must use this socket for an unresolvable private
// broker name, including TLS SNI and certificate verification.
class _Backend implements WireGuardBackend {
  @override
  bool get supported => true;
  _Backend(this.brokerPort);
  final int brokerPort;
  final routes = <_Route>[];
  final targets = <String>[];
  Completer<WireGuardForwarder>? pending;

  @override
  Future<void> validate(String config) async {}

  @override
  Future<WireGuardForwarder> open(
    String config,
    String host,
    int port,
    int timeoutMs,
  ) async {
    targets.add(host);
    if (pending != null) return pending!.future;
    final route = await _Route.start(brokerPort);
    routes.add(route);
    return route;
  }

  Future<void> close() async {
    for (final route in routes) {
      await route.close();
    }
  }
}

class _Route implements WireGuardForwarder {
  _Route(this.server);
  final ServerSocket server;
  final sockets = <Socket>[];
  bool closed = false;
  @override
  int get port => server.port;
  @override
  List<int> get token => List<int>.generate(32, (i) => i);

  static Future<_Route> start(int brokerPort) async {
    final route = _Route(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    route.server.listen((local) {
      route.sockets.add(local);
      Socket? remote;
      var authenticated = false;
      final buffered = <int>[];
      local.listen(
        (bytes) async {
          if (!authenticated) {
            buffered.addAll(bytes);
            if (buffered.length < 32) return;
            expect(buffered.take(32), route.token);
            buffered.removeRange(0, 32);
            authenticated = true;
            final connected = await Socket.connect(
              InternetAddress.loopbackIPv4,
              brokerPort,
            );
            if (route.closed) {
              connected.destroy();
              return;
            }
            route.sockets.add(connected);
            remote = connected;
            connected.add(buffered);
            buffered.clear();
            connected.listen(
              local.add,
              onDone: local.destroy,
              onError: (_) => local.destroy(),
            );
          } else if (remote == null) {
            buffered.addAll(bytes);
          } else {
            remote!.add(bytes);
          }
        },
        onDone: () => remote?.destroy(),
        onError: (_) => remote?.destroy(),
      );
    });
    return route;
  }

  @override
  Future<void> close() async {
    closed = true;
    for (final socket in sockets) {
      socket.destroy();
    }
    await server.close();
  }
}

SecurityContext _serverContext() => SecurityContext()
  ..useCertificateChain('test/mqtt/fixtures/wireguard_server.pem')
  ..usePrivateKey('test/mqtt/fixtures/wireguard_server.key');

SecurityContext _clientContext() =>
    SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates('test/mqtt/fixtures/wireguard_ca.pem');

// Enough of a broker to exercise the real client's CONNECT and SUBSCRIBE,
// with a retained reading returned after SUBACK.
void _serveMqtt(Socket socket) {
  final buffer = <int>[];
  socket.listen(
    (bytes) {
      buffer.addAll(bytes);
      while (buffer.length >= 2) {
        var length = 0, multiplier = 1, offset = 1;
        int digit;
        do {
          if (offset >= buffer.length) return;
          digit = buffer[offset++];
          length += (digit & 127) * multiplier;
          multiplier *= 128;
        } while (digit & 128 != 0);
        if (buffer.length < offset + length) return;
        final type = buffer.first >> 4;
        final body = buffer.sublist(offset, offset + length);
        buffer.removeRange(0, offset + length);
        if (type == 1) socket.add([0x20, 2, 0, 0]);
        if (type == 8) {
          socket.add([0x90, 3, body[0], body[1], 1]);
          const topic = 'sensors/temperature';
          final payload = [
            0,
            topic.length,
            ...utf8.encode(topic),
            ...utf8.encode('21.5'),
          ];
          socket.add([0x31, payload.length, ...payload]);
        }
      }
    },
    onError: (_) {},
    onDone: socket.destroy,
  );
}

void main() {
  setUp(MqttManager.useProtocolRules);

  for (final secure in [false, true]) {
    test(
      'MQTT ${secure ? "TLS" : "TCP"} uses the route and preserves the private hostname',
      () async {
        final ServerSocket broker = secure
            ? await SecureServerSocket.bind(
                InternetAddress.loopbackIPv4,
                0,
                _serverContext(),
              )
            : await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final sockets = <Socket>[];
        broker.listen((socket) {
          sockets.add(socket);
          _serveMqtt(socket);
        }, onError: (_) {});
        addTearDown(() async {
          for (final socket in sockets) {
            socket.destroy();
          }
          await broker.close();
        });
        final backend = _Backend(broker.port);
        addTearDown(backend.close);
        final config = BrokerConfig(
          id: 'wg',
          host: 'broker.internal.invalid',
          port: 1883,
          protocol: secure ? MqttProtocol.tcpSsl : MqttProtocol.tcp,
          transport: ConnectionTransport.wireGuard,
          wireGuardConfig: 'test config',
        );
        final manager = MqttManager(
          config: config,
          password: '',
          clientFactory: (cfg, id, {host}) => WireGuardMqttClient(
            cfg,
            host!,
            id,
            backend: backend,
            securityContext: secure ? _clientContext() : null,
          ),
        );
        addTearDown(manager.dispose);
        await manager.connect();
        final value = manager.subscribe('sensors/temperature').first;
        expect(
          (await value.timeout(const Duration(seconds: 3))).payload,
          '21.5',
        );
        expect(backend.targets, ['broker.internal.invalid']);
        manager.disconnect();
        await Future<void>.delayed(Duration.zero);
        expect(backend.routes.single.closed, isTrue);
      },
    );
  }

  test('TLS rejects a certificate for a different broker name', () async {
    final broker = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      _serverContext(),
    );
    broker.listen((socket) => socket.destroy(), onError: (_) {});
    addTearDown(broker.close);
    final backend = _Backend(broker.port);
    addTearDown(backend.close);
    const config = BrokerConfig(
      id: 'wg',
      host: 'wrong.internal.invalid',
      port: 8883,
      protocol: MqttProtocol.tcpSsl,
      transport: ConnectionTransport.wireGuard,
      wireGuardConfig: 'test',
    );
    final client = WireGuardMqttClient(
      config,
      config.host,
      'test',
      backend: backend,
      securityContext: _clientContext(),
    );
    addTearDown(client.disconnect);
    await expectLater(client.connect(), throwsA(isA<HandshakeException>()));
  });

  test(
    'disconnect while the native route is opening closes the late route',
    () async {
      final backend = _Backend(1)..pending = Completer<WireGuardForwarder>();
      const config = BrokerConfig(
        id: 'wg',
        host: 'broker.internal.invalid',
        port: 1883,
        protocol: MqttProtocol.tcp,
        transport: ConnectionTransport.wireGuard,
        wireGuardConfig: 'test',
      );
      final client = WireGuardMqttClient(
        config,
        config.host,
        'test',
        backend: backend,
      );
      final connecting = client.connect();
      final failed = expectLater(connecting, throwsA(isA<SocketException>()));
      client.disconnect();
      final route = await _Route.start(1);
      backend.pending!.complete(route);
      await failed;
      expect(route.closed, isTrue);
    },
  );
}
