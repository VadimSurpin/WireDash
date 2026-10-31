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
import 'recording_cache.dart';

class RecordingBrowser extends StatefulWidget {
  const RecordingBrowser({
    super.key,
    required this.context,
    required this.sessionFactory,
    this.events = false,
    this.previewFactory = NativeVideoSession.preview,
    this.cache,
  });
  final PluginTileContext context;
  final VideoSessionFactory sessionFactory;
  final bool events;
  final VideoSessionFactory previewFactory;
  final RecordingCache? cache;
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
  late final RecordingCache cache;
  bool rollingRange = true, cachedResults = false;
  DateTime? cachedAt;
  String get viewKey => widget.events ? 'events-view' : 'recordings-view';
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
    cache = widget.cache ?? RecordingCache.forPanel(widget.context);
    previews = RecordingPreviews(
      host: widget.context.host,
      config: config,
      sessionFactory: widget.previewFactory,
      cache: cache,
    );
    end = DateTime.now();
    start = end.subtract(const Duration(hours: 24));
    unawaited(initialize());
  }

  Future<void> initialize({bool force = false}) async {
    try {
      var restored = false;
      if (!force) {
        final view = await cache.readJson(viewKey);
        if (!mounted) return;
        try {
          if (view != null) {
            final from = DateTime.parse(view['start'] as String);
            final to = DateTime.parse(view['end'] as String);
            final filter = RecordingTarget.values.byName(
              view['target'] as String,
            );
            final rolling = view['rolling'] as bool;
            if (!to.isAfter(from) ||
                to.difference(from) > const Duration(days: 7)) {
              throw const FormatException('Invalid cached range.');
            }
            start = from;
            end = to;
            target = filter;
            rollingRange = rolling;
            restored = true;
          }
        } catch (_) {
          /* Ignore an obsolete cache entry. */
        }
        final caps = await cache.readJson('capabilities');
        if (!mounted) return;
        if (caps != null && caps['targets'] is List) {
          capabilities = RecorderCapabilities({
            RecordingTarget.all,
            for (final value in caps['targets'] as List? ?? [])
              ...RecordingTarget.values.where((t) => t.name == value),
          });
        }
        if (widget.events && !restored && capabilities != null) {
          target =
              capabilities!.targets
                  .where((t) => t != RecordingTarget.all)
                  .firstOrNull ??
              RecordingTarget.all;
        }
        final saved = await cache.readJson(
          cache.timelineKey(start, end, target),
        );
        if (!mounted) return;
        if (_applyCached(saved)) setState(() => loading = false);
      } else {
        setState(() {
          loading = true;
          error = null;
        });
      }
      final credentials = VideoCredentials.decode(
        await widget.context.host.readSecret(config.credentialId),
      );
      if (!mounted) return;
      final network = config.useHomeNetwork
          ? widget.context.host.network
          : const DirectPluginNetwork();
      client?.close();
      client = HikvisionClient(
        config: config,
        credentials: credentials,
        http: network.createHttpClient(),
      );
      if (force || capabilities == null) {
        capabilities = await client!.capabilities();
        unawaited(
          cache.writeJson('capabilities', {
            'targets': capabilities!.targets.map((t) => t.name).toList(),
          }),
        );
      }
      if (widget.events && !restored && !force) {
        target =
            capabilities!.targets
                .where((t) => t != RecordingTarget.all)
                .firstOrNull ??
            RecordingTarget.all;
      }
      if (!mounted) return;
      if (!capabilities!.targets.contains(target)) {
        target = widget.events
            ? capabilities!.targets
                      .where((t) => t != RecordingTarget.all)
                      .firstOrNull ??
                  RecordingTarget.all
            : RecordingTarget.all;
        records.clear();
        cachedResults = false;
      }
      if (rollingRange &&
          (force ||
              DateTime.now().difference(end) >= const Duration(minutes: 1))) {
        end = DateTime.now();
        start = end.subtract(const Duration(hours: 24));
      }
      await search(
        reset: true,
        force: force,
        preserve: cachedResults || records.isNotEmpty,
      );
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

  bool _applyCached(Map<String, dynamic>? saved) {
    if (saved == null) return false;
    try {
      final entries = (saved['records'] as List)
          .map(
            (r) => RecordingCache.decodeRecord(
              Map<String, dynamic>.from(r as Map),
              config,
            ),
          )
          .toList();
      final next = saved['position'] as int, id = saved['searchId'] as String;
      final hasMore = saved['more'] as bool;
      final time = DateTime.parse(saved['savedAt'] as String);
      records
        ..clear()
        ..addAll(entries);
      position = next;
      searchId = id;
      more = hasMore;
      cachedAt = time;
      cachedResults = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  void _saveView() => unawaited(
    cache.writeJson(viewKey, {
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
      'target': target.name,
      'rolling': rollingRange,
    }),
  );

  Future<void> search({
    required bool reset,
    bool force = false,
    bool preserve = false,
  }) async {
    if (client == null || (loading && !reset)) return;
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
      if (reset && !preserve) {
        records.clear();
        cachedResults = false;
      }
      if (reset) {
        position = 0;
        more = false;
        searchId = const Uuid().v4();
      }
    });
    _saveView();
    final key = cache.timelineKey(start, end, target);
    try {
      if (reset && !force) {
        final saved = await cache.readJson(key);
        if (!mounted || request != generation) return;
        if (_applyCached(saved)) {
          setState(() {});
          final historical =
              !rollingRange &&
              end.isBefore(DateTime.now().subtract(const Duration(hours: 1)));
          final age = DateTime.now().difference(cachedAt!);
          if (!age.isNegative &&
              age <
                  (historical
                      ? const Duration(days: 1)
                      : const Duration(minutes: 1))) {
            return;
          }
        }
        position = 0;
        more = false;
        searchId = const Uuid().v4();
      }
      final page = await client!.search(
        start: start,
        end: end,
        target: target,
        position: position,
        searchId: searchId,
      );
      if (!mounted || request != generation) return;
      final seen = records.map((r) => r.identity).toSet();
      if (reset) seen.clear();
      final additions = page.records
          .where((r) => seen.add(r.identity))
          .toList();
      setState(() {
        if (reset) records.clear();
        records.addAll(additions);
        records.sort((a, b) => a.start.compareTo(b.start));
        more =
            page.hasMore &&
            page.nextPosition > position &&
            additions.isNotEmpty;
        position = page.nextPosition;
        cachedResults = false;
      });
      if (records.length <= 2000) {
        unawaited(
          cache.writeJson(key, {
            'records': records.map(RecordingCache.encodeRecord).toList(),
            'position': position,
            'more': more,
            'searchId': searchId,
            'savedAt': DateTime.now().toUtc().toIso8601String(),
          }),
        );
      }
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
      rollingRange = false;
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
                    playback: HikvisionClient.continuousPlayback(
                      config,
                      record.start,
                    ),
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
                  unawaited(initialize(force: true));
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
                              client == null ||
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
                if (cachedResults)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      loading ? 'Cached results · updating…' : 'Cached results',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
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
