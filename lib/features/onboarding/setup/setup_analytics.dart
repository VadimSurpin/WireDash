import '../../../core/analytics/analytics_events.dart';
import 'setup_coordinator.dart';

/// The `setup_step` event for a setup state change, or null when the change
/// is not a step (more candidates arriving, say). Recorded only with
/// consent (ADR 0006). [platform] is the user's answer so far; an empty scan
/// also reports what it saw (2.5).
SetupStep? setupStepFor(
  SetupState? previous,
  SetupState next, {
  SetupPlatform? platform,
}) => switch (next) {
  SetupScanning() when previous is! SetupScanning => const SetupStep(
    SetupStepKind.started,
  ),
  SetupVerifying() when previous is SetupScanning => SetupStep(
    SetupStepKind.scanFound,
    platform: platform,
  ),
  SetupScanEmpty(:final tried, :final deviceIp) => SetupStep(
    SetupStepKind.scanEmpty,
    platform: next.platform ?? platform,
    hub: next.hub?.kind,
    hostsTried: tried?.hostsTried,
    widened: tried?.widened,
    subnet: subnetShape(deviceIp),
  ),
  SetupNeedsAuth(:final rejected) => SetupStep(
    rejected ? SetupStepKind.loginRejected : SetupStepKind.needsLogin,
  ),
  SetupFailed(:final kind) => SetupStep(SetupStepKind.failed, error: kind),
  SetupReview(:final rows) when previous is! SetupReview => SetupStep(
    SetupStepKind.review,
    devices: rows.length,
    platform: platform,
  ),
  SetupComplete(:final result) => SetupStep(
    SetupStepKind.complete,
    devices: result.panelCount,
    platform: platform,
  ),
  _ => null,
};

/// The private range the phone's address is in, never the address itself.
String? subnetShape(String? ip) {
  if (ip == null) return null;
  final parts = ip.split('.');
  if (parts.length != 4) return 'other';
  final a = int.tryParse(parts[0]), b = int.tryParse(parts[1]);
  if (a == 192 && b == 168) return '192.168';
  if (a == 10) return '10';
  if (a == 172 && b != null && b >= 16 && b <= 31) return '172.16';
  return 'other';
}
