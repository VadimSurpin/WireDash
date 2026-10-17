import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../settings/providers/settings_controller.dart';
import '../../core/analytics/analytics.dart';
import '../kiosk/kiosk.dart';
import '../pro/pro.dart';
import 'widgets/wall_alarm_screen.dart';
import 'widgets/wall_idle_screen.dart';
import '../../data/repositories/dashboard_repo.dart';
import '../devices/devices_providers.dart';
import '../discovery/providers/discovery_provider.dart';
import 'wall_sensors.dart';

/// The screen as Wall display and kiosk drive it; a seam so tests need no
/// platform channel. Every call is best effort and never throws.
class ScreenWake {
  const ScreenWake();

  static const _channel = MethodChannel('zigdash/app');

  /// Keeps the screen on.
  Future<void> keepOn(bool on) => WakelockPlus.toggle(enable: on);

  /// Hides Android's status and navigation bars (a swipe from the edge shows
  /// them briefly); off restores the app's usual edge-to-edge chrome.
  Future<void> fullscreen(bool on) => SystemChrome.setEnabledSystemUIMode(
    on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
  );

  /// Dims this window to [dimBrightness]; off returns to the system's.
  Future<void> dim(bool on) async {
    try {
      await _channel.invokeMethod<void>('setBrightness', {
        'value': on ? dimBrightness : -1.0,
      });
    } on PlatformException catch (_) {
      // No window to dim (tests, web).
    } on MissingPluginException catch (_) {}
  }

