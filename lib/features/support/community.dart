import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/analytics/analytics.dart';

/// The ZigDash Telegram group (docs/design/support.md, Community): where
/// users ask, suggest and hear what's coming. Public, so the link is open.
final communityUrl = Uri.parse('https://t.me/zigdash_app');

/// Opens a link outside the app; replaced in tests.
@visibleForTesting
Future<bool> Function(Uri url) openCommunityLink =
    (url) => launchUrl(url, mode: LaunchMode.externalApplication);

/// Opens the community group and records where it was opened from.
Future<void> openCommunity(WidgetRef ref, HelpFrom from) async {
  ref.read(analyticsProvider).track(CommunityOpened(from));
  try {
    await openCommunityLink(communityUrl);
  } catch (_) {}
}
