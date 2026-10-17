import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zigdash/data/database/database.dart' show Dashboard;
import 'package:zigdash/data/repositories/dashboard_repo.dart';
import 'package:zigdash/features/dashboards/wall_display.dart';
import 'package:zigdash/features/dashboards/wall_sensors.dart';
import 'package:zigdash/features/dashboards/widgets/wall_alarm_screen.dart';
import 'package:zigdash/features/dashboards/widgets/wall_idle_screen.dart';
import 'package:zigdash/features/devices/devices_providers.dart';
import 'package:zigdash/features/discovery/models/z2m_device.dart';
import 'package:zigdash/features/discovery/providers/discovery_provider.dart';
import 'package:zigdash/features/pro/pro.dart';
import 'package:zigdash/features/settings/providers/settings_controller.dart';
import 'package:zigdash/l10n/app_localizations.dart';

class _Wake extends ScreenWake {
  final dimCalls = <bool>[];
  final soundCalls = <bool>[];
  final brightnessCalls = <double?>[];
  @override
  Future<void> brightness(double? value) async => brightnessCalls.add(value);
  @override
  Future<void> keepOn(bool on) async {}
  @override
  Future<void> fullscreen(bool on) async {}
  @override
  Future<void> dim(bool on) async => dimCalls.add(on);
  @override
  Future<void> alarmSound(bool on) async => soundCalls.add(on);
  @override
  Future<bool> lockTask(bool on) async => true;
}