  /// This window's brightness, 0 to 1; null returns to the system's.
  Future<void> brightness(double? value) async {
    try {
      await _channel.invokeMethod<void>('setBrightness', {
        'value': value ?? -1.0,
      });
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }

  /// The phone's alarm tone, looping while [on] (alarm takeover).
  Future<void> alarmSound(bool on) async {
    try {
      await _channel.invokeMethod<void>('alarmSound', {'on': on});
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }

  /// Android screen pinning. False when Android refused.
  Future<bool> lockTask(bool on) async {
    try {
      return await _channel.invokeMethod<bool>('lockTask', {'on': on}) ?? false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }
}

/// How dark a dimmed wall display is (0 to 1 of the window's brightness).
const dimBrightness = 0.1;

final screenWakeProvider = Provider<ScreenWake>((_) => const ScreenWake());

/// "Wall display" for one dashboard (signal-2.0.md §7): keep the screen on
/// and hide the bars. Off by default, stored on this phone per dashboard.
class WallDisplaySetting extends FamilyNotifier<bool, String> {
  String get _key => 'wall_display_$arg';

  @override
  bool build(String arg) =>
      ref.read(sharedPreferencesProvider).getBool(_key) ?? false;

  Future<void> toggle() => set(!state);

  Future<void> set(bool on) async {
    state = on;
    if (on) {
      ref.read(analyticsProvider).track(const FeatureUsed(Feature.wallDisplay));
    }
    await ref.read(sharedPreferencesProvider).setBool(_key, on);
  }
}

final wallDisplayProvider =
    NotifierProvider.family<WallDisplaySetting, bool, String>(
      WallDisplaySetting.new,
    );

/// Fullscreen for one dashboard (kiosk-2.6.md): Android's bars hide too
/// while Wall display or kiosk is on. Off until set; turning the kiosk lock
/// on sets it unless the user already chose.
class WallFullscreenSetting extends FamilyNotifier<bool, String> {
  String get _key => 'wall_fullscreen_$arg';

  @override
  bool build(String arg) =>
      ref.read(sharedPreferencesProvider).getBool(_key) ?? false;

  bool get chosen => ref.read(sharedPreferencesProvider).containsKey(_key);

  Future<void> set(bool on) async {
    state = on;
    await ref.read(sharedPreferencesProvider).setBool(_key, on);
  }
}

final wallFullscreenProvider =
    NotifierProvider.family<WallFullscreenSetting, bool, String>(
      WallFullscreenSetting.new,
    );

/// Minutes without a touch before the screen dims; 0 is off.
const wallDimChoices = [0, 1, 5, 15];

/// The dim delay for one dashboard (kiosk-2.6.md), in minutes, 0 for off.
class WallDimSetting extends FamilyNotifier<int, String> {
  String get _key => 'wall_dim_$arg';

  @override
  int build(String arg) =>
      ref.read(sharedPreferencesProvider).getInt(_key) ?? 0;

  bool get chosen => ref.read(sharedPreferencesProvider).containsKey(_key);

  Future<void> set(int minutes) async {
    state = minutes;
    await ref.read(sharedPreferencesProvider).setInt(_key, minutes);
  }
}

final wallDimProvider = NotifierProvider.family<WallDimSetting, int, String>(
  WallDimSetting.new,
);

/// What an idle wall display shows once [WallDimSetting]'s minutes pass
/// (wall-tablet-2.9.md §2): the dimmed dashboard (2.6's behaviour, the
/// default), a clock, the clock with readings (Pro), or black.
enum WallIdleShow { dim, clock, readings, black }

/// The idle screen for one dashboard, stored on this tablet.
class WallIdleShowSetting extends FamilyNotifier<WallIdleShow, String> {
  String get _key => 'wall_idle_show_$arg';

  @override
  WallIdleShow build(String arg) {
    final name = ref.read(sharedPreferencesProvider).getString(_key);
    return WallIdleShow.values.firstWhere(
      (s) => s.name == name,
      orElse: () => WallIdleShow.dim,
    );
  }

  Future<void> set(WallIdleShow show) async {
    state = show;
    await ref.read(sharedPreferencesProvider).setString(_key, show.name);
  }
}

final wallIdleShowProvider =
    NotifierProvider.family<WallIdleShowSetting, WallIdleShow, String>(
      WallIdleShowSetting.new,
    );

/// True while a wall-display dashboard has had no touch for [wallChromeDelay]:
/// the header and the navigation hide until the screen is touched.
final wallChromeHiddenProvider = StateProvider<bool>((_) => false);

const wallChromeDelay = Duration(seconds: 10);

/// Applies Wall display and kiosk to the dashboard on screen: keeps the
/// screen on and hides the chrome after [wallChromeDelay] without a touch
/// (Wall display), hides Android's bars (Fullscreen) and dims after the
/// chosen minutes (Dim) while either is on, and asks Android to pin the app
/// while kiosk is on with OS pinning chosen. [active] is false in Edit mode,
/// which never hides anything.
class WallDisplayScope extends ConsumerStatefulWidget {
  const WallDisplayScope({
    super.key,
    required this.dashboardId,
    required this.active,
    required this.child,
  });

  final String dashboardId;
  final bool active;
  final Widget child;

  @override
  ConsumerState<WallDisplayScope> createState() => _WallDisplayScopeState();
}

class _WallDisplayScopeState extends ConsumerState<WallDisplayScope> {
  Timer? _timer;
  Timer? _dimTimer;
  bool _wakeOn = false;
  bool _fullscreenOn = false;
  bool _dimmed = false;
  bool _pinned = false;

  /// What the idle screen shows over the dashboard, or null while awake.
  WallIdleShow? _idle;

  /// Alarm takeover's alarms (wall-tablet-2.9.md §6).
  final _alarms = WallAlarmTracker();
  bool _sounding = false;

  /// Friendly name to display name, for the alarm screen.
  Map<String, String> _names = const {};

  /// Kiosk is app-wide: swiping to a sibling dashboard stays in it, with
  /// the kiosk dashboard's Wall display settings governing the whole time.
  bool get _kiosk => widget.active && ref.read(kioskProvider).on;

  String get _settingsId =>
      ref.read(kioskProvider).dashboardId ?? widget.dashboardId;

  bool get _wall => widget.active && ref.read(wallDisplayProvider(_settingsId));

  /// Fullscreen and Dim apply to a wall display and to a kiosk alike.
  bool get _ambient => _wall || _kiosk;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _apply());
  }

  @override
  void didUpdateWidget(WallDisplayScope old) {
    super.didUpdateWidget(old);
    if (old.dashboardId != widget.dashboardId || old.active != widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _apply());
    }
  }

