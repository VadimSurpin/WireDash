import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:wiredash_plugin_api/wiredash_plugin_api.dart';
import 'video_config.dart';
import 'video_session.dart';
import 'video_tile.dart';

class VideoPanelPlugin implements WireDashPanelPlugin {
  const VideoPanelPlugin({this.sessionFactory = NativeVideoSession.new});
  static const pluginId = 'wiredash.video';
  final VideoSessionFactory sessionFactory;
  @override
  String get id => pluginId;
  @override
  String title(BuildContext context) => _ru(context) ? 'Видео' : 'Video';
  @override
  String description(BuildContext context) => _ru(context)
      ? 'RTSP и записи Hikvision с поиском людей и автомобилей'
      : 'RTSP live video and Hikvision human/vehicle recordings';
  @override
  IconData get icon => Icons.videocam_outlined;
  @override
  Widget buildTile(PluginTileContext context) =>
      VideoTile(context: context, sessionFactory: sessionFactory);
  @override
  PluginEditorController createEditor(
    Map<String, dynamic> settings,
    PluginHost host,
  ) => VideoEditorController(settings, host);
  static bool _ru(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ru';
}

class VideoEditorController extends PluginEditorController {
  VideoEditorController(Map<String, dynamic> initial, this.host)
    : config = VideoConfig.fromJson(initial) {
    stream.text = config.streamUrl;
    recorder.text = config.recorderUrl;
    channel.text = '${config.channel}';
    credentialId = config.credentialId.isEmpty
        ? const Uuid().v4()
        : config.credentialId;
    substream = config.substream;
    recordings = config.recordings;
    muted = config.muted;
    useHomeNetwork = config.useHomeNetwork;
    loadingCredentials = _loadCredentials();
  }
  final PluginHost host;
  final VideoConfig config;
  final stream = TextEditingController(),
      recorder = TextEditingController(),
      channel = TextEditingController();
  final username = TextEditingController(), password = TextEditingController();
  late String credentialId;
  late final Future<void> loadingCredentials;
  late bool substream, recordings, muted, useHomeNetwork;
  bool credentialsEdited = false, disposed = false;
  String? credentialError;
  Future<void> _loadCredentials() async {
    try {
      final value = VideoCredentials.decode(
        await host.readSecret(credentialId),
      );
      if (!disposed && !credentialsEdited) {
        username.text = value.username;
        password.text = value.password;
      }
    } catch (_) {
      credentialError = 'Could not read the saved video login. Enter it again.';
    }
    if (!disposed) notifyListeners();
  }

  VideoConfig get current => VideoConfig(
    streamUrl: stream.text.trim(),
    recorderUrl: recorder.text.trim(),
    channel: int.tryParse(channel.text) ?? 0,
    substream: substream,
    recordings: recordings,
    muted: muted,
    useHomeNetwork: useHomeNetwork,
    credentialId: credentialId,
  );
  @override
  Map<String, dynamic> get settings => current.toJson();
  @override
  Future<void> save() async {
    await loadingCredentials;
    final uri = Uri.tryParse(stream.text.trim());
    var login = VideoCredentials(username.text, password.text);
    if (uri != null && uri.userInfo.isNotEmpty && !credentialsEdited) {
      final colon = uri.userInfo.indexOf(':');
      login = VideoCredentials(
        Uri.decodeComponent(
          colon < 0 ? uri.userInfo : uri.userInfo.substring(0, colon),
        ),
        colon < 0 ? '' : Uri.decodeComponent(uri.userInfo.substring(colon + 1)),
      );
    }
    if (config.credentialId.isNotEmpty &&
        (credentialsEdited || uri?.userInfo.isNotEmpty == true)) {
      // Duplicated panels may share a login reference. Editing one login must
      // not silently replace the other panel's credentials.
      credentialId = const Uuid().v4();
    }
    if (login.username.isEmpty && login.password.isEmpty) {
      await host.deleteSecret(credentialId);
    } else {
      await host.writeSecret(credentialId, login.encode());
    }
    if (uri != null && uri.userInfo.isNotEmpty) {
      stream.text = uri.replace(userInfo: '').toString();
    }
  }

  void changed(VoidCallback change) {
    change();
    notifyListeners();
  }

  @override
  Widget buildFields(BuildContext context) => AnimatedBuilder(
    animation: this,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('video-stream-url'),
          controller: stream,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'RTSP stream URL',
            hintText: 'rtsp://192.168.1.64:554/Streaming/Channels/102',
            helperText:
                'Leave blank to generate a Hikvision URL from the recorder and channel.',
          ),
          validator: (_) => current.validate(),
          onChanged: (_) => notifyListeners(),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('video-recorder-url'),
          controller: recorder,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'Hikvision recorder address',
            hintText: 'http://192.168.1.64',
          ),
          validator: (_) => current.validate(),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: channel,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Camera channel',
            helperText:
                'Use the DVR channel number (analog and IP channels may differ).',
          ),
          validator: (_) =>
              (int.tryParse(channel.text) ?? 0) < 1 ||
                  (int.tryParse(channel.text) ?? 0) > 1024
              ? 'Enter a channel from 1 to 1024.'
              : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Use substream for live video'),
          subtitle: const Text(
            'A smaller stream saves bandwidth. Saved recordings use the main stream.',
          ),
          value: substream,
          onChanged: stream.text.trim().isEmpty
              ? (v) => changed(() => substream = v)
              : null,
        ),
        TextFormField(
          controller: username,
          autofillHints: const [AutofillHints.username],
          decoration: const InputDecoration(labelText: 'Video username'),
          onChanged: (_) => credentialsEdited = true,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: password,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Video password',
            helperText:
                'Stored securely on this device; excluded from dashboard exports.',
          ),
          onChanged: (_) => credentialsEdited = true,
        ),
        if (credentialError != null) Text(credentialError!),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable Hikvision recordings'),
          subtitle: const Text(
            'Browse saved video, with human/vehicle filters when supported by the recorder.',
          ),
          value: recordings,
          onChanged: (v) => changed(() => recordings = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Mute initially'),
          value: muted,
          onChanged: (v) => changed(() => muted = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Use this home’s network route'),
          subtitle: const Text(
            'Includes embedded WireGuard when configured for the home.',
          ),
          value: useHomeNetwork,
          onChanged: (v) => changed(() => useHomeNetwork = v),
        ),
      ],
    ),
  );
  @override
  void dispose() {
    disposed = true;
    for (final c in [stream, recorder, channel, username, password]) {
      c.dispose();
    }
    super.dispose();
  }
}
