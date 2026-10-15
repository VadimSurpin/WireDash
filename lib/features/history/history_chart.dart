import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'history_record.dart';

/// History's graph (docs/design/history-2.7.md, decision 9): the averages as
/// a line over a shaded band from minimum to maximum, in the accent colour.
/// A touch shows the point under the finger through [onScrub]; lifting the
/// finger clears it. Gaps in recording stay gaps.
class HistoryChart extends StatefulWidget {
  const HistoryChart({
    super.key,
    required this.points,
    required this.from,
    required this.to,
    required this.step,
    required this.color,
    required this.gridColor,
    required this.labelStyle,
    required this.formatValue,
    required this.formatTime,
    this.onScrub,
  });

  final List<HistoryPoint> points;

  /// The view's time span; points are placed in it.
  final DateTime from;
  final DateTime to;

  /// The spacing of [points] (15 minutes, an hour or a day): a jump of more
  /// than twice this breaks the line.
  final Duration step;

  final Color color;
  final Color gridColor;
  final TextStyle labelStyle;
  final String Function(double) formatValue;
  final String Function(DateTime) formatTime;
  final ValueChanged<HistoryPoint?>? onScrub;

  @override
  State<HistoryChart> createState() => _HistoryChartState();
}

class _HistoryChartState extends State<HistoryChart> {
  HistoryPoint? _scrub;

  void _scrubAt(double dx, double width) {
    if (widget.points.isEmpty || width <= 0) return;
    final span = widget.to.difference(widget.from).inMilliseconds;
    final t = widget.from.add(
      Duration(milliseconds: (dx / width * span).round()),
    );
    var best = widget.points.first;
    for (final p in widget.points) {
      if ((p.at.difference(t)).abs() < (best.at.difference(t)).abs()) best = p;
    }
    if (best != _scrub) {
      setState(() => _scrub = best);
      widget.onScrub?.call(best);
    }
  }

  void _end() {
    setState(() => _scrub = null);
    widget.onScrub?.call(null);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (d) => _scrubAt(d.localPosition.dx, c.maxWidth),
      onHorizontalDragUpdate: (d) => _scrubAt(d.localPosition.dx, c.maxWidth),
      onHorizontalDragEnd: (_) => _end(),
      onTapDown: (d) => _scrubAt(d.localPosition.dx, c.maxWidth),
      onTapUp: (_) => _end(),
      child: CustomPaint(
        size: Size(c.maxWidth, c.maxHeight),
        painter: HistoryPainter(
          points: widget.points,
          from: widget.from,
          to: widget.to,
          step: widget.step,
          color: widget.color,
          gridColor: widget.gridColor,
          labelStyle: widget.labelStyle,
          formatValue: widget.formatValue,
          formatTime: widget.formatTime,
          scrub: _scrub,
        ),
      ),
    ),
  );
}

class HistoryPainter extends CustomPainter {
  HistoryPainter({
    required this.points,
    required this.from,
    required this.to,
    required this.step,
    required this.color,
    required this.gridColor,
    required this.labelStyle,
    required this.formatValue,
    required this.formatTime,
    this.scrub,
  });

  final List<HistoryPoint> points;
  final DateTime from;
  final DateTime to;
  final Duration step;
  final Color color;
  final Color gridColor;
  final TextStyle labelStyle;
  final String Function(double) formatValue;
  final String Function(DateTime) formatTime;
  final HistoryPoint? scrub;

  static const _labelGap = 6.0;

  TextPainter _text(String s) => TextPainter(
    text: TextSpan(text: s, style: labelStyle),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    var lo = points.map((p) => p.min).reduce(math.min);
    var hi = points.map((p) => p.max).reduce(math.max);
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * 0.08;
    // A reading that never goes below zero (power, humidity) keeps its
    // axis at zero instead of padding into negative numbers.
    lo = lo >= 0 && lo - pad < 0 ? 0 : lo - pad;
    hi += pad;

    final hiLabel = _text(formatValue(hi));
    final loLabel = _text(formatValue(lo));
    final timeH = _text(formatTime(from)).height;
    final top = 0.0;
    final bottom = size.height - timeH - _labelGap;
    final chartH = bottom - top;
    final span = to.difference(from).inMilliseconds.toDouble();
    double x(DateTime t) =>
        (t.difference(from).inMilliseconds / span).clamp(0.0, 1.0) * size.width;
    double y(double v) => top + (hi - v) / (hi - lo) * chartH;

    // Grid: top, middle and bottom lines, the range's end values.
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      final gy = top + chartH * f;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }
    hiLabel.paint(canvas, Offset(0, top + 2));
    loLabel.paint(canvas, Offset(0, bottom - loLabel.height - 2));

    // Time labels: start, middle, end.
    for (final (t, align) in [
      (from, 0.0),
      (from.add(to.difference(from) ~/ 2), 0.5),
      (to, 1.0),
    ]) {
      final tp = _text(formatTime(t));
      tp.paint(
        canvas,
        Offset(
          (x(t) - tp.width * align).clamp(0, size.width - tp.width),
          bottom + _labelGap,
        ),
      );
    }

    // Runs of points without a gap.
    final runs = <List<HistoryPoint>>[[]];
    for (final p in points) {
      final run = runs.last;
      if (run.isNotEmpty && p.at.difference(run.last.at) > step * 2) {
        runs.add([]);
      }
      runs.last.add(p);
    }

    final band = Paint()..color = color.withValues(alpha: 0.18);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    for (final run in runs) {
      if (run.isEmpty) continue;
      if (run.length == 1) {
        final p = run.single;
        canvas.drawCircle(
          Offset(x(p.at), y(p.avg)),
          2.5,
          Paint()..color = color,
        );
        continue;
      }
      final area = Path()..moveTo(x(run.first.at), y(run.first.max));
      for (final p in run.skip(1)) {
        area.lineTo(x(p.at), y(p.max));
      }
      for (final p in run.reversed) {
        area.lineTo(x(p.at), y(p.min));
      }
      area.close();
      canvas.drawPath(area, band);
      final path = Path()..moveTo(x(run.first.at), y(run.first.avg));
      for (final p in run.skip(1)) {
        path.lineTo(x(p.at), y(p.avg));
      }
      canvas.drawPath(path, line);
    }

    final s = scrub;
    if (s != null) {
      final sx = x(s.at);
      canvas.drawLine(
        Offset(sx, top),
        Offset(sx, bottom),
        Paint()
          ..color = color.withValues(alpha: 0.6)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(Offset(sx, y(s.avg)), 4.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(HistoryPainter old) =>
      old.points != points ||
      old.scrub != scrub ||
      old.color != color ||
      old.from != from ||
      old.to != to;
}
