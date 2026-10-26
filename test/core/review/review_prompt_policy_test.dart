import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/core/review/review_prompt_policy.dart';

void main() {
  const policy = ReviewPromptPolicy();
  final day0 = DateTime(2026, 9, 1);

  test('never prompts before the first session is recorded', () {
    expect(
      policy.shouldPrompt(
        sessions: 10,
        firstSessionDay: null,
        lastPromptDay: null,
        today: day0,
      ),
      isFalse,
    );
  });

  test('needs minSessions distinct sessions (two)', () {
    expect(
      policy.shouldPrompt(
        sessions: 1,
        firstSessionDay: day0,
        lastPromptDay: null,
        today: day0.add(const Duration(days: 30)),
      ),
      isFalse,
    );
    expect(
      policy.shouldPrompt(
        sessions: 2,
        firstSessionDay: day0,
        lastPromptDay: null,
        today: day0.add(const Duration(days: 30)),
      ),
      isTrue,
    );
  });

  test(
    'needs minAge (a day) since the first session even with enough sessions',
    () {
      expect(
        policy.shouldPrompt(
          sessions: 2,
          firstSessionDay: day0,
          lastPromptDay: null,
          today: day0,
        ),
        isFalse,
      );
      expect(
        policy.shouldPrompt(
          sessions: 2,
          firstSessionDay: day0,
          lastPromptDay: null,
          today: day0.add(const Duration(days: 1)),
        ),
        isTrue,
      );
    },
  );

  test('respects the cooldown after a prompt', () {
    final prompted = day0.add(const Duration(days: 10));
    expect(
      policy.shouldPrompt(
        sessions: 20,
        firstSessionDay: day0,
        lastPromptDay: prompted,
        today: prompted.add(const Duration(days: 89)),
      ),
      isFalse,
    );
    expect(
      policy.shouldPrompt(
        sessions: 20,
        firstSessionDay: day0,
        lastPromptDay: prompted,
        today: prompted.add(const Duration(days: 90)),
      ),
      isTrue,
    );
  });
}
