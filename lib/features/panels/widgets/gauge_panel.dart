import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/motion.dart';
import '../../../core/theme/signal_colors.dart';
import '../models/panel_config.dart';

/// A gauge arc's height in dp, so every row with a gauge is the same
/// height whatever the tile's width. The arc is twice as wide as tall, at
/// most, and narrower on a Small phone tile; Wide and Full tiles centre
/// the same drawing instead of growing it. A fixed height (not a width
/// cap) because the grid sizes rows by intrinsic height, which a width cap
/// would answer from the tile's full width.
const double gaugeHeight = 100;

/// The band a gauge value falls in: the first of [bands] that contains it,
/// or null when none does (the arc then draws in ink).
GaugeBand? gaugeBandFor(num? value, List<GaugeBand> bands) {
  if (value == null) return null;
  for (final b in bands) {
    if (b.contains(value)) return b;
  }
  return null;
}

/// Where [value] sits between [min] and [max], 0 to 1, or null without a
/// value or a usable range.
double? gaugeFraction(num? value, double min, double max) {
  if (value == null || max <= min) return null;
  return ((value - min) / (max - min)).clamp(0.0, 1.0).toDouble();
}

/// A half arc for one reading (docs/design/gauge-2.4.md): the track shows
/// the colour bands, the value arc fills from the left in the band's tone,
/// the value sits inside the arc and the name below. Never mirrored in
/// right-to-left layouts, like a dial.
class GaugeArc extends StatelessWidget {
  const GaugeArc({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.bands,
    required this.label,
    this.strokeWidth = 10,
  });

  final num? value;
  final double min;
  final double max;
  final List<GaugeBand> bands;

  /// The formatted value shown inside the arc.
  final String label;
  final double strokeWidth;

  /// The colour the value arc draws in: the content colour of the band's
  /// theme role (the band tints the track with the role's container
  /// colour), or ink when the value is in no band or a normal one.
  @visibleForTesting
  Color fillColor(BuildContext context) {
    final roles = SignalColors.of(context);
    return switch (gaugeBandFor(value, bands)?.tone) {
      GaugeTone.good => roles.onHealthy,
      GaugeTone.attention => roles.onAttention,
      GaugeTone.normal || null => Theme.of(context).colorScheme.onSurface,
    };
  }

  @override
  Widget build(BuildContext context) {
    final roles = SignalColors.of(context);
    final theme = Theme.of(context);
    final fraction = gaugeFraction(value, min, max);
    final fill = fillColor(context);
    // A fixed-height 2:1 box, never a LayoutBuilder: the grid sizes rows
    // with IntrinsicHeight, which a LayoutBuilder cannot answer.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: fraction ?? 0),
      duration: SignalMotion.of(context, SignalMotion.stateChange),
      builder: (context, animated, _) => SizedBox(
        height: gaugeHeight,
        child: Center(
          child: AspectRatio(
            aspectRatio: 2,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GaugePainter(
                      fraction: fraction == null ? null : animated,
                      min: min,
                      max: max,
                      bands: bands,
                      strokeWidth: strokeWidth,
                      track: roles.hairline,
                      fill: fill,
                      good: roles.healthy,
                      attention: roles.attention,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    label,
                    style: theme.textTheme.headlineSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.fraction,
    required this.min,
    required this.max,
    required this.bands,
    required this.strokeWidth,
    required this.track,
    required this.fill,
    required this.good,
    required this.attention,
  });

  final double? fraction;
  final double min;
  final double max;
  final List<GaugeBand> bands;
  final double strokeWidth;
  final Color track;
  final Color fill;
  final Color good;
  final Color attention;

  @override
  void paint(Canvas canvas, Size size) {
    // The largest half circle that fits, stroke included, sitting on the
    // bottom edge.
    final radius = math.min(size.width / 2, size.height) - strokeWidth;
    if (radius <= 0) return;
    final center = Offset(size.width / 2, size.height - strokeWidth / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = math.pi;
    const sweep = math.pi;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, start, sweep, false, paint..color = track);

    // Bands tint the track in the role's container colour, so the whole
    // scale reads at a glance and the value arc stays legible on top.
    final span = max - min;
    if (span > 0) {
      final bandPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      for (final b in bands) {
        if (b.tone == GaugeTone.normal) continue;
        final from = ((b.from - min) / span).clamp(0.0, 1.0);
        final to = ((b.to - min) / span).clamp(0.0, 1.0);
        if (to <= from) continue;
        bandPaint.color = b.tone == GaugeTone.good ? good : attention;
        canvas.drawArc(
          rect,
          start + sweep * from,
          sweep * (to - from),
          false,
          bandPaint,
        );
      }
    }

    final f = fraction;
    if (f != null && f > 0) {
      canvas.drawArc(rect, start, sweep * f, false, paint..color = fill);
      // The bands show through the fill, so the scale still reads once the
      // value has passed them.
      if (span > 0) {
        final over = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt;
        for (final b in bands) {
          if (b.tone == GaugeTone.normal) continue;
          final from = ((b.from - min) / span).clamp(0.0, f);
          final to = ((b.to - min) / span).clamp(0.0, f);
          if (to <= from) continue;
          over.color = (b.tone == GaugeTone.good ? good : attention).withValues(
            alpha: 0.55,
          );
          canvas.drawArc(
            rect,
            start + sweep * from,
            sweep * (to - from),
            false,
            over,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction ||
      old.min != min ||
      old.max != max ||
      old.bands != bands ||
      old.fill != fill ||
      old.track != track;
}