  void _apply() {
    if (!mounted) return;
    final screen = ref.read(screenWakeProvider);
    final wake = _wall;
    if (wake != _wakeOn) {
      _wakeOn = wake;
      screen.keepOn(wake).ignore();
    }
    final fullscreen =
        _ambient && ref.read(wallFullscreenProvider(_settingsId));
    if (fullscreen != _fullscreenOn) {
      _fullscreenOn = fullscreen;
      screen.fullscreen(fullscreen).ignore();
    }
    final kiosk = ref.read(kioskProvider);
    final pin = _kiosk && kiosk.osPinning;
    if (pin != _pinned) {
      _pinned = pin;
      screen.lockTask(pin).ignore();
    }
    _touched();
  }

  /// The night schedule is on and it is night now (Pro).
  bool get _night {
    final night = ref.read(wallNightProvider(_settingsId));
    return night.on &&
        ref.read(proStatusProvider) == ProStatus.unlocked &&
        isNightAt(ref.read(wallNowProvider)(), night.from, night.to);
  }

  /// Motion at night: awake, but only dimly (wall-tablet-2.9.md §5).
  void _wokenByMotion() {
    _touched();
    if (_night && _alarms.showing.isEmpty) {
      _dimmed = true;
      ref.read(screenWakeProvider).brightness(nightWakeBrightness).ignore();
    }
  }

  /// Shows the chrome and undims; on a wall display, hides the chrome again
  /// after a while, and dims again after the chosen minutes.
  void _touched() {
    _timer?.cancel();
    _dimTimer?.cancel();
    final hidden = ref.read(wallChromeHiddenProvider.notifier);
    if (hidden.state) hidden.state = false;
    if (_dimmed) {
      _dimmed = false;
      ref.read(screenWakeProvider).dim(false).ignore();
    }
    if (_idle != null) setState(() => _idle = null);
    if (_wall) {
      _timer = Timer(wallChromeDelay, () {
        if (mounted && _wall) {
          ref.read(wallChromeHiddenProvider.notifier).state = true;
        }
      });
    }
    var minutes = _ambient ? ref.read(wallDimProvider(_settingsId)) : 0;
    // At night the screen goes black even when the day setting is Never.
    if (_ambient && minutes == 0 && _night) minutes = 1;
    if (minutes > 0) {
      _dimTimer = Timer(Duration(minutes: minutes), () {
        if (!mounted || !_ambient) return;
        // An alarm on screen stays bright until OK.
        if (_alarms.showing.isNotEmpty) return;
        _dimmed = true;
        ref.read(screenWakeProvider).dim(true).ignore();
        var show = ref.read(wallIdleShowProvider(_settingsId));
        // Readings are Pro (wall-tablet-2.9.md §7); without it, the clock.
        if (show == WallIdleShow.readings &&
            ref.read(proStatusProvider) != ProStatus.unlocked) {
          show = WallIdleShow.clock;
        }
        if (_night) show = WallIdleShow.black;
        if (show != WallIdleShow.dim) setState(() => _idle = show);
      });
    }
  }

  /// A state message from the Home: a picked sensor seeing someone wakes
  /// the screen as a touch does; an alarm takes it over.
  void _onState(WallStateEvent e, Set<String> wakers, bool alarmsOn) {
    if (!mounted) return;
    if (wakers.contains(e.name) && wakesFor(e.state)) _wokenByMotion();
    if (alarmsOn && _alarms.update(e.name, e.state)) {
      setState(() {});
      ref
          .read(analyticsProvider)
          .track(AlarmShown(_alarms.showing.last.kind.name));
      _touched();
      final sound = ref.read(wallAlarmProvider(_settingsId)).sound;
      if (sound && !_sounding) {
        _sounding = true;
        ref.read(screenWakeProvider).alarmSound(true).ignore();
      }
    }
  }

