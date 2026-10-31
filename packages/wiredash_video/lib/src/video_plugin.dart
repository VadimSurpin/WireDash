import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:wiredash_plugin_api/wiredash_plugin_api.dart';
import 'video_config.dart';
import 'video_session.dart';
import 'video_tile.dart';
import 'video_strings.dart';

class VideoPanelPlugin implements WireDashPanelPlugin {
  const VideoPanelPlugin({this.sessionFactory = NativeVideoSession.new});
  static const pluginId = 'wiredash.video';
  final VideoSessionFactory sessionFactory;
  @override
  String get id => pluginId;
  @override
  String title(BuildContext context) => context.videoStrings.message('video');
  @override
  String description(BuildContext context) =>
      context.videoStrings.message('description');
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
    playbackTime = config.playbackTime;
    playbackOffset.text = config.playbackUtcOffset;
    loadingCredentials = _loadCredentials();
  }
  final PluginHost host;
  final VideoConfig config;
  final stream = TextEditingController(),
      recorder = TextEditingController(),
      channel = TextEditingController(),
      playbackOffset = TextEditingController();
  final username = TextEditingController(), password = TextEditingController();
  late String credentialId;
  late final Future<void> loadingCredentials;
  late bool substream, recordings, muted, useHomeNetwork;
  late RecorderPlaybackTime playbackTime;
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
    playbackTime: playbackTime,
    playbackUtcOffset: playbackOffset.text.trim(),
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
          decoration: InputDecoration(
            labelText: context.videoStrings.message('streamUrl'),
            hintText: 'rtsp://192.168.1.64:554/Streaming/Channels/102',
            helperText: context.videoStrings.message('streamHelp'),
          ),
          validator: (_) => context.videoStrings.nullable(current.validate()),
          onChanged: (_) => notifyListeners(),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('video-recorder-url'),
          controller: recorder,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: context.videoStrings.message('recorderAddress'),
            hintText: 'http://192.168.1.64',
          ),
          validator: (_) => context.videoStrings.nullable(current.validate()),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: channel,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: context.videoStrings.message('cameraChannel'),
            helperText: context.videoStrings.message('channelHelp'),
          ),
          validator: (_) =>
              (int.tryParse(channel.text) ?? 0) < 1 ||
                  (int.tryParse(channel.text) ?? 0) > 1024
              ? context.videoStrings.message('enterChannel')
              : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.videoStrings.message('substream')),
          subtitle: Text(context.videoStrings.message('substreamHelp')),
          value: substream,
          onChanged: stream.text.trim().isEmpty
              ? (v) => changed(() => substream = v)
              : null,
        ),
        TextFormField(
          controller: username,
          autofillHints: const [AutofillHints.username],
          decoration: InputDecoration(
            labelText: context.videoStrings.message('username'),
          ),
          onChanged: (_) => credentialsEdited = true,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: password,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: context.videoStrings.message('password'),
            helperText: context.videoStrings.message('passwordHelp'),
          ),
          onChanged: (_) => credentialsEdited = true,
        ),
        if (credentialError != null)
          Text(context.videoStrings.text(credentialError!)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.videoStrings.message('enableRecordings')),
          subtitle: Text(context.videoStrings.message('recordingsHelp')),
          value: recordings,
          onChanged: (v) => changed(() => recordings = v),
        ),
        if (recordings) ...[
          DropdownButtonFormField<RecorderPlaybackTime>(
            initialValue: playbackTime,
            decoration: InputDecoration(
              labelText: context.videoStrings.message('playbackTime'),
            ),
            items: [
              DropdownMenuItem(
                value: RecorderPlaybackTime.automatic,
                child: Text(context.videoStrings.message('automatic')),
              ),
              DropdownMenuItem(
                value: RecorderPlaybackTime.local,
                child: Text(context.videoStrings.message('recorderLocal')),
              ),
              DropdownMenuItem(
                value: RecorderPlaybackTime.utc,
                child: Text(context.videoStrings.message('utc')),
              ),
            ],
            onChanged: (value) => changed(
              () => playbackTime = value ?? RecorderPlaybackTime.automatic,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: playbackOffset,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: context.videoStrings.message('utcOffset'),
              hintText: '+03:00',
              helperText: context.videoStrings.message('utcOffsetHelp'),
            ),
            validator: (_) => context.videoStrings.nullable(current.validate()),
          ),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.videoStrings.message('muteInitially')),
          value: muted,
          onChanged: (v) => changed(() => muted = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.videoStrings.message('homeRoute')),
          subtitle: Text(context.videoStrings.message('homeRouteHelp')),
          value: useHomeNetwork,
          onChanged: (v) => changed(() => useHomeNetwork = v),
        ),
      ],
    ),
  );
  @override
  void dispose() {
    disposed = true;
    for (final c in [
      stream,
      recorder,
      channel,
      playbackOffset,
      username,
      password,
    ]) {
      c.dispose();
    }
    super.dispose();
  }
}
