/// Decides whether the in-app review dialog may be requested.
///
/// Pure and clock-free so it can be unit-tested exhaustively. All inputs are
/// at calendar-day granularity; nothing finer is ever stored (see
/// [ReviewPromptController]).
class ReviewPromptPolicy {
  const ReviewPromptPolicy({
    this.minSessions = 2,
    this.minAge = const Duration(days: 1),
    this.cooldown = const Duration(days: 90),
  });

  /// Distinct days on which a command the user sent was confirmed by the
  /// device before we ask. One day proves the setup works; coming back on a
  /// second day proves they kept it. Was four days (2026-09 to 2026-10),
  /// which produced no visible rating in three weeks of production.
  final int minSessions;

  /// Minimum time since the first successful session. With [minSessions] at
  /// two this only rules out a same-day double count across midnight.
  final Duration minAge;

  /// Minimum gap between review requests. Google gives no signal whether the
  /// dialog was shown, so every request counts against the cooldown.
  final Duration cooldown;

  bool shouldPrompt({
    required int sessions,
    required DateTime? firstSessionDay,
    required DateTime? lastPromptDay,
    required DateTime today,
  }) {
    if (firstSessionDay == null || sessions < minSessions) return false;
    if (today.difference(firstSessionDay) < minAge) return false;
    if (lastPromptDay != null && today.difference(lastPromptDay) < cooldown) {
      return false;
    }
    return true;
  }
}
