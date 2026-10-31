import 'dart:io';
import 'package:flutter/material.dart';

/// A bundled extension. Plugins own their settings and widgets; WireDash owns
/// dashboard persistence, credentials and the home's private network route.
abstract interface class WireDashPanelPlugin {
  String get id;
  String title(BuildContext context);
  String description(BuildContext context);
  IconData get icon;
  Widget buildTile(PluginTileContext context);
  PluginEditorController createEditor(
    Map<String, dynamic> settings,
    PluginHost host,
  );
}

abstract class PluginEditorController extends ChangeNotifier {
  Map<String, dynamic> get settings;
  Widget buildFields(BuildContext context);

  /// Called only after the enclosing form validates. Never serialize passwords.
  Future<void> save();
}

class PluginTileContext {
  const PluginTileContext({
    required this.id,
    required this.title,
    required this.settings,
    required this.host,
  });
  final String id, title;
  final Map<String, dynamic> settings;
  final PluginHost host;
}

abstract interface class PluginHost {
  Future<String?> readSecret(String key);
  Future<void> writeSecret(String key, String value);
  Future<void> deleteSecret(String key);
  PluginNetwork get network;
}

abstract interface class PluginNetwork {
  HttpClient createHttpClient();

  /// A lease may replace the network address with a private TCP forwarder.
  Future<PluginStreamLease> openStream(Uri source);
}

abstract interface class PluginStreamLease {
  Uri get uri;
  Future<void> close();
}

class DirectPluginNetwork implements PluginNetwork {
  const DirectPluginNetwork();
  @override
  HttpClient createHttpClient() => HttpClient();
  @override
  Future<PluginStreamLease> openStream(Uri source) async =>
      _DirectLease(source);
}

class _DirectLease implements PluginStreamLease {
  _DirectLease(this.uri);
  @override
  final Uri uri;
  @override
  Future<void> close() async {}
}
