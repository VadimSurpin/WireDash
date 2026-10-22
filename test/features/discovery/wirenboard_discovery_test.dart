import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/data/database/tables/panels.dart';
import 'package:zigdash/features/discovery/models/wirenboard_device.dart';
import 'package:zigdash/features/discovery/models/wirenboard_panel_suggestion.dart';
import 'package:zigdash/features/panels/models/panel_config.dart';
import 'package:zigdash/features/panels/providers/panel_value_provider.dart';
import 'package:zigdash/mqtt/json_path.dart';

void main() {
  const topic = '/devices/wb-mr6c_12/controls/Relay 1';

  test(
    'widget alternatives preserve raw payloads, enums and read-only restrictions',
    () {
      for (final meta in [
        '{"type":"switch"}',
        '{"type":"wo-switch"}',
        '{"type":"range","min":10,"max":90}',
        '{"type":"value","enum":{"0":"Manual","0x10":"Auto"}}',
        '{"type":"temperature","readonly":true}',
        '{"type":"switch","readonly":true}',
        '{"type":"text"}',
        '{"type":"rgb"}',
        '{"type":"local_time"}',
        '{"type":"custom"}',
        '{"type":"rgb","readonly":true}',
        '{"type":"local_time","readonly":true}',
      ]) {
        final device =
            (WirenBoardDiscovery()..apply('$topic/meta', meta)).devices.single;
        final control = device.controls.single;
        final suggestion = suggestWirenBoardPanel(device, control);
        expect(suggestion.widgetChoices.first.type, suggestion.type);
        if (!control.readOnly) {
          expect(
            suggestion.widgetChoices.map((choice) => choice.type),
            contains(PanelType.textInput),
            reason: meta,
          );
        }
        for (final choice in suggestion.widgetChoices) {
          expect(choice.topicPrefixOverride, topic);
          expect(choice.subscribeTopicSuffix, '');
          expect(choice.publishTopicSuffix, control.readOnly ? '' : 'on');
          if (choice.config is TextInputConfig) {
            expect((choice.config as TextInputConfig).template, '{value}');
          }
          final config = choice.config!;
          if (control.readOnly) {
            expect(
              choice.type,
              isIn([
                PanelType.led,
                PanelType.reading,
                PanelType.progress,
                PanelType.textLog,
              ]),
            );
          }
          if (config is ToggleConfig) {
            expect(config.onPayload, '1');
            expect(config.offPayload, '0');
          }
          if (config is SliderConfig) {
            expect(config.valueTemplate, '{value}');
            expect(config.jsonPath, isNull);
          }
          if (config is OptionsConfig && control.type == 'value') {
            expect(config.options.last.payload, '16');
          }
        }
      }
    },
  );

  test(
    'legacy metadata discovers controls without values or device metadata',
    () {
      final discovery = WirenBoardDiscovery();
      discovery.apply('$topic/meta/readonly', '0');
      discovery.apply('$topic/meta/type', 'switch');
      discovery.apply('/devices/wb-mr6c_12/meta/name', 'Relay module');
      final device = discovery.devices.single;
      expect(device.title('en'), 'Relay module');
      expect(device.controls.single.title('en'), 'Relay 1');
      expect(device.controls.single.readOnly, isFalse);
      expect(device.controls.single.topic, topic);
      expect(discovery.apply(topic, '1'), isFalse);
      expect(discovery.apply('$topic/on', '0'), isFalse);
      expect(discovery.apply('$topic/meta/error', 'r'), isFalse);
      expect(
        discovery.apply('devices/wrong/controls/x/meta', '{"type":"switch"}'),
        isFalse,
        reason: 'The leading slash is part of the WB topic',
      );
    },
  );

  test(
    'JSON wins over legacy regardless of delivery order and titles localize',
    () {
      for (final legacyFirst in [true, false]) {
        final d = WirenBoardDiscovery();
        void legacy() => d.apply('$topic/meta/readonly', '0');
        if (legacyFirst) legacy();
        d.apply(
          '$topic/meta',
          '{"type":"switch","readonly":true,'
              '"title":{"ru":"Реле","en":"Relay"}}',
        );
        if (!legacyFirst) legacy();
        final control = d.devices.single.controls.single;
        expect(control.readOnly, isTrue);
        expect(control.title('ru'), 'Реле');
        expect(control.title('de'), 'Relay');
      }
    },
  );

  test(
    'complete JSON metadata restores MR6C K1–K6 toggle choices despite stale legacy flags',
    () {
      for (final legacyFirst in [true, false]) {
        final discovery = WirenBoardDiscovery();
        for (var i = 1; i <= 6; i++) {
          final topic = '/devices/wb-mr6c_12/controls/K$i';
          void legacy() {
            discovery.apply('$topic/meta/type', 'value');
            discovery.apply('$topic/meta/readonly', '1');
            discovery.apply('$topic/meta/hidden', '1');
            discovery.apply('$topic/meta/min', '10');
            discovery.apply('$topic/meta/max', '20');
          }

          if (legacyFirst) legacy();
          discovery.apply('$topic/meta', '{"type":"switch","order":$i}');
          if (!legacyFirst) legacy();
        }
        final device = discovery.devices.single;
        expect(device.controls.map((c) => c.id), [
          'K1',
          'K2',
          'K3',
          'K4',
          'K5',
          'K6',
        ]);
        for (final control in device.controls) {
          expect(control.readOnly, isFalse);
          expect(control.min, isNull);
          expect(control.max, isNull);
          final suggestion = suggestWirenBoardPanel(
            device,
            control,
            widgetType: PanelType.toggle,
          );
          expect(suggestion.type, PanelType.toggle);
          expect(suggestion.publishTopicSuffix, 'on');
          expect((suggestion.config as ToggleConfig).onPayload, '1');
          expect((suggestion.config as ToggleConfig).offPayload, '0');
        }
        // A modern read-only flag must still win over writable legacy metadata.
        const first = '/devices/wb-mr6c_12/controls/K1';
        discovery.apply('$first/meta', '{"type":"switch","readonly":true}');
        discovery.apply('$first/meta/readonly', '0');
        final updated = discovery.devices.single;
        expect(
          updated.controls.firstWhere((c) => c.id == 'K1').readOnly,
          isTrue,
        );
        expect(
          () => suggestWirenBoardPanel(
            updated,
            updated.controls.firstWhere((c) => c.id == 'K1'),
            widgetType: PanelType.toggle,
          ),
          throwsArgumentError,
        );
      }
    },
  );

  test(
    'JSON removal falls back to legacy metadata and names remain available',
    () {
      final discovery = WirenBoardDiscovery()
        ..apply('/devices/wb-mr6c_12/meta/name', 'Relay module')
        ..apply('/devices/wb-mr6c_12/meta', '{"driver":"wb-mqtt-serial"}')
        ..apply('$topic/meta/name', 'Kitchen')
        ..apply('$topic/meta/type', 'switch')
        ..apply('$topic/meta/readonly', '1')
        ..apply('$topic/meta', '{"type":"switch"}');
      expect(discovery.devices.single.title('en'), 'Relay module');
      expect(discovery.devices.single.controls.single.title('en'), 'Kitchen');
      expect(discovery.devices.single.controls.single.readOnly, isFalse);
      discovery.apply('$topic/meta', '');
      expect(discovery.devices.single.controls.single.readOnly, isTrue);
      discovery.apply('$topic/meta/readonly', '0');
      expect(discovery.devices.single.controls.single.readOnly, isFalse);
    },
  );

  test('hidden, reordered, deleted and malformed retained metadata', () {
    final d = WirenBoardDiscovery();
    d.apply('$topic/meta', '{"type":"switch","order":2}');
    d.apply(
      '/devices/wb-mr6c_12/controls/Voltage/meta',
      '{"type":"voltage","readonly":true,"order":1}',
    );
    d.apply(
      '/devices/wb-mr6c_12/controls/Internal/meta',
      '{"type":"value","hidden":true}',
    );
    expect(d.devices.single.controls.map((c) => c.id), ['Voltage', 'Relay 1']);
    for (final invalid in ['{', '[]', 'null', '"switch"']) {
      expect(d.apply('$topic/meta', invalid), isFalse);
    }
    expect(d.devices.single.controls, hasLength(2));
    d.apply('$topic/meta', '');
    expect(d.devices.single.controls.single.id, 'Voltage');
    d.apply('/devices/wb-mr6c_12/controls/Voltage/meta', '');
    expect(d.devices, isEmpty);
    d.apply('$topic/meta/type', 'switch');
    d.apply('$topic/meta/type', '');
    expect(d.devices, isEmpty);
  });

  test('snapshots do not mutate after a later update', () {
    final d = WirenBoardDiscovery();
    d.apply('$topic/meta', '{"type":"switch","title":{"en":"Old"}}');
    final old = d.devices;
    d.apply('$topic/meta', '{"type":"switch","title":{"en":"New"}}');
    expect(old.single.controls.single.title('en'), 'Old');
    expect(d.devices.single.controls.single.title('en'), 'New');
  });

  test('relay suggestions preserve the slash and use scalar /on commands', () {
    final d = WirenBoardDiscovery()..apply('$topic/meta', '{"type":"switch"}');
    final device = d.devices.single;
    final suggestion = suggestWirenBoardPanel(device, device.controls.single);
    expect(suggestion.type, PanelType.toggle);
    final config = suggestion.config! as ToggleConfig;
    expect(
      (config.onPayload, config.offPayload, config.onMatch),
      ('1', '0', '1'),
    );
    expect(config.jsonPath, isNull);
    expect(
      composeTopic(
        suggestion.topicPrefixOverride,
        suggestion.publishTopicSuffix,
      ),
      '$topic/on',
    );
    expect(
      composeTopic(
        suggestion.topicPrefixOverride,
        suggestion.subscribeTopicSuffix,
      ),
      topic,
    );
    expect(extractByPath('1', config.jsonPath), config.onMatch);
  });

  test('control types map to usable scalar tile configurations', () {
    final cases = <String, PanelType>{
      '{"type":"switch","readonly":true}': PanelType.led,
      '{"type":"alarm"}': PanelType.led,
      '{"type":"wo-switch"}': PanelType.combo,
      '{"type":"pushbutton"}': PanelType.button,
      '{"type":"temperature","readonly":1}': PanelType.reading,
      '{"type":"value","readonly":true,"units":"W"}': PanelType.reading,
      '{"type":"range","min":10,"max":300}': PanelType.slider,
      '{"type":"range","min":10,"max":5}': PanelType.textInput,
      '{"type":"text"}': PanelType.textInput,
      '{"type":"rgb"}': PanelType.textInput,
      '{"type":"local_time"}': PanelType.textInput,
      '{"type":"custom"}': PanelType.textInput,
      '{"type":"rgb","readonly":true}': PanelType.textLog,
    };
    for (final entry in cases.entries) {
      final d = WirenBoardDiscovery()..apply('$topic/meta', entry.key);
      final device = d.devices.single;
      final suggestion = suggestWirenBoardPanel(device, device.controls.single);
      expect(suggestion.type, entry.value, reason: entry.key);
      final config = suggestion.config;
      if (config is ReadingConfig) {
        expect(config.jsonPath, isEmpty);
        expect(extractByPath('23.4', config.jsonPath), '23.4');
        expect(config.unit, isNotEmpty);
      } else if (config is SliderConfig) {
        expect((config.min, config.max, config.step), (10, 300, 1));
        expect(config.valueTemplate, '{value}');
        expect(config.jsonPath, isNull);
      } else if (config is ButtonConfig) {
        expect(config.payload, '1');
      }
    }
  });

  test('enum labels localize while payloads and matching stay raw', () {
    final d = WirenBoardDiscovery()
      ..apply(
        '$topic/meta',
        '{"type":"value","enum":{"0":{"en":"Off","ru":"Выкл"},'
            '"0x10":{"en":"Auto","ru":"Авто"}}}',
      );
    final device = d.devices.single;
    final suggestion = suggestWirenBoardPanel(
      device,
      device.controls.single,
      language: 'ru',
    );
    final config = suggestion.config! as OptionsConfig;
    expect(config.jsonPath, isNull);
    expect(config.options.map((o) => (o.label, o.payload, o.match)), [
      ('Выкл', '0', '0'),
      ('Авто', '16', '16'),
    ]);
  });
}
