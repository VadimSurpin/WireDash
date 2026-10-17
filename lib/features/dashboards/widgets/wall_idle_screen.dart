import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/motion.dart';
import '../../../data/repositories/dashboard_repo.dart';
import '../../panels/providers/panel_value_provider.dart';
import '../../panels/widgets/device_tile_panel.dart' show formatReading, ltr;
import '../wall_display.dart';
import '../wall_readings.dart';

/// What an idle wall display shows over its dashboard (wall-tablet-2.9.md
/// §2): a clock that drifts a little every minute so nothing burns into the
/// screen, or plain black. Always black behind, in light and dark themes
/// alike: it is a screen at night as much as by day, and black pixels are
/// off on OLED panels. The touch that wakes it never reaches a tile.
class WallIdleScreen extends StatefulWidget {
  const WallIdleScreen({
    super.key,
    required this.show,
    this.dashboardId,
    this.now,
  });

  final WallIdleShow show;

  /// Whose readings [WallIdleShow.readings] shows.
  final String? dashboardId;

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
                if (widget.show == WallIdleShow.readings &&
                    widget.dashboardId != null)
                  _Readings(dashboardId: widget.dashboardId!, ink: ink),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Up to three of the dashboard's numbers under the clock, large, each with
/// its tile's name.
class _Readings extends ConsumerWidget {
  const _Readings({required this.dashboardId, required this.ink});

  final String dashboardId;
  final Color ink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionId = ref
        .watch(dashboardByIdProvider(dashboardId))
        .valueOrNull
        ?.connectionId;
    final readings = ref.watch(wallIdleReadingsProvider(dashboardId));
    if (connectionId == null || readings.isEmpty) return const SizedBox();
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Wrap(
        spacing: 48,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: [
          for (final r in readings)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _format(
                    ref
                        .watch(
                          panelValueProvider(
                            PanelStreamKey(
                              connectionId: connectionId,
                              topic: r.topic,
                              jsonPath: r.path,
                            ),
                          ),
                        )
                        .valueOrNull,
                    r,
                  ),
                  style: text.displaySmall?.copyWith(color: ink),
                ),
                Text(
                  r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyLarge?.copyWith(
                    color: ink.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _format(Object? raw, WallReading r) {
    final v = raw is num ? raw : num.tryParse('${raw ?? ''}');
    if (v == null) return '—';
    if (r.decimals == null) return formatReading(v, r.unit);
    return ltr(
      '${v.toStringAsFixed(r.decimals!)}${r.unit == null ? '' : ' ${r.unit}'}',
    );
  }
}
