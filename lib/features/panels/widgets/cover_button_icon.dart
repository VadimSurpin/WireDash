import 'package:flutter/material.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../models/cover_controls.dart';

class CoverButtonGlyph extends StatelessWidget {
  const CoverButtonGlyph(this.icon, {super.key, this.size});
  final CoverButtonIcon icon;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final material = switch (icon) {
      CoverButtonIcon.up => Icons.keyboard_arrow_up,
      CoverButtonIcon.down => Icons.keyboard_arrow_down,
      CoverButtonIcon.left => Icons.keyboard_arrow_left,
      CoverButtonIcon.right => Icons.keyboard_arrow_right,
      CoverButtonIcon.stop => Icons.stop,
      CoverButtonIcon.rollerOpen => Icons.roller_shades,
      CoverButtonIcon.rollerClosed => Icons.roller_shades_closed,
      _ => null,
    };
    if (material != null) return Icon(material, size: size);
    return CustomPaint(
      size: Size.square(size ?? IconTheme.of(context).size ?? 24),
      painter: _GatePainter(
        icon,
        IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

String coverIconLabel(BuildContext context, CoverButtonIcon icon) {
  final l10n = context.l10n;
  return switch (icon) {
    CoverButtonIcon.up => '↑',
    CoverButtonIcon.down => '↓',
    CoverButtonIcon.left => '←',
    CoverButtonIcon.right => '→',
    CoverButtonIcon.stop => l10n.panelCoverStop,
    CoverButtonIcon.rollerOpen => l10n.coverRollerOpen,
    CoverButtonIcon.rollerClosed => l10n.coverRollerClosed,
    CoverButtonIcon.gateOpen => l10n.coverGateOpen,
    CoverButtonIcon.gateClosed => l10n.coverGateClosed,
    CoverButtonIcon.gatePartial => l10n.coverGatePartial,
  };
}

/// Vector gate leaves: closed, part-open, and fully open have distinct silhouettes.
class _GatePainter extends CustomPainter {
  const _GatePainter(this.icon, this.color);
  final CoverButtonIcon icon;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(2, 5), const Offset(2, 21), pen);
    canvas.drawLine(const Offset(22, 5), const Offset(22, 21), pen);
    final reach = icon == CoverButtonIcon.gateClosed
        ? 9.5
        : icon == CoverButtonIcon.gatePartial
        ? 6.0
        : 2.0;
    final drop = icon == CoverButtonIcon.gateClosed ? 0.0 : 3.0;
    for (final left in [true, false]) {
      final x = left ? 3.0 : 21.0;
      final tip = x + (left ? reach : -reach);
      canvas.drawPath(
        Path()
          ..moveTo(x, 7)
          ..lineTo(tip, 7 + drop)
          ..lineTo(tip, 19 + drop)
          ..lineTo(x, 19)
          ..close(),
        pen,
      );
      for (var i = 1; i < 4; i++) {
        final t = i / 4;
        final bar = x + (tip - x) * t;
        canvas.drawLine(
          Offset(bar, 7 + drop * t),
          Offset(bar, 19 + drop * t),
          pen,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GatePainter old) =>
      old.icon != icon || old.color != color;
}
