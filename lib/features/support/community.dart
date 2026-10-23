import 'help_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/l10n_ext.dart';

/// The ZigDash Telegram group (docs/design/support.md, Community): where
/// users ask, suggest and hear what's coming. Public, so the link is open.
final communityUrl = Uri.parse('https://t.me/zigdash_app');

/// Opens a link outside the app; replaced in tests.
@visibleForTesting
Future<bool> Function(Uri url) openCommunityLink = (url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// Opens the community group and records where it was opened from.
Future<void> openCommunity(WidgetRef ref, HelpFrom from) async {
  try {
    await openCommunityLink(communityUrl);
  } catch (_) {}
}

/// "Ask in the Telegram group", the quiet link beside Get help on a screen
/// where setup is stuck (support.md, Community): a stuck user can ask in
/// public right there instead of writing to the developer first.
class CommunityLink extends ConsumerWidget {
  const CommunityLink({super.key, required this.from});

  final HelpFrom from;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton.icon(
    onPressed: () => openCommunity(ref, from),
    icon: const Icon(Icons.forum_outlined, size: 18),
    label: Text(context.l10n.getHelpCommunity),
  );
}
