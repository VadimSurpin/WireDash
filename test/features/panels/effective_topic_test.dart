import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/features/panels/providers/panel_value_provider.dart';

void main() {
  test('a full WB topic keeps its leading slash without a prefix', () {
    const state = '/devices/wb-mr6c_1/controls/K1';
    for (final prefix in [null, '']) {
      expect(composeTopic(prefix, state), state);
      expect(composeTopic(prefix, '$state/on'), '$state/on');
    }
  });

  group('effectiveSubscribeTopic', () {
    test('override wins over dashboard prefix', () {
      expect(
        effectiveSubscribeTopic(
          dashboardPrefix: 'zigbee2mqtt',
          prefixOverride: 'zigbee2mqtt/shutter',
          subscribeSuffix: '',
        ),
        'zigbee2mqtt/shutter',
      );
    });

    test('blank override falls back to dashboard prefix', () {
      expect(
        effectiveSubscribeTopic(
          dashboardPrefix: 'zigbee2mqtt',
          prefixOverride: '   ',
          subscribeSuffix: '',
        ),
        'zigbee2mqtt',
      );
    });

    test('empty suffix collapses to just the prefix', () {
      expect(
        effectiveSubscribeTopic(
          dashboardPrefix: 'zigbee2mqtt/lamp',
          prefixOverride: '',
          subscribeSuffix: '',
        ),
        'zigbee2mqtt/lamp',
      );
    });

    test('non-empty suffix is appended with slash', () {
      expect(
        effectiveSubscribeTopic(
          dashboardPrefix: 'zigbee2mqtt/lamp',
          prefixOverride: '',
          subscribeSuffix: 'availability',
        ),
        'zigbee2mqtt/lamp/availability',
      );
    });

    test('leading-slash suffix is trimmed (composeTopic contract)', () {
      expect(
        effectiveSubscribeTopic(
          dashboardPrefix: 'zigbee2mqtt/lamp',
          prefixOverride: '',
          subscribeSuffix: '/availability',
        ),
        'zigbee2mqtt/lamp/availability',
      );
    });

    test('override with non-empty suffix', () {
      expect(
        effectiveSubscribeTopic(
          dashboardPrefix: 'zigbee2mqtt',
          prefixOverride: 'zigbee2mqtt/shutter',
          subscribeSuffix: 'set',
        ),
        'zigbee2mqtt/shutter/set',
      );
    });
  });
}
