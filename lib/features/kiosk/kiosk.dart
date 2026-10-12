import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/router/routes.dart';
import '../settings/providers/settings_controller.dart';

/// Kiosk lock (kiosk-2.6.md): one dashboard of one Home is pinned on
/// screen for guests. While it is on, only that Home's dashboards and their
/// controls are reachable; the router sends every other address back. Off
/// when [dashboardId] is null. Stored on this device, so a tablet that
/// reboots comes back in kiosk.
class KioskState {
  const KioskState({
    this.connectionId,
    this.dashboardId,
    this.hasPin = false,
    this.osPinning = false,
  });

  final String? connectionId;
  final String? dashboardId;

  /// A kiosk PIN is set (asked when leaving kiosk).
  final bool hasPin;

  /// Also ask Android to pin the app (screen pinning) while kiosk is on.
  final bool osPinning;

  bool get on => dashboardId != null;

  KioskState copyWith({
    String? connectionId,
    String? dashboardId,
    bool clearDashboard = false,
    bool? hasPin,
    bool? osPinning,
  }) => KioskState(
    connectionId: clearDashboard ? null : connectionId ?? this.connectionId,
    dashboardId: clearDashboard ? null : dashboardId ?? this.dashboardId,
    hasPin: hasPin ?? this.hasPin,
    osPinning: osPinning ?? this.osPinning,
  );
}

/// Where the kiosk PIN lives: the same encrypted store as broker passwords,
/// one PIN per device. A seam so tests need no platform channel.
class KioskPinStore {
  const KioskPinStore(this._storage);
  final FlutterSecureStorage _storage;
  static const _key = 'kiosk_pin';

  Future<String?> read() => _storage.read(key: _key);
  Future<void> write(String pin) => _storage.write(key: _key, value: pin);
  Future<void> delete() => _storage.delete(key: _key);
}

final kioskPinStoreProvider = Provider<KioskPinStore>(
  (_) => const KioskPinStore(
    FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  ),
);

const _kConnection = 'kiosk_connection';
const _kDashboard = 'kiosk_dashboard';
const _kOsPinning = 'kiosk_os_pinning';

class KioskController extends Notifier<KioskState> {
  @override
  KioskState build() {
    // Kiosk is read by the home shell and every tile grid, so widget tests
    // that never touch it need no preferences: no store means kiosk off.
    final SharedPreferences prefs;
    try {
      prefs = ref.read(sharedPreferencesProvider);
    } on UnimplementedError {
      return const KioskState();
    }
    _loadPin();
    return KioskState(
      connectionId: prefs.getString(_kConnection),
      dashboardId: prefs.getString(_kDashboard),
      osPinning: prefs.getBool(_kOsPinning) ?? false,
    );
  }

  Future<void> _loadPin() async {
    try {
      final pin = await ref.read(kioskPinStoreProvider).read();
      state = state.copyWith(hasPin: pin != null);
    } catch (_) {
      // No secure store (tests, a broken keystore): behave as without a PIN.
    }
  }

  Future<void> start(String connectionId, String dashboardId) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_kConnection, connectionId);
    await prefs.setString(_kDashboard, dashboardId);
    state = state.copyWith(
      connectionId: connectionId,
      dashboardId: dashboardId,
    );
  }

  Future<void> stop() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_kConnection);
    await prefs.remove(_kDashboard);
    state = state.copyWith(clearDashboard: true);
  }

  Future<void> setOsPinning(bool on) async {
    await ref.read(sharedPreferencesProvider).setBool(_kOsPinning, on);
    state = state.copyWith(osPinning: on);
  }

  Future<void> setPin(String pin) async {
    await ref.read(kioskPinStoreProvider).write(pin);
    state = state.copyWith(hasPin: true);
  }

  Future<void> clearPin() async {
    await ref.read(kioskPinStoreProvider).delete();
    state = state.copyWith(hasPin: false);
  }

  /// True when [pin] is the stored one, or when none is stored.
  Future<bool> checkPin(String pin) async {
    final stored = await ref.read(kioskPinStoreProvider).read();
    return stored == null || stored == pin;
  }
}

final kioskProvider = NotifierProvider<KioskController, KioskState>(
  KioskController.new,
);

/// The dashboards address kiosk keeps the app on, or null when off.
String? kioskHome(KioskState kiosk) =>
    kiosk.on ? Routes.homeDashboards(kiosk.connectionId!) : null;

/// Router redirect for kiosk: while it is on, every address other than the
/// pinned Home's dashboards (exactly that page, not its form, edit or add
/// sub-pages) goes back there. Back presses, notification taps and widget
/// deep links all pass through here, so none of them can leave.
String? kioskRedirect({required KioskState kiosk, required String location}) {
  final home = kioskHome(kiosk);
  if (home == null || location == home) return null;
  return home;
}

/// A valid kiosk PIN: exactly four digits.
bool isValidKioskPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);
