import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/review/review_prompt_controller.dart';
import '../../../data/repositories/connection_repo.dart';
import '../../onboarding/demo_service.dart' show isDemoConnection;
import '../../settings/providers/settings_controller.dart'
    show sharedPreferencesProvider;
import '../../support/community.dart';
import 'poll_card.dart' show pollAfterDays, pollDoneKey;

/// "1" once the card was tapped or put away: it is shown only once.
const communityCardDoneKey = 'community_card_done';

/// Days on a connected dashboard before the card is shown: the second day,
/// so a new user hears about the group while setup is fresh (2.6.1).
const communityCardAfterDays = 2;

/// "Join the ZigDash community" (docs/design/support.md, Community): a
/// one-time card on a real Home's dashboard once the app was used on
/// [communityCardAfterDays] days. It steps aside while the usage-data
/// question or the poll card is showing, so the cards never stack. Join
/// opens the Telegram group; Not now puts the card away for good. Nothing
/// is sent but the optional `community_opened` event.
class CommunityCard extends ConsumerStatefulWidget {
  const CommunityCard({super.key, required this.connectionId});

  final String connectionId;

  @override
  ConsumerState<CommunityCard> createState() => _CommunityCardState();
}

class _CommunityCardState extends ConsumerState<CommunityCard> {
  bool _done = false;

  Future<void> _finish() async {
    setState(() => _done = true);
    await ref
        .read(sharedPreferencesProvider)
        .setString(communityCardDoneKey, '1');
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final consent = ref.watch(analyticsConsentProvider);
    final available = ref.watch(analyticsAvailableProvider);
    final host = ref
        .watch(connectionByIdProvider(widget.connectionId))
        .valueOrNull
        ?.host;
    final days = prefs.getInt(ReviewPromptController.kSessions) ?? 0;
    if (_done ||
        prefs.getString(communityCardDoneKey) != null ||
        days < communityCardAfterDays ||
        host == null ||
        isDemoConnection(host) ||
        // The usage-data question and the poll come first; one card at a time.
        (available && consent == AnalyticsConsent.unasked) ||
        (days >= pollAfterDays && prefs.getString(pollDoneKey) == null)) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.forum_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.communityCardTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Text(
                l10n.communityCardBody,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _finish,
                  child: Text(l10n.communityCardNotNow),
                ),
                FilledButton(
                  onPressed: () {
                    _finish();
                    openCommunity(ref, HelpFrom.card);
                  },
                  child: Text(l10n.communityCardJoin),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
