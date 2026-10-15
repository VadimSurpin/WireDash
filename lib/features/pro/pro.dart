import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ZigDash Pro (docs/design/history-2.7.md): a one-time purchase on Google
/// Play that unlocks depth features, starting with the 7- and 30-day
/// history views.
enum ProStatus {
  /// Everything is open: a build outside Play, or Pro was bought.
  unlocked,

  /// Pro can be bought and isn't yet: Pro views show the locked sample.
  locked,

  /// Pro isn't offered in this build yet: Pro views are hidden entirely,
  /// so nobody is shown something they can't get.
  unavailable,
}

/// Which build this is: `foss` (GitHub, IzzyOnDroid, F-Droid: no billing,
/// everything unlocked) or `play`. Set by tool/build_release.sh.
const proFlavor = String.fromEnvironment(
  'ZIGDASH_FLAVOR',
  defaultValue: 'foss',
);

/// Whether the Play build offers Pro yet (the payments profile and the
/// product exist). Until then Pro views are hidden in the Play build.
const proLive = bool.fromEnvironment('ZIGDASH_PRO_LIVE');

/// This build's Pro status. The Play build's purchase state is wired in with
/// billing; until then a Play build without [proLive] is [ProStatus.unavailable].
final proStatusProvider = Provider<ProStatus>((ref) {
  if (proFlavor != 'play') return ProStatus.unlocked;
  if (!proLive) return ProStatus.unavailable;
  return ProStatus.locked;
});

/// Starts buying Pro; null when this build can't (outside Play, or before
/// billing is live), which disables Unlock.
final proPurchaseProvider = Provider<VoidCallback?>((ref) => null);
