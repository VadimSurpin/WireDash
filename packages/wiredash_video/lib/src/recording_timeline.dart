import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'hikvision_client.dart';
import 'recording_event.dart';
import 'recording_previews.dart';

/// Lazy timeline entries; only entries built by the viewport request previews.
class RecordingTimeline extends StatefulWidget {
  const RecordingTimeline({
    super.key,
    required this.records,
    required this.previews,
    required this.onSelected,
    this.previewEpoch = 0,
  });
  final List<Recording> records;
  final RecordingPreviews previews;
  final ValueChanged<Recording> onSelected;
  final int previewEpoch;

  @override
  State<RecordingTimeline> createState() => _RecordingTimelineState();
}

class _RecordingTimelineState extends State<RecordingTimeline> {
  final times = <String, DateTime>{};
  List<Recording> get records => widget.records;
  RecordingPreviews get previews => widget.previews;
  int get previewEpoch => widget.previewEpoch;
  ValueChanged<Recording> get onSelected => widget.onSelected;
  @override
  void didUpdateWidget(RecordingTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identities = records.map((r) => r.identity).toSet();
    times.removeWhere((key, _) => !identities.contains(key));
  }

  @override
  Widget build(BuildContext context) => SliverList.builder(
    itemCount: records.length,
    itemBuilder: (context, index) {
      final record = records[index];
      final local = record.start.toLocal();
      final before = index == 0 ? null : records[index - 1].start.toLocal();
      final newDay =
          before == null ||
          DateUtils.dateOnly(before) != DateUtils.dateOnly(local);
      final m = MaterialLocalizations.of(context);
      final colors = Theme.of(context).colorScheme;
      final events = record.events;
      final color = events.any((e) => e != RecordingEvent.scheduled)
          ? colors.tertiary
          : colors.primary;
      final elapsed = record.end.difference(record.start);
      final duration = elapsed.inHours > 0
          ? '${elapsed.inHours}h ${elapsed.inMinutes % 60}m'
          : elapsed.inMinutes > 0
          ? '${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s'
          : '${elapsed.inSeconds}s';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (newDay)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Text(
                m.formatFullDate(local),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 72,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      m.formatTimeOfDay(TimeOfDay.fromDateTime(local)),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
                SizedBox(
                  width: 18,
                  child: Column(
                    children: [
                      Container(
                        width: 2,
                        height: 12,
                        color: colors.outlineVariant,
                      ),
                      Container(
                        key: ValueKey('timeline-dot/${record.identity}'),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Container(
                          width: 2,
                          color: colors.outlineVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 12, 16),
                    child: Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          final time = times[record.identity];
                          onSelected(
                            time == null || time == record.start
                                ? record
                                : record.at(time),
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AspectRatio(
                              aspectRatio: 16 / 9,
                              child: RecordingPreview(
                                key: ValueKey(
                                  '${record.identity}/$previewEpoch',
                                ),
                                record: record,
                                previews: previews,
                                onReady: (preview) =>
                                    times[record.identity] = preview.time,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      for (final label
                                          in events.isEmpty
                                              ? ['Recording']
                                              : events.map((e) => e.label))
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: color.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            label,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelMedium,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.play_circle_outline,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '$duration · Until ${m.formatTimeOfDay(TimeOfDay.fromDateTime(record.end.toLocal()))}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class RecordingPreview extends StatefulWidget {
  const RecordingPreview({
    super.key,
    required this.record,
    required this.previews,
    this.onReady,
  });
  final ValueChanged<RecordingPreviewData>? onReady;
  final Recording record;
  final RecordingPreviews previews;
  @override
  State<RecordingPreview> createState() => _RecordingPreviewState();
}

class _RecordingPreviewState extends State<RecordingPreview> {
  RecordingPreviewTicket? ticket;
  RecordingPreviewData? preview;
  Uint8List? get image => preview?.bytes;
  bool loading = true;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    final request = ++generation;
    ticket?.release();
    loading = true;
    preview = null;
    ticket = widget.previews.request(widget.record);
    ticket!.preview.then((value) {
      if (mounted && generation == request) {
        setState(() {
          preview = value;
          loading = false;
        });
        if (value != null) widget.onReady?.call(value);
      }
    });
  }

  @override
  void didUpdateWidget(RecordingPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.previews != widget.previews ||
        oldWidget.record.identity != widget.record.identity) {
      load();
    }
  }

  @override
  void dispose() {
    generation++;
    ticket?.release();
    final bytes = image;
    if (bytes != null) {
      PaintingBinding.instance.imageCache.evict(
        ResizeImage.resizeIfNeeded(960, null, MemoryImage(bytes)),
      );
    }
    super.dispose();
  }

  String _clock(DateTime time) {
    final local = time.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final bytes = image;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: bytes != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  bytes,
                  cacheWidth: 960,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  semanticLabel: preview!.eventPhoto
                      ? 'Recorder event photo'
                      : 'Recorded video preview',
                  errorBuilder: (_, _, _) =>
                      const Center(child: Icon(Icons.broken_image_outlined)),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ColoredBox(
                    color: Colors.black87,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        preview!.eventPhoto
                            ? '${preview!.events.contains(RecordingEvent.human)
                                  ? 'Person capture'
                                  : preview!.events.contains(RecordingEvent.vehicle)
                                  ? 'Vehicle capture'
                                  : 'Recorder event photo'} · ${_clock(preview!.time)}'
                            : 'Video start · detection photo unavailable',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Center(
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton.icon(
                      onPressed: () => setState(load),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Load preview'),
                    ),
            ),
    );
  }
}
