import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash_video/wiredash_video.dart';

void main() {
  final time = DateTime(2026, 10, 31, 10);
  Widget ruler(
    ValueChanged<DateTime> seek, {
    List<Recording> records = const [],
    bool enabled = true,
  }) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 400,
          child: RecordingTimeRuler(
            start: time.subtract(const Duration(hours: 1)),
            end: time.add(const Duration(hours: 1)),
            position: time,
            records: records,
            onSeek: seek,
            enabled: enabled,
          ),
        ),
      ),
    ),
  );
  testWidgets(
    'absolute time selection uses the visible scale and zoom never seeks',
    (tester) async {
      final selected = <DateTime>[];
      await tester.pumpWidget(ruler(selected.add));
      expect(find.text('2026-10-31 10:00:00'), findsOneWidget);
      expect(find.byKey(const Key('ruler-scale')), findsOneWidget);
      final bounds = tester.getRect(
        find.byKey(const Key('recording-time-ruler')),
      );
      await tester.tapAt(
        Offset(bounds.left + bounds.width * 0.75, bounds.center.dy),
      );
      await tester.pump();
      expect(
        selected.single,
        time.add(const Duration(minutes: 7, seconds: 30)),
      );
      selected.clear();
      await tester.tap(find.byTooltip('Zoom in timeline'));
      await tester.pump();
      expect(selected, isEmpty);
      // The same quarter-width offset now represents half as much time.
      await tester.tapAt(
        Offset(bounds.left + bounds.width * 0.75, bounds.center.dy),
      );
      await tester.pump();
      expect(
        selected.single,
        time.add(const Duration(minutes: 11, seconds: 15)),
      );
    },
  );
  testWidgets(
    'dragging seeks once on release; pinch changes scale without restarting playback',
    (tester) async {
      final selected = <DateTime>[];
      await tester.pumpWidget(ruler(selected.add));
      final finder = find.byKey(const Key('recording-time-ruler'));
      final center = tester.getCenter(finder);
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();
      expect(selected, isEmpty);
      await gesture.up();
      await tester.pump();
      expect(selected, hasLength(1));
      expect(selected.single.isBefore(time), isTrue);
      selected.clear();
      final before = tester
          .widget<Text>(find.byKey(const Key('ruler-scale')))
          .data;
      final left = await tester.startGesture(
        center - const Offset(40, 0),
        pointer: 1,
      );
      final right = await tester.startGesture(
        center + const Offset(40, 0),
        pointer: 2,
      );
      await left.moveBy(const Offset(-40, 0));
      await right.moveBy(const Offset(40, 0));
      await tester.pump();
      await left.up();
      await right.up();
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('ruler-scale'))).data,
        isNot(before),
      );
      expect(selected, isEmpty);
    },
  );
  testWidgets(
    'all event types appear and the time scale clamps to search bounds',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final records = [
        for (final kind in [
          RecordingEvent.motion,
          RecordingEvent.human,
          RecordingEvent.vehicle,
        ])
          Recording(
            start: time,
            end: time.add(const Duration(seconds: 20)),
            playback: Uri.parse('rtsp://camera/archive'),
            eventTypes: [kind],
          ),
      ];
      final selected = <DateTime>[];
      await tester.pumpWidget(ruler(selected.add, records: records));
      expect(find.text('Motion'), findsOneWidget);
      expect(find.text('Person'), findsOneWidget);
      expect(find.text('Vehicle'), findsOneWidget);
      for (var n = 0; n < 4; n++) {
        await tester.tap(find.byTooltip('Zoom out timeline'));
        await tester.pump();
      }
      final bounds = tester.getRect(
        find.byKey(const Key('recording-time-ruler')),
      );
      await tester.tapAt(Offset(bounds.right - 1, bounds.center.dy));
      await tester.pump();
      await tester.tapAt(Offset(bounds.right - 1, bounds.center.dy));
      await tester.pump();
      expect(selected.last, time.add(const Duration(hours: 1)));
      semantics.dispose();
    },
  );
}
