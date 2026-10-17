import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/motion.dart';
import '../wall_display.dart';

/// What an idle wall display shows over its dashboard (wall-tablet-2.9.md
/// §2): a clock that drifts a little every minute so nothing burns into the
/// screen, or plain black. Always black behind, in light and dark themes
/// alike: it is a screen at night as much as by day, and black pixels are
/// off on OLED panels. The touch that wakes it never reaches a tile.
class WallIdleScreen extends StatefulWidget {
  const WallIdleScreen({super.key, required this.show, this.now});

  final WallIdleShow show;

  /// The clock's time source; tests pass a fixed one.
  final DateTime Function()? now;

  @override
  State<WallIdleScreen> createState() => _WallIdleScreenState();
}

/// Where the clock sits, in turn: small steps around the middle.
const _drift = [
  Alignment(0, -0.1),
  Alignment(0.25, 0.1),
  Alignment(-0.2, 0.25),
  Alignment(0.15, -0.3),
  Alignment(-0.25, -0.05),
];

class _WallIdleScreenState extends State<WallIdleScreen> {
  Timer? _tick;
  late DateTime _now;
  int _step = 0;

  DateTime _read() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _now = _read();
    _schedule();
  }

  /// Wakes at the next whole minute: the time changes and the clock moves.
  void _schedule() {
    final next = Duration(seconds: 60 - _now.second);
    _tick = Timer(next, () {
      if (!mounted) return;
      setState(() {
        _now = _read();
        _step = (_step + 1) % _drift.length;
      });
      _schedule();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final black = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: const ColoredBox(color: Colors.black),
    );
    if (widget.show == WallIdleShow.black || widget.show == WallIdleShow.dim) {
      return black;
    }
    final loc = MaterialLocalizations.of(context);
    final h24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final time = loc.formatTimeOfDay(
      TimeOfDay.fromDateTime(_now),
      alwaysUse24HourFormat: h24,
    );
    final date = loc.formatFullDate(_now);
    final text = Theme.of(context).textTheme;
    const ink = Color(0xFFE6E1D8);
    return Stack(
      fit: StackFit.expand,
      children: [
        black,
        IgnorePointer(
          child: AnimatedAlign(
            alignment: _drift[_step],
            duration: SignalMotion.of(context, SignalMotion.idleDrift),
            curve: Curves.easeInOut,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  child: Text(
                    time,
                    style: text.displayLarge?.copyWith(
                      color: ink,
                      fontSize: 120,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),
                Text(
                  date,
                  style: text.titleLarge?.copyWith(
                    color: ink.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
