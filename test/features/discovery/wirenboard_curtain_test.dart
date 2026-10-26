import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/data/database/tables/panels.dart';
import 'package:wiredash/features/discovery/models/wirenboard_curtain.dart';
import 'package:wiredash/features/discovery/models/wirenboard_device.dart';
import 'package:wiredash/features/discovery/models/wirenboard_panel_suggestion.dart';
import 'package:wiredash/features/panels/models/panel_config.dart';

void main() {
  WirenBoardDevice device({bool complete = true, bool readOnly = false}) =>
      (WirenBoardDiscovery()
            ..apply(
              '/devices/relay/controls/Curtain 1 Open/meta',
              '{"type":"switch"}',
            )
            ..apply(
              '/devices/relay/controls/${complete ? 'Curtain 1 Close' : 'K2'}/meta',
              '{"type":"switch","readonly":$readOnly}',
            ))
          .devices
          .single;

  test(
    'complete writable pairs offer a cover using dedicated curtain topics',
    () {
      final d = device();
      for (final control in d.controls) {
        final suggestion = suggestWirenBoardPanel(d, control);
        expect(suggestion.type, PanelType.cover);
        final cfg = suggestion.config! as CoverConfig;
        expect(
          cfg.wirenBoard!.openTopic,
          '/devices/relay/controls/Curtain 1 Open',
        );
        expect(
          cfg.wirenBoard!.closeTopic,
          '/devices/relay/controls/Curtain 1 Close',
        );
        expect(cfg.showSlider, false);
        expect(cfg.presets, isEmpty);
        expect(cfg.stopButton.visible, false);
        expect(
          suggestion.widgetChoices.any((v) => v.type == PanelType.toggle),
          true,
        );
      }
    },
  );

  test(
    'missing or read-only counterparts never become paired covers, even with override',
    () {
      for (final d in [device(complete: false), device(readOnly: true)]) {
        expect(wirenBoardCurtainFor(d, d.controls.first), isNull);
        expect(
          suggestWirenBoardPanel(
            d,
            d.controls.first,
            allowCommands: true,
          ).widgetChoices.any((v) => v.type == PanelType.cover),
          false,
        );
      }
    },
  );

  test(
    'cover config retains pair, titles, icons and visibility through backup encoding',
    () {
      final config = CoverConfig(
        wirenBoard: const WirenBoardCoverBinding(deviceId: 'relay', number: 2),
        openButton: const CoverButtonConfig(
          title: 'Entrance',
          icon: CoverButtonIcon.gatePartial,
        ),
        closeButton: const CoverButtonConfig(
          title: 'Shut',
          icon: CoverButtonIcon.gateClosed,
        ),
        stopButton: const CoverButtonConfig(visible: false),
        showSlider: false,
        presets: const [],
      );
      final restored =
          PanelConfig.decode(PanelType.cover, config.encode()) as CoverConfig;
      expect(restored.toJson(), config.toJson());
      expect(restored.wirenBoard!.number, 2);
      expect(restored.stopButton.visible, false);
    },
  );

  test(
    'legacy covers keep three buttons and custom JSON paths and payloads when edited',
    () {
      final old = CoverConfig.fromJson({
        'statePath': 'motor.state',
        'positionPath': 'motor.position',
        'openPayload': 'up',
        'closePayload': 'down',
        'stopPayload': 'halt',
      });
      expect(old.wirenBoard, isNull);
      expect(
        [
          old.openButton.visible,
          old.closeButton.visible,
          old.stopButton.visible,
        ],
        [true, true, true],
      );
      final edited = old.copyWith(
        stopButton: const CoverButtonConfig(visible: false),
      );
      expect(edited.statePath, 'motor.state');
      expect(edited.openPayload, 'up');
      expect(edited.closePayload, 'down');
      expect(edited.stopPayload, 'halt');
    },
  );
}
