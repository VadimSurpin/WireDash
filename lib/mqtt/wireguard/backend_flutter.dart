import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'backend.dart';

WireGuardBackend createBackend() => _AndroidBackend();

class _AndroidBackend implements WireGuardBackend {
  static const _channel = MethodChannel('zigdash/wireguard');

  @override
  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void _checkPlatform() {
    if (!supported) {
      throw UnsupportedError(
        'Embedded WireGuard is available on Android only.',
      );
    }
  }

  @override
  Future<void> validate(String config) async {
    _checkPlatform();
    await _channel.invokeMethod<void>('validate', {'config': config});
  }

  @override
  Future<WireGuardForwarder> open(
    String config,
    String host,
    int port,
    int timeoutMs,
  ) async {
    _checkPlatform();
    final result = await _channel.invokeMapMethod<String, Object?>('open', {
      'config': config,
      'host': host,
      'port': port,
      'timeoutMs': timeoutMs,
    });
    if (result == null) throw StateError('WireGuard did not create a route');
    return _Forwarder(
      result['id'] as String,
      result['port'] as int,
      base64Decode(result['token'] as String),
    );
  }
}

class _Forwarder implements WireGuardForwarder {
  _Forwarder(this.id, this.port, this.token);
  final String id;
  @override
  final int port;
  @override
  final List<int> token;
  bool _closed = false;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _AndroidBackend._channel.invokeMethod<void>('close', {'id': id});
  }
}
