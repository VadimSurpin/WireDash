import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ha_registry.dart';

/// Why reading Home Assistant failed, for the import screen.
enum HaReadError {
  /// Nothing answered at the address (wrong address, not on the network).
  unreachable,

  /// Something answered, but not Home Assistant's WebSocket API.
  notHomeAssistant,

  /// Home Assistant refused the token or the sign-in.
  badToken,

  /// Home Assistant answered but a read failed or timed out.
  failed,

  /// An `https://` address whose certificate the phone does not trust
  /// (self-signed). Not "nothing answered": the fix is different.
  certificate,
}

/// A read: the registries, or why not.
typedef HaReadResult = ({HaRegistry? registry, HaReadError? error});

/// Where Home Assistant is, from what the user typed or the scan saw:
/// `192.168.1.20`, `homeassistant.local:8123`, `http://…/lovelace/0`,
/// `https://xyz.ui.nabu.casa`. Without a scheme, http on 8123. Null when
/// nothing usable was typed.
Uri? haBaseUri(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  final hasScheme = text.contains('://');
  if (!hasScheme) text = 'http://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : (hasScheme ? null : 8123),
  );
}

/// Home Assistant's WebSocket API for [base]: `ws(s)://host:port/api/websocket`.
Uri haWebSocketUri(Uri base) => base.replace(
  scheme: base.scheme == 'https' ? 'wss' : 'ws',
  path: '/api/websocket',
);

/// Reads the four registries over one WebSocket session, then closes it
/// (docs/design/ha-import.md: one session, reads only). [token] is an access
/// token or a long-lived token; it is used for this session and not kept.
Future<HaReadResult> readHaRegistry(
  Uri base,
  String token, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  WebSocket socket;
  try {
    socket = await WebSocket.connect(
      haWebSocketUri(base).toString(),
    ).timeout(const Duration(seconds: 8));
  } on HandshakeException {
    return (registry: null, error: HaReadError.certificate);
  } on WebSocketException {
    // The host answered HTTP but refused the upgrade: not Home Assistant.
    return (registry: null, error: HaReadError.notHomeAssistant);
  } catch (_) {
    return (registry: null, error: HaReadError.unreachable);
  }
  final session = _Session(socket);
  try {
    return await session.read(token).timeout(timeout);
  } on TimeoutException {
    return (registry: null, error: HaReadError.failed);
  } finally {
    await session.close();
  }
}

class _Session {
  _Session(this._socket) {
    _sub = _socket.listen(
      (frame) {
        if (frame is! String) return;
        final Object? message;
        try {
          message = jsonDecode(frame);
        } catch (_) {
          return;
        }
        // Home Assistant may batch messages into one JSON array.
        for (final m in message is List ? message : [message]) {
          if (m is Map) _messages.add(Map<String, Object?>.from(m));
        }
      },
      onDone: () => _messages.close(),
      onError: (_) => _messages.close(),
      cancelOnError: true,
    );
  }

  final WebSocket _socket;
  late final StreamSubscription<Object?> _sub;
  final _messages = StreamController<Map<String, Object?>>();
  late final _queue = StreamIterator(_messages.stream);
  var _id = 0;

  Future<Map<String, Object?>?> _next() async =>
      await _queue.moveNext() ? _queue.current : null;

  Future<HaReadResult> read(String token) async {
    final hello = await _next();
    if (hello?['type'] != 'auth_required') {
      return (registry: null, error: HaReadError.notHomeAssistant);
    }
    _socket.add(jsonEncode({'type': 'auth', 'access_token': token}));
    final auth = await _next();
    if (auth?['type'] != 'auth_ok') {
      return (
        registry: null,
        error: auth?['type'] == 'auth_invalid'
            ? HaReadError.badToken
            : HaReadError.failed,
      );
    }
    final devices = await _call('config/device_registry/list');
    final areas = await _call('config/area_registry/list');
    if (devices is! List || areas is! List) {
      return (registry: null, error: HaReadError.failed);
    }
    // Floors and entity areas are extras: an older Home Assistant without
    // them still imports names and rooms.
    final floors = await _call('config/floor_registry/list');
    final entities = await _call('config/entity_registry/list_for_display');
    return (
      registry: HaRegistry.fromLists(
        devices: devices,
        areas: areas,
        floors: floors is List ? floors : null,
        entitiesForDisplay: entities is Map
            ? Map<String, Object?>.from(entities)
            : null,
      ),
      error: null,
    );
  }

  /// Sends one command and returns its result, or null when it failed.
  Future<Object?> _call(String type) async {
    final id = ++_id;
    _socket.add(jsonEncode({'id': id, 'type': type}));
    while (true) {
      final m = await _next();
      if (m == null) return null;
      if (m['id'] != id || m['type'] != 'result') continue;
      return m['success'] == true ? m['result'] : null;
    }
  }

  Future<void> close() async {
    await _sub.cancel();
    await _socket.close();
  }
}
