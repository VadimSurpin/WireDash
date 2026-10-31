import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:wiredash_plugin_api/wiredash_plugin_api.dart';
import 'hikvision_client.dart';
import 'video_config.dart';
import 'video_session.dart';
import 'video_tile.dart';
import 'recording_previews.dart';
import 'recording_timeline.dart';

class RecordingBrowser extends StatefulWidget {
  const RecordingBrowser({
    super.key,
    required this.context,
    required this.sessionFactory,
    this.events = false,
    this.previewFactory = NativeVideoSession.preview,
  });
  final PluginTileContext context;
  final VideoSessionFactory sessionFactory;
  final bool events;
  final VideoSessionFactory previewFactory;
  @override
  State<RecordingBrowser> createState() => _RecordingBrowserState();
}

class _RecordingBrowserState extends State<RecordingBrowser>
    with WidgetsBindingObserver {
  HikvisionClient? client;
  RecorderCapabilities? capabilities;
  late DateTime start, end;
  RecordingTarget target = RecordingTarget.all;
  final records = <Recording>[];
  late final RecordingPreviews previews;
  bool viewing = false, foreground = true;
  int previewEpoch = 0;
  String? error;
  bool loading = true, more = false;
  int position = 0, generation = 0;
  String searchId = const Uuid().v4();
  VideoConfig get config => VideoConfig.fromJson(widget.context.settings);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    previews = RecordingPreviews(
      host: widget.context.host,
      config: config,
      sessionFactory: widget.previewFactory,
    );
    end = DateTime.now();
    start = end.subtract(const Duration(hours: 24));
    unawaited(initialize());
  }

  Future<void> initialize() async {
    try {
      final credentials = VideoCredentials.decode(
        await widget.context.host.readSecret(config.credentialId),
      );
      if (!mounted) return;
      final network = config.useHomeNetwork
          ? widget.context.host.network
          : const DirectPluginNetwork();
      client = HikvisionClient(
        config: config,
        credentials: credentials,
        http: network.createHttpClient(),
      );
      capabilities = await client!.capabilities();
      if (widget.events) {
        target =
            capabilities!.targets
                .where((t) => t != RecordingTarget.all)
                .firstOrNull ??
            RecordingTarget.all;
      }
      if (mounted) await search(reset: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e is RecorderException
              ? e.message
              : 'Could not connect to the recording service.';
        });
      }
    }
  }

  Future<void> search({required bool reset}) async {
    if (client == null || (loading && !reset)) return;
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
      if (reset) {
        records.clear();
        position = 0;
        more = false;
        searchId = const Uuid().v4();
      }
    });
    try {
      final page = await client!.search(
        start: start,
        end: end,
        target: target,
        position: position,
        searchId: searchId,
      );
      if (!mounted || request != generation) return;
      final seen = records.map((r) => r.identity).toSet();
      final additions = page.records
          .where((r) => seen.add(r.identity))
          .toList();
      setState(() {
        records.addAll(additions);
        records.sort((a, b) => a.start.compareTo(b.start));
        more =
            page.hasMore &&
            page.nextPosition > position &&
            additions.isNotEmpty;
        position = page.nextPosition;
      });
    } catch (e) {
      if (mounted && request == generation) {
        setState(
          () => error = e is RecorderException
              ? e.message
              : 'Could not read recordings from this recorder firmware.',
        );
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  Future<void> chooseRange() async {
    final now = DateTime.now();
    final from = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (from == null || !mounted) return;
    final fromTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(start),
    );
    if (fromTime == null || !mounted) return;
    final to = await showDatePicker(
      context: context,
      initialDate: end,
      firstDate: from,
      lastDate: now,
    );
    if (to == null || !mounted) return;
    final toTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(end),
    );
    if (toTime == null || !mounted) return;
    setState(() {
      start = DateTime(
        from.year,
        from.month,
        from.day,
        fromTime.hour,
        fromTime.minute,
      );
      end = DateTime(to.year, to.month, to.day, toTime.hour, toTime.minute);
    });
    await search(reset: true);
  }

  String stamp(DateTime value) {
    final local = value.toLocal(), m = MaterialLocalizations.of(context);
    return '${m.formatShortDate(local)} ${m.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    previews.dispose();
    generation++;
    client?.close();
    scroll.dispose();
    super.dispose();
  }

  final scroll = ScrollController();
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    unawaited(previews.setPaused(!foreground || viewing));
    if (foreground && mounted) setState(() => previewEpoch++);
  }

  Future<void> select(Recording record) async {
    if (viewing) return;
    viewing = true;
    await previews.setPaused(true);
    if (!mounted) return;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text('${widget.context.title} · ${stamp(record.start)}'),
            ),
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, bounds) => SingleChildScrollView(
                  child: VideoPane(
                    context: widget.context,
                    sessionFactory: widget.sessionFactory,
                    playback: record.playback,
                    autoStart: true,
                    showRecordings: false,
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
    } finally {
      viewing = false;
      if (mounted) {
        await previews.setPaused(!foreground);
        if (mounted) setState(() => previewEpoch++);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        '${widget.context.title} · ${widget.events ? 'Events' : 'Recordings'}',
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh recordings',
          onPressed: loading
              ? null
              : () {
                  if (client == null || capabilities == null) {
                    client?.close();
                    setState(() => loading = true);
                    unawaited(initialize());
                  } else {
                    unawaited(search(reset: true));
                  }
                },
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: LayoutBuilder(
      builder: (context, constraints) => CustomScrollView(
        controller: scroll,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final kind in RecordingTarget.values)
                        ChoiceChip(
                          label: Text(switch (kind) {
                            RecordingTarget.all => 'All recordings',
                            RecordingTarget.human => 'People',
                            RecordingTarget.vehicle => 'Vehicles',
                          }),
                          selected: target == kind,
                          onSelected:
                              loading ||
                                  !(capabilities?.targets.contains(kind) ??
                                      kind == RecordingTarget.all)
                              ? null
                              : (_) {
                                  setState(() => target = kind);
                                  unawaited(search(reset: true));
                                },
                        ),
                    ],
                  ),
                ),
                if (capabilities != null && capabilities!.targets.length == 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'This recorder does not expose human/vehicle recording search. All recordings remain available.',
                    ),
                  ),
                TextButton.icon(
                  onPressed: loading ? null : chooseRange,
                  icon: const Icon(Icons.date_range),
                  label: Text('${stamp(start)} – ${stamp(end)}'),
                ),
                if (loading) const LinearProgressIndicator(),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(error!),
                  ),
              ],
            ),
          ),
          if (records.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  loading
                      ? 'Searching recordings…'
                      : error == null
                      ? 'No recordings in this range.'
                      : '',
                ),
              ),
            )
          else
            RecordingTimeline(
              records: records,
              previews: previews,
              previewEpoch: previewEpoch,
              onSelected: select,
            ),
          if (more)
            SliverToBoxAdapter(
              child: TextButton(
                onPressed: loading ? null : () => search(reset: false),
                child: const Text('Load more recordings'),
              ),
            ),
        ],
      ),
    ),
  );
}
