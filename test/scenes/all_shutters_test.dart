import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zigdash/features/discovery/models/z2m_device.dart';
import 'package:zigdash/features/scenes/all_shutters.dart';
import 'package:zigdash/l10n/app_localizations.dart';

const _cover = {
  'type': 'cover',
  'features': [
    {'type': 'enum', 'name': 'state', 'property': 'state', 'access': 3, 'values': ['OPEN', 'CLOSE', 'STOP']},
    {'type': 'numeric', 'name': 'position', 'property': 'position', 'access': 7},
  ],
};
const _light = {
  'type': 'light',
  'features': [
    {'type': 'binary', 'name': 'state', 'property': 'state', 'access': 7, 'value_on': 'ON', 'value_off': 'OFF'},
  ],
};

Z2mDevice _dev(String name, Object expose, {String? ieee}) => Z2mDevice(
    friendlyName: name, type: 'Router', ieeeAddress: ieee, rawExposes: [expose]);

final _devices = [
  _dev('Living room blind', _cover, ieee: '0x01'),
  _dev('Kitchen lamp', _light, ieee: '0x02'),
  _dev('Garage door', _cover, ieee: '0x03'),
  _dev('Bedroom shutter', _cover),
];

void main() {
  test('ids are stable and round-trip; anything else is a saved scene', () {
    for (final c in ShutterCommand.values) {
      expect(allShuttersCommand(allShuttersSceneId(c)), c);
    }
    expect(allShuttersSceneId(ShutterCommand.close), 'all_shutters:close');
    expect(allShuttersCommand('3f9c-uuid'), isNull);
    expect(allShuttersCommand('all_shutters:dance'), isNull);
  });

  test('only covers count as shutters; a cover without an address keys by name',
      () {
    expect(shuttersOf(_devices).map((d) => d.friendlyName),
        ['Living room blind', 'Garage door', 'Bedroom shutter']);
    expect(shutterKey(_devices[0]), '0x01');
    expect(shutterKey(_devices[3]), 'Bedroom shutter');
  });

  test('actions command every included shutter on <base>/<name>/set', () {
    final actions =
        shutterActions(ShutterCommand.close, 'zigbee2mqtt', _devices, {'0x03'});
    expect(actions.map((a) => a.setTopic), [
      'zigbee2mqtt/Living room blind/set',
      'zigbee2mqtt/Bedroom shutter/set',
    ]);
    expect(actions.map((a) => a.payload).toSet(), {'{"state":"CLOSE"}'});
    expect(shutterActions(ShutterCommand.open, 'z2m', _devices, {}).first.payload,
        '{"state":"OPEN"}');
    expect(shutterActions(ShutterCommand.stop, 'z2m', _devices, {}).first.payload,
        '{"state":"STOP"}');
    expect(shutterActions(ShutterCommand.close, 'z2m', const [], {}), isEmpty);
  });

  test('exclusions are a per-Home string list; new shutters are included',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(excludedShutters(prefs, 'h1'), isEmpty);
    await setShutterExcluded(prefs, 'h1', key: '0x03', excluded: true);
    await setShutterExcluded(prefs, 'h1', key: '0x01', excluded: true);
    await setShutterExcluded(prefs, 'h1', key: '0x01', excluded: false);
    expect(excludedShutters(prefs, 'h1'), {'0x03'});
    expect(excludedShutters(prefs, 'h2'), isEmpty);
    expect(includedShutters(_devices, excludedShutters(prefs, 'h1'))
        .map((d) => d.friendlyName),
        ['Living room blind', 'Bedroom shutter']);
  });

  test('the built-ins are three localised scene rows, listed first', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final scenes = allShuttersScenes('h1', en);
    expect(scenes.map((s) => s.name),
        ['Close all shutters', 'Open all shutters', 'Stop all shutters']);
    expect(scenes.map((s) => s.id).toSet(), hasLength(3));
    expect(scenes.every((s) => s.connectionId == 'h1'), isTrue);
    expect(scenes.every((s) => s.sortOrder < 0), isTrue,
        reason: 'before any saved scene');
    final fr = lookupAppLocalizations(const Locale('fr'));
    expect(allShuttersScenes('h1', fr).first.name, 'Fermer tous les volets');
  });
}
