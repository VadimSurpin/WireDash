# Usage data is on by default, with the choice still shown first

From 2.5 the usage-data box on the first setup screen is ticked. A new install that moves past that screen without unticking it sends the anonymous events listed in the privacy policy. Everything else in [ADR 0006](0006-opt-in-anonymous-analytics.md) stands: the fixed list of events and property values, no identifiers, turning it off is immediate and deletes unsent events, builds without an analytics key contain no analytics, and the rules are public.

## Why

ADR 0006 chose off-by-default a week before this, and the week answered the question it left open: whether an opt-in sample is enough to steer setup. Play Console shows about ten installs a day and a daily active count far below that; Aptabase sees about one new install a day. Nine in ten new users never appear, and the one who does is not necessarily the one who got stuck. The setup funnel is the first thing the data is for, and a tenth of it is too small to read: three stalled installs in two days was the whole sample behind the 2.5 setup help.

## What stays visible

- The question is still asked before anything is sent: the box sits on the first screen, next to "What's shared", and nothing is queued until the user moves on.
- People who installed before 2.0 keep the dashboard card with its two buttons, and send nothing until they answer. A choice already made, either way, is kept.
- The switch in Settings › About reads the same and turns it off in one tap.
- The privacy policy, the README, the user guide and the Play listing say "unless you opt out" instead of "only if you opt in".

## Considered

- **Stay opt-in and wait for volume.** Rejected: at one opted-in install a day, a change to setup takes months to measure, and the people it is for are the ones least likely to tick a box on a screen that is already failing them.
- **On with no question at all.** Rejected: the box costs nothing and keeps the promise that the user saw the choice before the first event left the phone.
- **Treat an unanswered upgrade card as yes.** Rejected: those users were promised "off until you say yes" when they installed.

Aptabase's position is that these events carry no personal data (no identifier is sent; the server derives a daily-rotating visitor hash from IP and user agent and does not store the IP), so no consent is required to send them. ZigDash still shows the choice first because its users read privacy policies.

Decided 2026-10-12.
