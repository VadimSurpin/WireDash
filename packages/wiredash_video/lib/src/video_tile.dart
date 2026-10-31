import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:wiredash_plugin_api/wiredash_plugin_api.dart';
import 'video_config.dart';
import 'video_session.dart';
import 'recording_browser.dart';
import 'hikvision_client.dart';

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
    this.selectedEvent,
    this.autoStart = false,
    this.showRecordings = true,
    this.videoHeight,
    this.fullscreen = false,
  });
  final PluginTileContext context;
  final VideoSessionFactory sessionFactory;
  final Uri? playback;
  final DateTime? selectedEvent;
  final double? videoHeight;
  final bool autoStart, showRecordings;
  final bool fullscreen;
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
  Uri? playback;
  double? scrubbing;
  DateTime? get playbackStart =>
      DateTime.tryParse(playback?.queryParameters['starttime'] ?? '');
  DateTime? get selectedEvent =>
      widget.selectedEvent ??
      DateTime.tryParse(widget.playback?.queryParameters['starttime'] ?? '');
  DateTime? get playbackTime =>
      playbackStart?.add(session?.position ?? Duration.zero);

  Future<void> jumpTo(DateTime time) async {
    final now = DateTime.now().toUtc();
    final earliest = DateTime.utc(2000);
    final at = time.isAfter(now)
        ? now
        : time.isBefore(earliest)
        ? earliest
        : time.toUtc();
    playback = HikvisionClient.continuousPlayback(config, at);
    scrubbing = null;
    await start();
  }

  Future<void> skip(Duration delta) async {
    final time = playbackTime;
    if (time != null) await jumpTo(time.add(delta));
  }

  String clock(DateTime time) {
    final local = time.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} ${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)}';
  }

  final transform = TransformationController();
  VideoConfig get config => VideoConfig.fromJson(widget.context.settings);
  @override
  void initState() {
    super.initState();
    muted = config.muted;
    playback = widget.playback;
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
      playback = widget.playback;
      scrubbing = null;
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
    transform.value = Matrix4.identity();
    final releasing = _release();
    if (mounted) setState(() {});
    await releasing;
  }

  Future<void> start() async {
    final request = ++generation;
    setState(() {
      opening = true;
      error = null;
    });
    PluginStreamLease? opened;
    VideoSession? created;
    try {
      await _release();
      if (!mounted || request != generation) return;
      final validation = config.validate();
      if (validation != null) throw StateError(validation);
      final credentials = VideoCredentials.decode(
        await widget.context.host.readSecret(config.credentialId),
      );
      if (!mounted || request != generation) return;
      final source = credentials.authenticate(playback ?? config.liveUri);
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
    transform.dispose();
    super.dispose();
  }

  Future<void> recordings({bool events = false}) async {
    await stop();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecordingBrowser(
          context: widget.context,
          sessionFactory: widget.sessionFactory,
          events: events,
        ),
      ),
    );
  }

  Future<void> expand() async {
    final time = playbackTime;
    final source = time == null
        ? playback
        : HikvisionClient.continuousPlayback(config, time);
    await stop();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(widget.context.title)),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, bounds) => SingleChildScrollView(
                child: VideoPane(
                  context: widget.context,
                  sessionFactory: widget.sessionFactory,
                  playback: source,
                  selectedEvent: selectedEvent,
                  showRecordings: widget.showRecordings,
                  autoStart: true,
                  fullscreen: true,
                  videoHeight: (bounds.maxHeight - 160).clamp(
                    bounds.maxHeight.clamp(0.0, 60.0),
                    bounds.maxHeight,
                  ),
                ),
              ),
            ),
          ),
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
          if (current != null)
            InteractiveViewer(
              key: const Key('video-viewport'),
              transformationController: transform,
              minScale: 1,
              maxScale: 8,
              panEnabled: true,
              scaleEnabled: true,
              child: SizedBox.expand(child: current.buildView()),
            ),
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
        if (playbackTime != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              clock(playbackTime!),
              key: const Key('recording-clock'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (playback != null &&
            current != null &&
            current.duration > Duration.zero)
          Slider(
            label: 'Recording position',
            value: (scrubbing ?? current.position.inMilliseconds.toDouble())
                .clamp(0, current.duration.inMilliseconds.toDouble()),
            max: current.duration.inMilliseconds.toDouble(),
            onChanged: opening
                ? null
                : (value) => setState(() => scrubbing = value),
            onChangeEnd: (value) {
              final from = playbackStart;
              if (from != null) {
                unawaited(
                  jumpTo(from.add(Duration(milliseconds: value.round()))),
                );
              } else {
                unawaited(current.seek(Duration(milliseconds: value.round())));
              }
            },
          ),
        Wrap(
          alignment: WrapAlignment.end,
          children: [
            if (playbackStart != null) ...[
              IconButton(
                tooltip: 'Rewind 1 minute',
                icon: const Icon(Icons.fast_rewind),
                onPressed: current == null || opening
                    ? null
                    : () => unawaited(skip(const Duration(minutes: -1))),
              ),
              IconButton(
                tooltip: 'Rewind 10 seconds',
                icon: const Icon(Icons.replay_10),
                onPressed: current == null || opening
                    ? null
                    : () => unawaited(skip(const Duration(seconds: -10))),
              ),
              IconButton(
                tooltip: 'Forward 10 seconds',
                icon: const Icon(Icons.forward_10),
                onPressed: current == null || opening
                    ? null
                    : () => unawaited(skip(const Duration(seconds: 10))),
              ),
              IconButton(
                tooltip: 'Forward 1 minute',
                icon: const Icon(Icons.fast_forward),
                onPressed: current == null || opening
                    ? null
                    : () => unawaited(skip(const Duration(minutes: 1))),
              ),
              IconButton(
                tooltip: 'Return to selected event',
                icon: const Icon(Icons.my_location),
                onPressed: current == null || opening
                    ? null
                    : () {
                        final time = selectedEvent;
                        if (time != null) unawaited(jumpTo(time));
                      },
              ),
            ],
            if (current != null)
              IconButton(
                tooltip: current.playing ? 'Pause video' : 'Resume video',
                onPressed: () => unawaited(current.playOrPause()),
                icon: Icon(current.playing ? Icons.pause : Icons.play_arrow),
              ),
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
            IconButton(
              tooltip: 'Reset zoom',
              onPressed: current == null
                  ? null
                  : () {
                      transform.value = Matrix4.identity();
                    },
              icon: const Icon(Icons.center_focus_strong),
            ),
            if (!widget.fullscreen)
              IconButton(
                tooltip: 'Fullscreen video',
                onPressed: expand,
                icon: const Icon(Icons.fullscreen),
              ),
            if (config.recordings && widget.showRecordings)
              IconButton(
                tooltip: 'Saved recordings',
                onPressed: () => recordings(),
                icon: const Icon(Icons.history),
              ),
            if (config.recordings && widget.showRecordings)
              IconButton(
                tooltip: 'Human and vehicle events',
                onPressed: () => recordings(events: true),
                icon: const Icon(Icons.manage_search),
              ),
          ],
        ),
      ],
    );
  }
}
