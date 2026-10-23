import 'package:flutter/painting.dart';

/// Signal design tokens (docs/design/tokens.md, signal-2.0.md §1). The only
/// place colours, radii and type families are written as literals.
abstract final class SignalPalette {
  // Light
  static const groundLight = Color(0xFFF5F8F1);
  static const tileLight = Color(0xFFFFFFFF);
  static const hairlineLight = Color(0xFFDEE6D6);
  static const inkLight = Color(0xFF182312);
  static const inkVariantLight = Color(0xFF4C5B43);
  static const accentLight = Color(0xFF5CB400);
  static const raisedLight = Color(0xFFEAF0E3);

  // Dark
  static const groundDark = Color(0xFF11170E);
  static const tileDark = Color(0xFF1B2416);
  static const hairlineDark = Color(0xFF2E3B25);
  static const inkDark = Color(0xFFEAF0E3);
  static const inkVariantDark = Color(0xFFA4B39A);
  static const accentDark = Color(0xFF84CE36);
  static const raisedDark = Color(0xFF26331F);

  /// Dark ink on the Wiren Board green active fill, in both themes.
  static const onAccent = Color(0xFF182312);

  /// A darker brand green for readable buttons and links on light surfaces.
  static const primaryLight = Color(0xFF3D7800);
  static const onPrimaryLight = Color(0xFFFFFFFF);

  // State roles (containers and their content)
  static const staleLight = Color(0xFFEDF2E7);
  static const staleDark = Color(0xFF172012);
  static const attentionLight = Color(0xFFFDE3D4);
  static const onAttentionLight = Color(0xFF9A3412);
  static const attentionDark = Color(0xFF3A2016);
  static const onAttentionDark = Color(0xFFFFB38A);
  static const healthyLight = Color(0xFFDFF1E6);
  static const onHealthyLight = Color(0xFF1F6F43);
  static const healthyDark = Color(0xFF1E3326);
  static const onHealthyDark = Color(0xFF8FD6A8);
  static const offlineLight = Color(0xFF5E6C55);
  static const offlineDark = Color(0xFF98A78D);
}

/// Corner radii (tokens.md, Shape).
abstract final class SignalRadii {
  static const tile = 28.0;
  static const quickAction = 18.0;
  static const chip = 12.0;
  static const sheet = 28.0;
  static const button = 20.0;
  static const navIndicator = 12.0;
}

/// Font families bundled in assets/fonts (tool/fonts/build_fonts.py).
abstract final class SignalFonts {
  static const display = 'SpaceGrotesk';
  static const body = 'IBMPlexSans';
  static const hebrew = 'IBMPlexSansHebrew';
  static const symbols = 'MaterialSymbolsRounded';

  /// Anything outside the Latin subsets: Hebrew from Plex Hebrew, then the
  /// platform font (Cyrillic device names, emoji).
  static const fallback = [hebrew];
}

/// Spacing by window class: compact, medium, expanded.
abstract final class SignalSpacing {
  static const margin = [16.0, 24.0, 36.0];
  static const tileGap = [10.0, 12.0, 16.0];
  static const quickAction = [48.0, 56.0, 64.0];
}
