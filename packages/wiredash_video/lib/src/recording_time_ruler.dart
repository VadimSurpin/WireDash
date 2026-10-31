import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'hikvision_client.dart';
import 'recording_event.dart';
import 'video_strings.dart';

String recordingTimestamp(DateTime time, {bool date = false}) {
  final local = time.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  final clock = '${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)}';
  return date
      ? '${local.year}-${pad(local.month)}-${pad(local.day)} $clock'
      : clock;
}

/// Absolute wall-clock ruler. The selected instant is independent of native
/// stream duration (Hikvision RTSP often reports zero or an arbitrary duration).
class RecordingTimeRuler extends StatefulWidget {
  const RecordingTimeRuler({
    super.key,
    required this.start,
    required this.end,
    required this.position,
    required this.records,
    required this.onSeek,
    this.enabled = true,
  });
  final DateTime start, end, position;
  final List<Recording> records;
  final ValueChanged<DateTime> onSeek;
  final bool enabled;
  @override
  State<RecordingTimeRuler> createState() => _RecordingTimeRulerState();
}

class _RecordingTimeRulerState extends State<RecordingTimeRuler> {
  late DateTime center;
  double span = const Duration(minutes: 30).inMilliseconds.toDouble();
  double initialSpan = 0;
  DateTime? initialCenter;
  Offset? initialFocal;
  bool touching = false, zoomGesture = false;
  double get maximum => math.max(
    1000,
    widget.end.difference(widget.start).inMilliseconds.toDouble(),
  );
  double get minimum => math.min(maximum, 60000);
  DateTime clamp(DateTime time) => time.isBefore(widget.start)
      ? widget.start
      : time.isAfter(widget.end)
      ? widget.end
      : time;
  @override
  void initState() {
    super.initState();
    center = widget.position;
    span = span.clamp(minimum, maximum);
  }

  @override
  void didUpdateWidget(RecordingTimeRuler oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!touching) center = widget.position;
    span = span.clamp(minimum, maximum);
  }

  DateTime at(double x, double width) => clamp(
    center.add(Duration(milliseconds: ((x / width - 0.5) * span).round())),
  );
  void zoom(double factor) =>
      setState(() => span = (span * factor).clamp(minimum, maximum));
  void seek(DateTime time) {
    setState(() => center = clamp(time));
    widget.onSeek(center);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.videoStrings;
    final events = widget.records.expand((r) => r.events).toSet();
    final kinds = RecordingEvent.values.where(events.contains).toList();
    events.remove(RecordingEvent.scheduled);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                recordingTimestamp(center, date: true),
                key: const Key('ruler-selected-time'),
                textDirection: TextDirection.ltr,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Text(
              strings.duration(Duration(milliseconds: span.round())),
              key: const Key('ruler-scale'),
            ),
            IconButton(
              tooltip: strings.message('timelineZoomOut'),
              onPressed: span >= maximum ? null : () => zoom(2),
              icon: const Icon(Icons.remove),
            ),
            IconButton(
              tooltip: strings.message('timelineZoomIn'),
              onPressed: span <= minimum ? null : () => zoom(0.5),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, bounds) {
            final width = bounds.maxWidth;
            return Semantics(
              label: strings.message('recordingPosition'),
              value: recordingTimestamp(center, date: true),
              increasedValue: recordingTimestamp(
                clamp(center.add(Duration(milliseconds: (span / 10).round()))),
                date: true,
              ),
              decreasedValue: recordingTimestamp(
                clamp(
                  center.subtract(Duration(milliseconds: (span / 10).round())),
                ),
                date: true,
              ),
              onIncrease: widget.enabled
                  ? () => seek(
                      center.add(Duration(milliseconds: (span / 10).round())),
                    )
                  : null,
              onDecrease: widget.enabled
                  ? () => seek(
                      center.subtract(
                        Duration(milliseconds: (span / 10).round()),
                      ),
                    )
                  : null,
              child: GestureDetector(
                key: const Key('recording-time-ruler'),
                behavior: HitTestBehavior.opaque,
                onTapUp: widget.enabled
                    ? (details) => seek(at(details.localPosition.dx, width))
                    : null,
                onScaleStart: widget.enabled
                    ? (details) {
                        touching = true;
                        zoomGesture = false;
                        initialCenter = center;
                        initialSpan = span;
                        initialFocal = details.localFocalPoint;
                      }
                    : null,
                onScaleUpdate: widget.enabled
                    ? (details) => setState(() {
                        span = (initialSpan / details.scale).clamp(
                          minimum,
                          maximum,
                        );
                        if (details.pointerCount > 1) zoomGesture = true;
                        final shift =
                            details.localFocalPoint.dx - initialFocal!.dx;
                        center = zoomGesture
                            ? initialCenter!
                            : clamp(
                                initialCenter!.subtract(
                                  Duration(
                                    milliseconds: (shift / width * span)
                                        .round(),
                                  ),
                                ),
                              );
                      })
                    : null,
                onScaleEnd: widget.enabled
                    ? (_) {
                        touching = false;
                        if (!zoomGesture &&
                            center
                                    .difference(initialCenter!)
                                    .inMilliseconds
                                    .abs() >=
                                1000) {
                          widget.onSeek(center);
                        }
                        setState(() {});
                      }
                    : null,
                child: CustomPaint(
                  size: Size(
                    width,
                    math.max(96, 46 + kinds.length * 12).toDouble(),
                  ),
                  painter: _RulerPainter(
                    center: center,
                    span: span,
                    start: widget.start,
                    end: widget.end,
                    records: widget.records,
                    kinds: kinds,
                    colors: Theme.of(context).colorScheme,
                    style: Theme.of(context).textTheme.labelSmall!,
                    strings: strings,
                  ),
                ),
              ),
            );
          },
        ),
        if (events.isNotEmpty)
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final event in RecordingEvent.values.where(events.contains))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.square,
                      size: 10,
                      color: eventColor(event, Theme.of(context).colorScheme),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      strings.text(event.label),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
            ],
          ),
      ],
    );
  }
}

