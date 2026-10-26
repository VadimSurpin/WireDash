import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiredash/features/kiosk/kiosk.dart';
import 'package:wiredash/features/settings/providers/settings_controller.dart';

class FakeKioskPinStore extends KioskPinStore {
  FakeKioskPinStore() : super(const FlutterSecureStorage());
  String? pin;
  @override
  Future<String?> read() async => pin;
  @override
  Future<void> write(String value) async => pin = value;
  @override
  Future<void> delete() async => pin = null;
}

void main() {
  group('kioskRedirect', () {
    const off = KioskState();
    const on = KioskState(connectionId: 'c1', dashboardId: 'd1');

    test('off: nothing redirects', () {
      expect(kioskRedirect(kiosk: off, location: '/settings'), isNull);
    });

    test('on: the pinned dashboards page is allowed, nothing else', () {
      expect(
        kioskRedirect(kiosk: on, location: '/connections/c1/dashboards'),
        isNull,
      );
      for (final blocked in [
        '/settings',
        '/connections/c1/devices',
        '/connections/c1/devices/0x1',
        '/connections/c1/scenes',
        '/connections/c1/dashboards/form',
        '/connections/c1/dashboards/d1/edit',
        '/connections/c1/dashboards/d1/add',
        '/connections/c2/dashboards',
        '/setup',
        '/start',
      ]) {
        expect(
          kioskRedirect(kiosk: on, location: blocked),
          '/connections/c1/dashboards',
          reason: blocked,
        );
      }
    });
  });

  group('KioskController', () {
    late SharedPreferences prefs;
    late FakeKioskPinStore pins;
    late ProviderContainer container;

    Future<void> build([Map<String, Object> initial = const {}]) async {
      SharedPreferences.setMockInitialValues(initial);
      prefs = await SharedPreferences.getInstance();
      pins = FakeKioskPinStore();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          kioskPinStoreProvider.overrideWithValue(pins),
        ],
      );
      addTearDown(container.dispose);
    }

    test('off until started; start and stop persist', () async {
      await build();
      expect(container.read(kioskProvider).on, isFalse);
      await container.read(kioskProvider.notifier).start('c1', 'd1');
      expect(container.read(kioskProvider).on, isTrue);
      expect(prefs.getString('kiosk_dashboard'), 'd1');
      expect(prefs.getString('kiosk_connection'), 'c1');
      await container.read(kioskProvider.notifier).stop();
      expect(container.read(kioskProvider).on, isFalse);
      expect(prefs.getString('kiosk_dashboard'), isNull);
    });

    test(
      'a stored kiosk comes back on the next start (a rebooted tablet)',
      () async {
        await build({'kiosk_connection': 'c1', 'kiosk_dashboard': 'd1'});
        final state = container.read(kioskProvider);
        expect(state.on, isTrue);
        expect(kioskHome(state), '/connections/c1/dashboards');
      },
    );

    test('the PIN lives in the secure store and is checked there', () async {
      await build();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(kioskProvider).hasPin, isFalse);
      final kiosk = container.read(kioskProvider.notifier);
      expect(
        await kiosk.checkPin('0000'),
        isTrue,
        reason: 'no PIN set: anything passes',
      );
      await kiosk.setPin('1234');
      expect(container.read(kioskProvider).hasPin, isTrue);
      expect(pins.pin, '1234');
      expect(await kiosk.checkPin('0000'), isFalse);
      expect(await kiosk.checkPin('1234'), isTrue);
      await kiosk.clearPin();
      expect(container.read(kioskProvider).hasPin, isFalse);
      expect(pins.pin, isNull);
    });

    test('an existing PIN is seen on start', () async {
      await build();
      pins.pin = '4321';
      container.invalidate(kioskProvider);
      container.read(kioskProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(kioskProvider).hasPin, isTrue);
    });

    test('OS pinning is a stored choice', () async {
      await build();
      await container.read(kioskProvider.notifier).setOsPinning(true);
      expect(container.read(kioskProvider).osPinning, isTrue);
      expect(prefs.getBool('kiosk_os_pinning'), isTrue);
    });
  });

  test('a kiosk PIN is exactly four digits', () {
    expect(isValidKioskPin('1234'), isTrue);
    expect(isValidKioskPin('123'), isFalse);
    expect(isValidKioskPin('12345'), isFalse);
    expect(isValidKioskPin('12a4'), isFalse);
  });
}
