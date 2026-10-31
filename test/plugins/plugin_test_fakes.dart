import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wiredash_plugin_api/wiredash_plugin_api.dart';
import 'package:wiredash_video/wiredash_video.dart';

class MemoryHost implements PluginHost {
  final secrets = <String, String>{};
  Completer<String?>? delayedSecret;
  @override
  final FakeNetwork network = FakeNetwork();
  @override
  Future<String?> readSecret(String key) =>
      delayedSecret?.future ?? Future.value(secrets[key]);
  @override
  Future<void> writeSecret(String key, String value) async {
    secrets[key] = value;
  }

  @override
  Future<void> deleteSecret(String key) async {
    secrets.remove(key);
  }
}

class FakeNetwork extends DirectPluginNetwork {
  final leases = <FakeLease>[];
  @override
  Future<PluginStreamLease> openStream(Uri source) async {
    final lease = FakeLease(source);
    leases.add(lease);
    return lease;
  }
}

class FakeLease implements PluginStreamLease {
  FakeLease(this.uri);
  @override
  final Uri uri;
  bool closed = false;
  @override
  Future<void> close() async {
    closed = true;
  }
}

class FakeSession extends VideoSession {
  bool closed = false;
  Uri? opened;
  bool paused = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = Duration.zero;
  @override
  bool get buffering => false;
  @override
  bool get playing => opened != null && !closed && !paused;
  @override
  String? get error => null;
  @override
  Widget buildView() =>
      const ColoredBox(key: Key('fake-video'), color: Colors.black);
  @override
  Future<void> open(Uri uri, {required bool muted}) async {
    opened = uri;
  }

  @override
  Future<void> setMuted(bool muted) async {}
  @override
  Future<void> playOrPause() async {
    paused = !paused;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration position) async {
    this.position = position;
    notifyListeners();
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