  void _acknowledge() {
    setState(_alarms.acknowledge);
    if (_alarms.showing.isEmpty && _sounding) {
      _sounding = false;
      ref.read(screenWakeProvider).alarmSound(false).ignore();
    }
  }

  /// For [dispose], where `ref` can no longer be used.
  late ProviderContainer _container;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context, listen: false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dimTimer?.cancel();
    final container = _container;
    final screen = container.read(screenWakeProvider);
    if (_wakeOn) screen.keepOn(false).ignore();
    if (_fullscreenOn) screen.fullscreen(false).ignore();
    if (_dimmed) screen.dim(false).ignore();
    if (_pinned) screen.lockTask(false).ignore();
    if (_sounding) screen.alarmSound(false).ignore();
    // Leaving the dashboard brings the chrome back for the other screens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        container.read(wallChromeHiddenProvider.notifier).state = false;
      } on StateError {
        // The whole scope is gone (app closing): nothing to restore.
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(wallDisplayProvider(widget.dashboardId), (_, __) => _apply());
    ref.listen(wallFullscreenProvider(widget.dashboardId), (_, __) => _apply());
    ref.listen(wallDimProvider(widget.dashboardId), (_, __) => _apply());
    ref.listen(wallIdleShowProvider(widget.dashboardId), (_, __) => _apply());
    ref.listen(wallNightProvider(widget.dashboardId), (_, __) => _apply());
    ref.listen(kioskProvider, (_, __) => _apply());
    _listenToSensors();
    final idle = _idle;
    final alarm = _alarms.showing.firstOrNull;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _touched(),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          // The touch that wakes the screen lands here, not on a tile.
          if (idle != null)
            Positioned.fill(
              child: WallIdleScreen(show: idle, dashboardId: _settingsId),
            ),
          if (alarm != null)
            Positioned.fill(
              child: WallAlarmScreen(
                kind: alarm.kind,
                deviceName: _names[alarm.name] ?? alarm.name,
                onOk: _acknowledge,
              ),
            ),
        ],
      ),
    );
  }

  /// Wake on motion and alarm takeover listen to the Home's devices while a
  /// wall display or kiosk is on, with Pro (wall-tablet-2.9.md §4, §6, §7).
  void _listenToSensors() {
    final id = ref.watch(kioskProvider).dashboardId ?? widget.dashboardId;
    final ambient =
        widget.active &&
        (ref.watch(wallDisplayProvider(id)) || ref.watch(kioskProvider).on);
    if (!ambient || ref.watch(proStatusProvider) != ProStatus.unlocked) return;
    final motion = ref.watch(wallMotionSensorsProvider(id));
    final alarmsOn = ref.watch(wallAlarmProvider(id)).on;
    if (motion.isEmpty && !alarmsOn) return;
    final connectionId = ref
        .watch(dashboardByIdProvider(id))
        .valueOrNull
        ?.connectionId;
    if (connectionId == null) return;
    final base = ref.watch(homeBaseTopicProvider(connectionId));
    if (base == null) return;
    final devices =
        ref
            .watch(
              bridgeDevicesStreamProvider((
                connectionId: connectionId,
                base: base,
              )),
            )
            .valueOrNull ??
        const [];
    _names = {for (final d in devices) d.friendlyName: d.displayName};
    final wakers = {
      for (final d in devices)
        if (motion.contains(d.ieeeAddress)) d.friendlyName,
    };
    ref.listen(
      wallStateEventsProvider((connectionId: connectionId, base: base)),
      (_, next) {
        final e = next.valueOrNull;
        if (e != null) _onState(e, wakers, alarmsOn);
      },
    );
  }
}
