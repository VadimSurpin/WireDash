import 'help_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/l10n_ext.dart';
import 'project_links.dart';

/// WireDash's repository, with documentation and public issues.
final communityUrl = Uri.parse(projectUrl);

/// Opens a link outside the app; replaced in tests.
@visibleForTesting
Future<bool> Function(Uri url) openCommunityLink = (url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// Opens the project only after an explicit user action.
Future<void> openCommunity(WidgetRef ref, HelpFrom from) async {
  try {
    await openCommunityLink(communityUrl);
  } catch (_) {}
}

/// A manual link to the WireDash project beside troubleshooting actions.
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
