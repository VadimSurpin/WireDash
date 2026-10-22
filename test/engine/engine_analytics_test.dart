import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/core/analytics/analytics_events.dart';

void main() {
  test('engine_setup: step, where from, Zigbee2MQTT as major.minor only', () {
    final e = EngineEvent(EngineStep.consentShown, z2m: '2.14.1-dev', from: EngineFrom.alerts);
    expect(e.name, 'engine_setup');
    expect(e.props, {'step': 'consent_shown', 'from': 'alerts', 'z2m': '2.14'});
    expect(const EngineEvent(EngineStep.offered).props, {'step': 'offered', 'from': 'automations'});
  });

  test('automation_saved: shape only, counts in buckets', () {
    const e = AutomationSaved(
        trigger: 'sun', conditions: 3, action: 'scene', offAfter: true, isNew: true, homeCount: 4);
    expect(e.props, {'trigger': 'sun', 'conditions': '2+', 'action': 'scene', 'off_after': 'yes', 'new': 'yes', 'count': '4-10'});
  });
}