void main() {
  group('what wakes and what alarms', () {
    test('motion, presence or an opened door wakes', () {
      expect(wakesFor({'occupancy': true}), isTrue);
      expect(wakesFor({'presence': true}), isTrue);
      expect(wakesFor({'contact': false}), isTrue, reason: 'opened');
      expect(wakesFor({'contact': true}), isFalse, reason: 'closed');
      expect(wakesFor({'occupancy': false, 'temperature': 21}), isFalse);
    });

    test('alarms a state reports', () {
      expect(alarmsIn({'water_leak': true, 'battery': 80}), {
        WallAlarmKind.leak,
      });
      expect(alarmsIn({'smoke': true, 'gas': true}), {
        WallAlarmKind.smoke,
        WallAlarmKind.gas,
      });
      expect(alarmsIn({'carbon_monoxide': true}), {WallAlarmKind.co});
      expect(alarmsIn({'water_leak': false}), isEmpty);
    });

    test('an alarm fires once, OK puts it away, and it fires again only '
        'after clearing', () {
      final t = WallAlarmTracker();
      expect(t.update('Laundry', {'water_leak': true}), isTrue);
      expect(t.showing.single.kind, WallAlarmKind.leak);
      expect(
        t.update('Laundry', {'water_leak': true}),
        isFalse,
        reason: 'the same leak again',
      );
      t.acknowledge();
      expect(t.showing, isEmpty);
      expect(
        t.update('Laundry', {'water_leak': true}),
        isFalse,
        reason: 'acknowledged and still wet',
      );
      t.update('Laundry', {'water_leak': false});
      expect(t.update('Laundry', {'water_leak': true}), isTrue);
    });

    test('night hours, across midnight or not', () {
      DateTime at(int h, int m) => DateTime(2026, 10, 17, h, m);
      expect(isNightAt(at(23, 30), 23 * 60, 7 * 60), isTrue);
      expect(isNightAt(at(3, 0), 23 * 60, 7 * 60), isTrue);
      expect(isNightAt(at(7, 0), 23 * 60, 7 * 60), isFalse);
      expect(isNightAt(at(12, 0), 23 * 60, 7 * 60), isFalse);
      expect(isNightAt(at(1, 0), 0, 6 * 60), isTrue);
      expect(isNightAt(at(6, 0), 0, 6 * 60), isFalse);
      expect(isNightAt(at(6, 0), 60, 60), isFalse, reason: 'empty night');
    });

    test('a message without the alarm property keeps its state', () {
      final t = WallAlarmTracker();
      t.update('Hall', {'smoke': true});
      t.acknowledge();
      expect(t.update('Hall', {'battery': 90}), isFalse);
      expect(
        t.update('Hall', {'smoke': true}),
        isFalse,
        reason: 'never cleared, so still acknowledged',
      );
    });
  });

  group('the wall display reacts (wall-tablet-2.9.md)', () {
    late SharedPreferences prefs;
    late _Wake wake;
    late StreamController<WallStateEvent> events;
    var seq = 0;

    final motion = parseBridgeDevices(
      jsonEncode([
        {
          'friendly_name': 'Hallway motion',
          'ieee_address': '0x00158d0001a2b3c4',
          'type': 'EndDevice',
          'supported': true,
          'definition': {
            'exposes': [
              {
                'type': 'binary',
                'name': 'occupancy',
                'property': 'occupancy',
                'access': 1,
                'value_on': true,
                'value_off': false,
              },
            ],
          },
        },
      ]),
    ).single;

    Future<void> pump(
      WidgetTester tester,
      Map<String, Object> values, {
      DateTime? now,
      DateTime Function()? clock,
    }) async {
      SharedPreferences.setMockInitialValues({
        'wall_display_d1': true,
        ...values,
      });
      prefs = await SharedPreferences.getInstance();
      wake = _Wake();
      events = StreamController<WallStateEvent>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            screenWakeProvider.overrideWithValue(wake),
            proStatusProvider.overrideWithValue(ProStatus.unlocked),
            if (now != null) wallNowProvider.overrideWithValue(() => now),
            if (clock != null) wallNowProvider.overrideWithValue(clock),
            dashboardByIdProvider('d1').overrideWith(
              (_) async => Dashboard(
                id: 'd1',
                connectionId: 'c1',
                name: 'Home',
                topicPrefix: 'zigbee2mqtt',
                colorSeed: 0,
                iconCodepoint: 0,
                locked: false,
                sortOrder: 0,
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
              ),
            ),
            homeBaseTopicProvider('c1').overrideWith((_) => 'zigbee2mqtt'),
            bridgeDevicesStreamProvider((
              connectionId: 'c1',
              base: 'zigbee2mqtt',
            )).overrideWith((_) => Stream.value([motion])),
            wallStateEventsProvider((
              connectionId: 'c1',
              base: 'zigbee2mqtt',
            )).overrideWith((_) => events.stream),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: WallDisplayScope(
              dashboardId: 'd1',
              active: true,
              child: Scaffold(body: Text('tile')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    Future<void> send(
      WidgetTester tester,
      String name,
      Map<String, Object?> s,
    ) async {
      events.add((seq: seq++, name: name, state: s));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a picked motion sensor wakes the idle screen', (tester) async {
      await pump(tester, {
        'wall_dim_d1': 1,
        'wall_idle_show_d1': 'clock',
        'wall_motion_sensors_d1': ['0x00158d0001a2b3c4'],
      });
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      expect(find.byType(WallIdleScreen), findsOneWidget);

      await send(tester, 'Other sensor', {'occupancy': true});
      expect(find.byType(WallIdleScreen), findsOneWidget, reason: 'not picked');

      await send(tester, 'Hallway motion', {'occupancy': true});
      expect(find.byType(WallIdleScreen), findsNothing);
      expect(wake.dimCalls.last, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a leak takes over with a sound until OK, and keeps the '
        'screen bright', (tester) async {
      await pump(tester, {'wall_dim_d1': 1, 'wall_alarms_d1': true});
      await send(tester, 'Laundry leak', {'water_leak': true});
      expect(find.byType(WallAlarmScreen), findsOneWidget);
      expect(find.text('Water leak'), findsOneWidget);
      expect(find.text('Laundry leak'), findsOneWidget);
      expect(wake.soundCalls, [true]);

      bool chromeHidden() => ProviderScope.containerOf(
        tester.element(find.byType(WallDisplayScope)),
      ).read(wallChromeHiddenProvider);
      expect(chromeHidden(), isTrue, reason: 'no header or navigation');

      await tester.pump(const Duration(minutes: 2));
      expect(wake.dimCalls, isNot(contains(true)), reason: 'stays bright');

      await tester.tap(find.text('OK'));
      await tester.pump();
      expect(find.byType(WallAlarmScreen), findsNothing);
      expect(wake.soundCalls, [true, false]);
      expect(chromeHidden(), isFalse, reason: 'back after OK');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('at night the idle screen is black, even set to Never, and '
        'motion wakes it only dimly', (tester) async {
      await pump(tester, {
        'wall_dim_d1': 0,
        'wall_idle_show_d1': 'clock',
        'wall_night_on_d1': true,
        'wall_motion_sensors_d1': ['0x00158d0001a2b3c4'],
      }, now: DateTime(2026, 10, 17, 2, 30));
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      expect(
        tester.widget<WallIdleScreen>(find.byType(WallIdleScreen)).show,
        WallIdleShow.black,
      );

      await send(tester, 'Hallway motion', {'occupancy': true});
      expect(find.byType(WallIdleScreen), findsNothing);
      expect(wake.brightnessCalls, [nightWakeBrightness]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('night starting while the clock shows turns it black', (
      tester,
    ) async {
      var now = DateTime(2026, 10, 17, 22, 58);
      await pump(tester, {
        'wall_dim_d1': 1,
        'wall_idle_show_d1': 'clock',
        'wall_night_on_d1': true,
      }, clock: () => now);
      now = DateTime(2026, 10, 17, 22, 59);
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      expect(
        tester.widget<WallIdleScreen>(find.byType(WallIdleScreen)).show,
        WallIdleShow.clock,
      );
      now = DateTime(2026, 10, 17, 23, 0);
      await tester.pump(const Duration(minutes: 1));
      expect(
        tester.widget<WallIdleScreen>(find.byType(WallIdleScreen)).show,
        WallIdleShow.black,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('by day the night schedule changes nothing', (tester) async {
      await pump(tester, {
        'wall_dim_d1': 1,
        'wall_idle_show_d1': 'clock',
        'wall_night_on_d1': true,
      }, now: DateTime(2026, 10, 17, 14, 0));
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      expect(
        tester.widget<WallIdleScreen>(find.byType(WallIdleScreen)).show,
        WallIdleShow.clock,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('alarms off: nothing takes over', (tester) async {
      await pump(tester, {
        'wall_motion_sensors_d1': ['0x00158d0001a2b3c4'],
      });
      await send(tester, 'Laundry leak', {'water_leak': true});
      expect(find.byType(WallAlarmScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
