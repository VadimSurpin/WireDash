import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:wiredash_plugin_api/wiredash_plugin_api.dart';
import 'video_config.dart';
import 'video_session.dart';
import 'recording_browser.dart';

class VideoTile extends StatelessWidget {
  const VideoTile({
    super.key,
    required this.context,
    required this.sessionFactory,
  });
  final PluginTileContext context;
  final VideoSessionFactory sessionFactory;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: VideoPane(context: this.context, sessionFactory: sessionFactory),
  );
}

class VideoPane extends StatefulWidget {
  const VideoPane({
    super.key,
    required this.context,
    required this.sessionFactory,
    this.playback,
    this.autoStart = false,
    this.showRecordings = true,
    this.videoHeight,
  });
  final PluginTileContext context;
  final VideoSessionFactory sessionFactory;
  final Uri? playback;
  final double? videoHeight;
  final bool autoStart, showRecordings;
  @override
  State<VideoPane> createState() => _VideoPaneState();
}

class _VideoPaneState extends State<VideoPane> with WidgetsBindingObserver {
  VideoSession? session;
  PluginStreamLease? lease;
  bool opening = false;
  String? error;
  int generation = 0;
  late bool muted;
  VideoConfig get config => VideoConfig.fromJson(widget.context.settings);
  @override
  void initState() {
    super.initState();
    muted = config.muted;
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(start());
      });
    }
  }

  @override
  void didUpdateWidget(VideoPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.context.id != widget.context.id ||
        oldWidget.context.host != widget.context.host ||
        !mapEquals(oldWidget.context.settings, widget.context.settings) ||
        oldWidget.playback != widget.playback) {
      unawaited(stop());
    }
  }

  void updated() {
    if (mounted) setState(() {});
  }

  Future<void> _release() async {
    final oldSession = session, oldLease = lease;
    session = null;
    lease = null;
    oldSession?.removeListener(updated);
    try {
      // Interrupt any stalled RTSP socket before awaiting native disposal.
      await oldLease?.close();
    } finally {
      await oldSession?.close();
    }
  }

  Future<void> stop() async {
    generation++;
    opening = false;
    final releasing = _release();
    if (mounted) setState(() {});
    await releasing;
  }

  Future<void> start() async {
    final request = ++generation;
    await _release();
    if (!mounted || request != generation) return;
    setState(() {
      opening = true;
      error = null;
    });
    PluginStreamLease? opened;
    VideoSession? created;
    try {
      final validation = config.validate();
      if (validation != null) throw StateError(validation);
      final credentials = VideoCredentials.decode(
        await widget.context.host.readSecret(config.credentialId),
      );
      if (!mounted || request != generation) return;
      final source = credentials.authenticate(
        widget.playback ?? config.liveUri,
      );
      final network = config.useHomeNetwork
          ? widget.context.host.network
          : const DirectPluginNetwork();
      opened = await network.openStream(source);
      if (!mounted || request != generation) {
        await opened.close();
        return;
      }
      created = widget.sessionFactory();
      session = created;
      lease = opened;
      created.addListener(updated);
      setState(() {});
      await created.open(opened.uri, muted: muted);
    } catch (_) {
      if (created == null) await opened?.close();
      if (mounted && request == generation) {
        await _release();
        if (mounted && request == generation) {
          setState(
            () => error =
                'Video could not start. Check the stream, login and network route.',
          );
        }
      }
    } finally {
      if (mounted && request == generation) setState(() => opening = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    generation++;
    unawaited(_release());
    super.dispose();
  }

  Future<void> recordings() async {
    await stop();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecordingBrowser(
          context: widget.context,
          sessionFactory: widget.sessionFactory,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = session;
    final message = error ?? current?.error;
    final video = ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (current != null) current.buildView(),
          if (current == null && !opening && message == null)
            Center(
              child: IconButton.filled(
                iconSize: 42,
                tooltip: 'Play live video',
                onPressed: start,
                icon: const Icon(Icons.play_arrow),
              ),
            ),
          if (message == null && (opening || current?.buffering == true))
            const Center(child: CircularProgressIndicator()),
          if (message != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Text(
            widget.context.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (widget.videoHeight == null)
          AspectRatio(aspectRatio: 16 / 9, child: video)
        else
          SizedBox(height: widget.videoHeight, child: video),
        Wrap(
          alignment: WrapAlignment.end,
          children: [
            IconButton(
              tooltip: current == null && !opening
                  ? 'Play video'
                  : 'Stop video',
              onPressed: current == null && !opening ? start : stop,
              icon: Icon(
                current == null && !opening ? Icons.play_arrow : Icons.stop,
              ),
            ),
            IconButton(
              tooltip: muted ? 'Unmute' : 'Mute',
              onPressed: () {
                setState(() => muted = !muted);
                unawaited(current?.setMuted(muted));
              },
              icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
            ),
            if (config.recordings && widget.showRecordings)
              IconButton(
                tooltip: 'Saved recordings',
                onPressed: recordings,
                icon: const Icon(Icons.history),
              ),
          ],
        ),
      ],
    );
  }
}
