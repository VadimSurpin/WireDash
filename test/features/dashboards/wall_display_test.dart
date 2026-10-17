import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zigdash/features/dashboards/wall_display.dart';
import 'package:zigdash/features/dashboards/widgets/wall_idle_screen.dart';
import 'package:zigdash/features/pro/pro.dart';
import 'package:zigdash/features/settings/providers/settings_controller.dart';

class _Wake extends ScreenWake {
  final calls = <bool>[];
  final fullscreenCalls = <bool>[];
  final dimCalls = <bool>[];
  final lockCalls = <bool>[];
  @override
  Future<void> keepOn(bool on) async => calls.add(on);
  @override
  Future<void> fullscreen(bool on) async => fullscreenCalls.add(on);
  @override
  Future<void> dim(bool on) async => dimCalls.add(on);
  @override
  Future<bool> lockTask(bool on) async {
    lockCalls.add(on);
    return true;
  }
}

void main() {
  late SharedPreferences prefs;
  late _Wake wake;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'wall_display_d1': true});
    prefs = await SharedPreferences.getInstance();
    wake = _Wake();
  });

  Widget app({bool active = true, String id = 'd1'}) => ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      screenWakeProvider.overrideWithValue(wake),
    ],
    child: MaterialApp(
      home: Consumer(
        builder: (context, ref, _) => WallDisplayScope(
          dashboardId: id,
          active: active,
          child: Scaffold(
            body: Center(
              child: Text(
                ref.watch(wallChromeHiddenProvider) ? 'hidden' : 'shown',
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('keeps the screen on and hides the chrome after 10 s', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();
    expect(wake.calls, [true]);
    expect(find.text('shown'), findsOneWidget);

    await tester.pump(wallChromeDelay + const Duration(milliseconds: 1));
    expect(find.text('hidden'), findsOneWidget);

    await tester.tap(find.text('hidden'));
    await tester.pump();
    expect(
      find.text('shown'),
      findsOneWidget,
      reason: 'a touch brings it back',
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(wake.calls.last, isFalse, reason: 'leaving lets the screen sleep');
  });

  group('fullscreen, dim and OS pinning (kiosk-2.6.md)', () {
    testWidgets('fullscreen and dim follow a wall display', (tester) async {
      SharedPreferences.setMockInitialValues({
        'wall_display_d1': true,
        'wall_fullscreen_d1': true,
        'wall_dim_d1': 5,
      });
      prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(app());
      await tester.pump();
      expect(wake.fullscreenCalls, [true]);
      expect(wake.dimCalls, isEmpty);

      await tester.pump(const Duration(minutes: 5, seconds: 1));
      expect(wake.dimCalls, [true], reason: 'dims after 5 min untouched');

      await tester.tap(find.byType(Text));
      await tester.pump();
      expect(wake.dimCalls, [true, false], reason: 'a touch undims');

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(wake.fullscreenCalls.last, isFalse, reason: 'leaving restores');
      expect(wake.lockCalls, isEmpty, reason: 'no kiosk: no OS pinning');
    });

    testWidgets('a kiosk without wall display still gets fullscreen and dim, '
        'and OS pinning when chosen', (tester) async {
      SharedPreferences.setMockInitialValues({
        'kiosk_connection': 'c1',
        'kiosk_dashboard': 'd1',
        'kiosk_os_pinning': true,
        'wall_fullscreen_d1': true,
        'wall_dim_d1': 1,
      });
      prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(app());
      await tester.pump();
      expect(wake.calls, isEmpty, reason: 'keep-on is its own switch');
      expect(wake.fullscreenCalls, [true]);
      expect(wake.lockCalls, [true]);
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      expect(wake.dimCalls, [true]);
      expect(
        find.text('shown'),
        findsOneWidget,
        reason: 'the chrome timer belongs to wall display, not kiosk',
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(wake.lockCalls, [true, false], reason: 'leaving unpins');
      expect(wake.dimCalls, [true, false]);
    });
  });

  group('the idle screen (wall-tablet-2.9.md)', () {
    Widget tappable({required VoidCallback onTap}) => ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        screenWakeProvider.overrideWithValue(wake),
      ],
      child: MaterialApp(
        home: WallDisplayScope(
          dashboardId: 'd1',
          active: true,
          child: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: onTap,
                child: const Text('tile'),
              ),
            ),
          ),
        ),
      ),
    );

    testWidgets('dimmed is the default: no screen over the dashboard', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'wall_display_d1': true,
        'wall_dim_d1': 1,
      });
      prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(app());
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      expect(wake.dimCalls, [true]);
      expect(find.byType(WallIdleScreen), findsNothing);
    });

    testWidgets('the clock covers the dashboard; the waking touch hits no '
        'tile', (tester) async {
      SharedPreferences.setMockInitialValues({
        'wall_display_d1': true,
        'wall_dim_d1': 1,
        'wall_idle_show_d1': 'clock',
      });
      prefs = await SharedPreferences.getInstance();
      var taps = 0;
      await tester.pumpWidget(tappable(onTap: () => taps++));
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      expect(find.byType(WallIdleScreen), findsOneWidget);
      expect(wake.dimCalls, [true]);

      await tester.tapAt(tester.getCenter(find.text('tile')));
      await tester.pump();
      expect(taps, 0, reason: 'the touch only wakes the screen');
      expect(find.byType(WallIdleScreen), findsNothing);
      expect(wake.dimCalls, [true, false]);

      await tester.tap(find.text('tile'));
      expect(taps, 1, reason: 'awake, tiles work again');

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('readings without Pro fall back to the clock', (tester) async {
      SharedPreferences.setMockInitialValues({
        'wall_display_d1': true,
        'wall_dim_d1': 1,
        'wall_idle_show_d1': 'readings',
      });
      prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            screenWakeProvider.overrideWithValue(wake),
            proStatusProvider.overrideWithValue(ProStatus.locked),
          ],
          child: const MaterialApp(
            home: WallDisplayScope(
              dashboardId: 'd1',
              active: true,
              child: Scaffold(body: Text('tile')),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      expect(
        tester.widget<WallIdleScreen>(find.byType(WallIdleScreen)).show,
        WallIdleShow.clock,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('black covers the dashboard too', (tester) async {
      SharedPreferences.setMockInitialValues({
        'wall_display_d1': true,
        'wall_dim_d1': 5,
        'wall_idle_show_d1': 'black',
      });
      prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(app());
      await tester.pump(const Duration(minutes: 5, seconds: 1));
      expect(find.byType(WallIdleScreen), findsOneWidget);
      expect(find.text('hidden'), findsOneWidget, reason: 'still built below');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('the clock shows the time and moves every minute', (
      tester,
    ) async {
      var now = DateTime(2026, 10, 17, 21, 5, 30);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(alwaysUse24HourFormat: true),
            child: WallIdleScreen(show: WallIdleShow.clock, now: () => now),
          ),
        ),
      );
      expect(find.text('21:05'), findsOneWidget);
      final first = tester.widget<AnimatedAlign>(find.byType(AnimatedAlign));
      now = DateTime(2026, 10, 17, 21, 6);
      await tester.pump(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('21:06'), findsOneWidget);
      final second = tester.widget<AnimatedAlign>(find.byType(AnimatedAlign));
      expect(second.alignment, isNot(first.alignment));
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('off by default, and never in Edit mode', (tester) async {
    await tester.pumpWidget(app(id: 'other'));
    await tester.pump(wallChromeDelay * 2);
    expect(find.text('shown'), findsOneWidget);
    expect(wake.calls, isEmpty);

    await tester.pumpWidget(app(active: false));
    await tester.pump(wallChromeDelay * 2);
    expect(find.text('shown'), findsOneWidget);
    expect(wake.calls, isEmpty);
  });
}
