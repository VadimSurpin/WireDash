import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wiredash_plugin_api/wiredash_plugin_api.dart';
import 'hikvision_client.dart';
import 'video_config.dart';
import 'video_session.dart';
import 'video_tile.dart';
import 'recording_previews.dart';
import 'recording_timeline.dart';
import 'recording_cache.dart';
import 'recording_photos.dart';
import 'recording_search.dart';
import 'recorder_clock.dart';

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
  RecorderClock recorderClock = const RecorderClock();
  bool clockLoaded = false, ready = false;
  late DateTime start, end;
  final filters = <RecordingFilter>{};
  RecordingSearch? query;
  final records = <Recording>[];
  late final RecordingPreviews previews;
  late final RecordingCache cache;
  bool rollingRange = true, cachedResults = false;
  DateTime? cachedAt;
  String get viewKey => widget.events ? 'events-view-v2' : 'recordings-view-v2';
  bool viewing = false, foreground = true;
  int previewEpoch = 0;
  String? error;
  bool loading = true, more = false;
  int generation = 0;
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
      photos: RecordingPhotos(
        host: widget.context.host,
        config: config,
        cache: cache,
        clock: () => recorderClock,
        rangeStart: () => start,
        rangeEnd: () => end,
      ),
    );
    end = DateTime.now();
    start = end.subtract(const Duration(hours: 24));
    unawaited(initialize());
  }

  void defaultFilters() {
    filters
      ..clear()
      ..addAll(
        widget.events
            ? RecordingFilter.values.where((f) => f.supported(capabilities))
            : <RecordingFilter>[],
      );
  }

  Future<void> initialize({bool force = false}) async {
    try {
      var restored = false;
      if (!force) {
        final view =
            await cache.readJson(viewKey) ??
            await cache.readJson(
              widget.events ? 'events-view' : 'recordings-view',
            );
        if (!mounted) return;
        try {
          if (view != null) {
            final from = DateTime.parse(view['start'] as String),
                to = DateTime.parse(view['end'] as String);
            if (!to.isAfter(from) ||
                to.difference(from) > const Duration(days: 7)) {
              throw const FormatException('Invalid cached range.');
            }
            start = from;
            end = to;
            rollingRange = view['rolling'] as bool;
            if (view['filters'] is List) {
              final saved = (view['filters'] as List)
                  .map((name) => RecordingFilter.values.byName(name as String))
                  .toSet();
              filters
                ..clear()
                ..addAll(saved);
              restored = true;
            }
          }
        } catch (_) {
          /* Ignore obsolete metadata. */
        }
        final savedClock = await cache.readJson('recorder-clock-v1');
        if (!mounted) return;
        if (savedClock != null) {
          recorderClock = RecorderClock.fromJson(savedClock);
          clockLoaded = true;
        }
        final caps = await cache.readJson('capabilities');
        if (!mounted) return;
        if (caps?['targets'] is List) {
          capabilities = RecorderCapabilities({
            RecordingTarget.all,
            for (final name in caps!['targets'] as List)
              ...RecordingTarget.values.where((t) => t.name == name),
          });
        }
        if (!restored) defaultFilters();
        final saved = await cache.readJson(
          RecordingSearch(start, end, filters).key,
        );
        if (!mounted) return;
        if (_applyCached(saved)) setState(() => loading = false);
      } else {
        previews.refresh();
        previewEpoch++;
        setState(() {
          ready = false;
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
        clock: recorderClock,
      );
      if (force || capabilities == null) {
        capabilities = await client!.capabilities();
        unawaited(
          cache.writeJson('capabilities', {
            'targets': capabilities!.targets.map((t) => t.name).toList(),
          }),
        );
      }
      if (!mounted) return;
      if (force || !clockLoaded) {
        recorderClock = await client!.discoverClock();
        clockLoaded = true;
        unawaited(cache.writeJson('recorder-clock-v1', recorderClock.toJson()));
      }
      if (!mounted) return;
      ready = true;
      if (!restored && !force) defaultFilters();
      final unsupported = filters
          .where((f) => !f.supported(capabilities))
          .toSet();
      if (unsupported.isNotEmpty) {
        filters.removeAll(unsupported);
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
      final restored = RecordingSearch(start, end, filters)
        ..restore(Map<String, dynamic>.from(saved['paging'] as Map));
      final time = DateTime.parse(saved['savedAt'] as String);
      records
        ..clear()
        ..addAll(entries);
      query = restored;
      more = restored.hasMore;
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
      'filters': filters.map((f) => f.name).toList(),
      'rolling': rollingRange,
    }),
  );

  Future<void> search({
    required bool reset,
    bool force = false,
    bool preserve = false,
  }) async {
    if (client == null || !ready || (loading && !reset)) return;
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
      if (reset && !preserve) {
        records.clear();
        cachedResults = false;
      }
      if (reset) {
        query = RecordingSearch(start, end, filters);
        more = false;
      }
    });
    _saveView();
    var current = query ?? RecordingSearch(start, end, filters);
    final key = current.key;
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
        current = RecordingSearch(start, end, filters);
        query = current;
      }
      final page = await current.next(
        client!,
        active: () => mounted && request == generation,
      );
      if (!mounted || request != generation) return;
      setState(() {
        final previous = !reset || (preserve && page.error != null)
            ? records.toList()
            : <Recording>[];
        records
          ..clear()
          ..addAll(RecordingSearch.merge([...previous, ...page.records]));
        more = current.hasMore;
        error = page.error;
        cachedResults = preserve && page.error != null;
      });
      if (records.length <= 2000 && page.error == null) {
        unawaited(
          cache.writeJson(key, {
            'records': records.map(RecordingCache.encodeRecord).toList(),
            'paging': current.save(),
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
              title: Text(
                '${widget.context.title} · ${stamp(record.playbackTime)}',
              ),
            ),
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, bounds) => SingleChildScrollView(
                  child: VideoPane(
                    context: widget.context,
                    sessionFactory: widget.sessionFactory,
                    playback: HikvisionClient.continuousPlayback(
                      config,
                      record.playbackTime,
                      source: record.playback,
                      clock: record.clock,
                    ),
                    recording: record,
                    resolveRecording: (time) async {
                      final page = await client!.search(
                        start: time,
                        end: time.add(const Duration(hours: 1)),
                      );
                      return page.records
                          .where(
                            (r) =>
                                !r.start.isAfter(time) && r.end.isAfter(time),
                          )
                          .firstOrNull;
                    },
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
                      FilterChip(
                        label: const Text('All recordings'),
                        selected: filters.isEmpty,
                        onSelected: !ready
                            ? null
                            : (_) {
                                setState(() => filters.clear());
                                unawaited(search(reset: true));
                              },
                      ),
                      for (final kind in RecordingFilter.values)
                        FilterChip(
                          label: Text(kind.label),
                          selected: filters.contains(kind),
                          onSelected: !ready || !kind.supported(capabilities)
                              ? null
                              : (selected) {
                                  setState(() {
                                    if (selected) {
                                      filters.add(kind);
                                    } else {
                                      filters.remove(kind);
                                    }
                                  });
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
                      'This recorder does not expose human/vehicle recording search. Motion and other generic events remain available.',
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
                      ? (more
                            ? 'No matches yet. Load more recordings to keep searching.'
                            : 'No recordings in this range.')
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
