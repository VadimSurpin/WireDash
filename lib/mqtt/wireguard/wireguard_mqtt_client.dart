import 'dart:async';
import 'dart:io';

import 'package:event_bus/event_bus.dart';
import 'package:mqtt_client/mqtt_client.dart' as mc;
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:typed_data/typed_data.dart' as typed;

import '../broker_config.dart';
import '../client_factory.dart';
import '../client_factory_io.dart' show webSocketServer;
import 'backend.dart';

/// Reuses mqtt_client's MQTT framing, subscriptions and QoS state machines.
/// Only socket creation changes: all broker traffic goes through a private
/// userspace WG stack. TLS still verifies the original broker's hostname.
class WireGuardMqttClient extends mc.MqttClient {
  WireGuardMqttClient(
    this.config,
    String host,
    String clientId, {
    WireGuardBackend? backend,
    this.securityContext,
  }) : backend = backend ?? createWireGuardBackend(),
       super.withPort(host, clientId, config.port);

  final BrokerConfig config;
  final WireGuardBackend backend;
  final SecurityContext? securityContext;
  _Connection? _wire;

  @override
  Future<mc.MqttClientConnectionStatus?> connect([
    String? username,
    String? password,
  ]) async {
    mc.MqttClientEnvironment.isWebClient = false;
    instantiationCorrect = true;
    final bus = clientEventBus = mc.MqttEventBus.fromEventBus(EventBus());
    bus.on<mc.DisconnectOnNoPingResponse>().listen(disconnectOnNoPingResponse);
    bus.on<mc.DisconnectOnNoMessageSent>().listen(disconnectOnNoMessageSent);
    final wire = _wire = _Connection(
      bus,
      config,
      server,
      backend,
      connectTimeoutPeriod,
      securityContext,
    );
    connectionHandler = _Handler(bus, wire, connectTimeoutPeriod);
    try {
      return await super.connect(username, password);
    } catch (_) {
      wire.closeClient();
      rethrow;
    }
  }

  @override
  void disconnect() {
    super.disconnect();
    _wire?.closeClient();
  }
}

class _Handler extends mc.MqttConnectionHandlerBase {
  _Handler(mc.MqttEventBus bus, _Connection wire, int timeoutMs)
    : super(bus, maxConnectionAttempts: 1) {
    connection = wire;
    connectTimer = mc.MqttCancellableAsyncSleep(timeoutMs);
    initialiseListeners();
  }

  @override
  Future<mc.MqttClientConnectionStatus> internalConnect(
    String hostname,
    int port,
    mc.MqttConnectMessage? message,
  ) async {
    connectionStatus.state = mc.MqttConnectionState.connecting;
    // mqtt_client marks this callback internal, but custom connection
    // handlers need it to report EOF to the client's reconnect owner.
    // ignore: invalid_use_of_internal_member
    connection.onDisconnected = onDisconnected;
    await connection.connect(hostname, port);
    sendMessage(message);
    await connectTimer.sleep();
    initialConnectionComplete = true;
    if (connectionStatus.state != mc.MqttConnectionState.connected) {
      throw mc.NoConnectionException(
        'WireGuard MQTT connection was not acknowledged',
      );
    }
    return connectionStatus;
  }
}

class _Connection extends MqttServerConnection<Object> {
  _Connection(
    mc.MqttEventBus bus,
    this.config,
    this.host,
    this.backend,
    int timeoutMs,
    this.securityContext,
  ) : timeout = Duration(milliseconds: timeoutMs),
      super(bus, [], Duration(milliseconds: timeoutMs));

  final BrokerConfig config;
  final String host;
  final WireGuardBackend backend;
  final Duration timeout;
  final SecurityContext? securityContext;
  WireGuardForwarder? _forwarder;
  HttpClient? _http;
  bool _closed = false;

  Future<Socket> _socket(String target, int port) async {
    final forwarder = await backend.open(
      config.wireGuardConfig!,
      target,
      port,
      timeout.inMilliseconds,
    );
    if (_closed) {
      await forwarder.close();
      throw const SocketException('WireGuard connection was cancelled');
    }
    _forwarder = forwarder;
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      forwarder.port,
      timeout: timeout,
    );
    if (_closed) {
      socket.destroy();
      throw const SocketException('WireGuard connection was cancelled');
    }
    // The native bridge consumes the token; the broker never sees it.
    socket.add(forwarder.token);
    await socket.flush();
    return socket;
  }

  @override
  Future<mc.MqttClientConnectionStatus?> connect(
    String server,
    int port,
  ) async {
    try {
      if (isWebSocketProtocol(config.protocol)) {
        final uri = Uri.parse(webSocketServer(config.protocol, host))
            .replace(port: port);
        final http = _http = HttpClient(context: securityContext)
          ..findProxy = (_) => 'DIRECT';
        // HttpClient wraps this socket in TLS for WSS, using uri.host.
        http.connectionFactory = (uri, proxyHost, proxyPort) async =>
            ConnectionTask.fromSocket(_socket(uri.host, uri.port), closeClient);
        final ws = await WebSocket.connect(
          uri.toString(),
          protocols: ['mqtt'],
          customClient: http,
        ).timeout(timeout);
        if (_closed) {
          await ws.close();
          throw const SocketException('WireGuard connection was cancelled');
        }
        client = ws;
      } else {
        final socket = await _socket(host, port);
        client = socket;
        if (isSecureProtocol(config.protocol)) {
          final secure = await SecureSocket.secure(
            socket,
            host: host,
            context: securityContext,
          ).timeout(timeout);
          if (_closed) {
            secure.destroy();
            throw const SocketException('WireGuard connection was cancelled');
          }
          client = secure;
        }
      }
      readWrapper = mc.ReadWrapper();
      messageStream = mc.MqttByteBuffer(typed.Uint8Buffer());
      listeners.add(onListen());
      return null;
    } catch (_) {
      closeClient();
      rethrow;
    }
  }

  @override
  Future<mc.MqttClientConnectionStatus?> connectAuto(String server, int port) =>
      connect(server, port);

  @override
  StreamSubscription onListen() {
    final stream = client;
    if (stream is Socket)
      return stream.listen(onData, onDone: onDone, onError: onError);
    return (stream as WebSocket).listen(
      onData,
      onDone: onDone,
      onError: onError,
    );
  }

  @override
  void send(mc.MqttByteBuffer message) {
    final bytes = message.read(message.length).toList();
    final socket = client;
    if (socket is Socket) socket.add(bytes);
    if (socket is WebSocket) socket.add(bytes);
  }

  @override
  void stopListening() {
    for (final listener in listeners) {
      unawaited(listener.cancel());
    }
    listeners.clear();
  }

  @override
  void closeClient() {
    _closed = true;
    final socket = client;
    client = null;
    if (socket is Socket) socket.destroy();
    if (socket is WebSocket) unawaited(socket.close());
    _http?.close(force: true);
    final forwarder = _forwarder;
    _forwarder = null;
    if (forwarder != null)
      unawaited(forwarder.close().catchError((Object _) {}));
  }

  @override
  void disposeClient() => closeClient();
}
