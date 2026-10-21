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
      '{"type":"rgb"}': PanelType.textLog,
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
