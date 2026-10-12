import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../settings/providers/settings_controller.dart';
import '../../core/analytics/analytics.dart';
import '../kiosk/kiosk.dart';

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

  bool get _wall =>
      widget.active && ref.read(wallDisplayProvider(widget.dashboardId));

  bool get _kiosk =>
      widget.active &&
      ref.read(kioskProvider).dashboardId == widget.dashboardId;

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
        _ambient && ref.read(wallFullscreenProvider(widget.dashboardId));
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
    if (_wall) {
      _timer = Timer(wallChromeDelay, () {
        if (mounted && _wall) {
          ref.read(wallChromeHiddenProvider.notifier).state = true;
        }
      });
    }
    final minutes = _ambient
        ? ref.read(wallDimProvider(widget.dashboardId))
        : 0;
    if (minutes > 0) {
      _dimTimer = Timer(Duration(minutes: minutes), () {
        if (!mounted || !_ambient) return;
        _dimmed = true;
        ref.read(screenWakeProvider).dim(true).ignore();
      });
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
    ref.listen(kioskProvider, (_, __) => _apply());
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _touched(),
      child: widget.child,
    );
  }
}
