import 'package:flutter/material.dart';
import 'package:zigdash/l10n/app_localizations.dart';
import 'package:zigdash/features/panels/widgets/device_panel_display_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/data/database/tables/panels.dart';
import 'package:zigdash/features/devices/device_profile.dart';
import 'package:zigdash/features/discovery/models/wirenboard_device.dart';
import 'package:zigdash/features/panels/models/panel_config.dart';

void main() {
  testWidgets('reset restores default visibility and removes panel-specific labels', (tester) async {
    DevicePanelDisplay? saved;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: DevicePanelDisplayEditor(
        properties: const [(id:'K1',label:'Relay 1'), (id:'K2',label:'Relay 2')],
        defaults: const ['K1','K2'],
        value: const DevicePanelDisplay(properties:['K1'],labels:{'K1':'Kitchen'}),
        onChanged: (value) => saved=value,
      )),
    ));
    expect(tester.widget<Checkbox>(find.byKey(const ValueKey('display-property:K2'))).value, isFalse);
    await tester.tap(find.text('Reset card contents and labels'));
    await tester.pumpAndSettle();
    expect(saved!.isDefault, isTrue);
    expect(tester.widget<Checkbox>(find.byKey(const ValueKey('display-property:K2'))).value, isTrue);
    expect(tester.widget<TextFormField>(find.byKey(const ValueKey('display-label:1:K1'))).initialValue, '');
  });

  test(
    'WB display overrides round-trip independently of legacy subsets and metadata',
    () {
      final device =
          (WirenBoardDiscovery()
                ..apply('/devices/relay/controls/K1/meta', '{"type":"switch"}'))
              .devices
              .single;
      const display = DevicePanelDisplay(
        properties: ['K1'],
        labels: {'K1': 'Kitchen'},
      );
      final config = WirenBoardDeviceConfig(device: device, display: display);
      final decoded =
          PanelConfig.decode(PanelType.device, config.encode())
              as WirenBoardDeviceConfig;
      expect(decoded.display.properties, ['K1']);
      expect(decoded.display.labels, {'K1': 'Kitchen'});
      expect(decoded.controlIds, isNull);
      expect(decoded.device.controls.single.title('en'), 'K1');
      final legacy = WirenBoardDeviceConfig(device: device, controlIds: ['K1']);
      expect(
        (PanelConfig.decode(PanelType.device, legacy.encode())
                as WirenBoardDeviceConfig)
            .display
            .isDefault,
        isTrue,
      );
    },
  );

  test(
    'native device labels and empty card selection survive config serialization',
    () {
      final profile = classifyExposes([
        {
          'type': 'binary',
          'property': 'state_l1',
          'name': 'state',
          'label': 'Relay 1',
          'access': 3,
        },
      ]);
      final config = DeviceTileConfig(
        profile: profile,
        display: const DevicePanelDisplay(
          properties: [],
          labels: {'state_l1': 'Desk'},
        ),
      );
      final decoded =
          PanelConfig.decode(PanelType.device, config.encode())
              as DeviceTileConfig;
      expect(decoded.display.properties, isEmpty);
      expect(decoded.display.labels, {'state_l1': 'Desk'});
      expect(decoded.profile.features.single.label, 'Relay 1');
      expect(
        DeviceTileConfig(profile: profile).toJson().containsKey('display'),
        isFalse,
      );
    },
  );
}