Color eventColor(RecordingEvent event, ColorScheme colors) => switch (event) {
  RecordingEvent.human => Colors.purple,
  RecordingEvent.vehicle => Colors.cyan.shade700,
  RecordingEvent.motion => Colors.orange.shade800,
  RecordingEvent.scheduled => colors.primary.withValues(alpha: 0.4),
  RecordingEvent.alarm => Colors.red,
  RecordingEvent.lineCrossing => Colors.indigo,
  RecordingEvent.intrusion => Colors.teal,
  RecordingEvent.manual => Colors.brown,
  RecordingEvent.other => colors.tertiary,
};

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.center,
    required this.span,
    required this.start,
    required this.end,
    required this.records,
    required this.kinds,
    required this.colors,
    required this.style,
    required this.strings,
  });
  final DateTime center, start, end;
  final double span;
  final List<Recording> records;
  final List<RecordingEvent> kinds;
  final ColorScheme colors;
  final TextStyle style;
  final VideoStrings strings;
  double x(DateTime time, Size size) =>
      size.width * (0.5 + time.difference(center).inMilliseconds / span);
  int get tick {
    // Maintain readable labels as the time scale changes.
    const seconds = [
      10,
      15,
      30,
      60,
      120,
      300,
      600,
      900,
      1800,
      3600,
      7200,
      14400,
      21600,
      43200,
      86400,
      172800,
      259200,
      604800,
    ];
    return seconds.firstWhere(
          (s) => s * 1000 >= span / 4,
          orElse: () => seconds.last,
        ) *
        1000;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = colors.surfaceContainerHighest,
    );
    final left = center.millisecondsSinceEpoch - span / 2;
    final right = left + span;
    final first = (left / tick).ceil() * tick;
    for (var value = first; value <= right; value += tick) {
      final time = DateTime.fromMillisecondsSinceEpoch(value);
      final dx = x(time, size);
      canvas.drawLine(
        Offset(dx, 28),
        Offset(dx, size.height - 4),
        Paint()..color = colors.outlineVariant,
      );
      final text = TextPainter(
        text: TextSpan(
          text: span >= const Duration(hours: 6).inMilliseconds
              ? '${time.toLocal().month.toString().padLeft(2, "0")}-${time.toLocal().day.toString().padLeft(2, "0")}\n${recordingTimestamp(time)}'
              : recordingTimestamp(time),
          style: style.copyWith(color: colors.onSurface),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(
        canvas,
        Offset(
          (dx - text.width / 2).clamp(0, math.max(0, size.width - text.width)),
          6,
        ),
      );
    }
    for (final record in records) {
      if (record.end.millisecondsSinceEpoch < left ||
          record.start.millisecondsSinceEpoch > right) {
        continue;
      }
      final from = x(record.start, size).clamp(0.0, size.width);
      final to = x(record.end, size).clamp(0.0, size.width);
      for (final event in record.events) {
        final top = 38.0 + kinds.indexOf(event) * 12;
        canvas.drawRect(
          Rect.fromLTWH(from, top, math.max(3, to - from), 8),
          Paint()..color = eventColor(event, colors),
        );
      }
    }
    // Shade time outside the selected search range; no seek can leave it.
    final before = x(start, size).clamp(0.0, size.width);
    final after = x(end, size).clamp(0.0, size.width);
    canvas.drawRect(
      Rect.fromLTRB(0, 28, before, size.height),
      Paint()..color = colors.surface.withValues(alpha: 0.8),
    );
    canvas.drawRect(
      Rect.fromLTRB(after, 28, size.width, size.height),
      Paint()..color = colors.surface.withValues(alpha: 0.8),
    );
    canvas.drawLine(
      Offset(size.width / 2, 26),
      Offset(size.width / 2, size.height),
      Paint()
        ..color = colors.error
        ..strokeWidth = 2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.center != center ||
      old.span != span ||
      old.records != records ||
      old.colors != colors ||
      old.style != style ||
      old.strings.language != strings.language ||
      old.start != start ||
      old.end != end;
  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => [
        for (final record in records)
          if (record.end.isAfter(
                center.subtract(Duration(milliseconds: (span / 2).round())),
              ) &&
              record.start.isBefore(
                center.add(Duration(milliseconds: (span / 2).round())),
              ))
            CustomPainterSemantics(
              rect: Rect.fromLTRB(
                x(record.start, size).clamp(0.0, size.width),
                36,
                math
                    .min(
                      size.width,
                      math.max(x(record.start, size) + 3, x(record.end, size)),
                    )
                    .clamp(0.0, size.width),
                size.height - 4,
              ),
              properties: SemanticsProperties(
                textDirection: TextDirection.ltr,
                label:
                    '${record.events.map((e) => strings.text(e.label)).join(', ')} ${recordingTimestamp(record.start, date: true)} – ${recordingTimestamp(record.end, date: true)}',
              ),
            ),
      ];
  @override
  bool shouldRebuildSemantics(_RulerPainter oldDelegate) =>
      shouldRepaint(oldDelegate);
}
