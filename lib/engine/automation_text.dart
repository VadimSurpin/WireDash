import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'automation.dart';

/// Automations in words, for the list and the editor (zigdash-3.0.md §1).

/// A device value as people say it: "motion", "opened", "single press".
String valueText(AppLocalizations l10n, String property, Object? value) {
  switch (property) {
    case 'occupancy':
    case 'presence':
      return value == true ? l10n.autoValMotion : l10n.autoValNoMotion;
    case 'contact':
      // Zigbee2MQTT: contact true = closed.
      return value == true ? l10n.autoValClosed : l10n.autoValOpened;
    case 'water_leak':
      return value == true ? l10n.autoValLeak : l10n.autoValDry;
    case 'smoke':
      return value == true ? l10n.autoValSmoke : l10n.autoValNoSmoke;
    case 'state':
      return switch ('$value'.toUpperCase()) {
        'ON' => l10n.autoValOn,
        'OFF' => l10n.autoValOff,
        'TOGGLE' => l10n.autoValToggle,
        'OPEN' => l10n.autoValOpen,
        'CLOSE' => l10n.autoValClose,
        'STOP' => l10n.autoValStop,
        _ => '$value',
      };
    case 'action':
      return '$value'.replaceAll('_', ' ');
  }
  if (value is bool) return value ? l10n.autoValOn : l10n.autoValOff;
  return '${property.replaceAll('_', ' ')}: $value';
}

String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

String triggerText(AppLocalizations l10n, MaterialLocalizations ml, AutomationTrigger t, {String? deviceName}) {
  switch (t) {
    case DeviceTrigger():
      final name = deviceName ?? t.label ?? t.ieee;
      if (t.above != null) return l10n.autoWhenAbove(name, t.property.replaceAll('_', ' '), _num(t.above!));
      if (t.below != null) return l10n.autoWhenBelow(name, t.property.replaceAll('_', ' '), _num(t.below!));
      return l10n.autoWhenDevice(name, valueText(l10n, t.property, t.equals));
    case TimeTrigger():
      final when = switch (t.sun) {
        null => l10n.autoAtTime(t.at ?? '--:--'),
        final sun => () {
            final sunName = sun == Sun.sunrise ? l10n.autoSunrise : l10n.autoSunset;
            if (t.offset > 0) return l10n.autoAfterSun(t.offset, sunName);
            if (t.offset < 0) return l10n.autoBeforeSun(-t.offset, sunName);
            return l10n.autoAtSun(sunName);
          }(),
      };
      return '$when, ${daysText(l10n, ml, t.days)}';
  }
}

/// "every day", "weekdays", "weekends", or the short names in order.
String daysText(AppLocalizations l10n, MaterialLocalizations ml, List<int> days) {
  final set = days.toSet();
  if (set.length == 7) return l10n.autoEveryDay;
  if (set.length == 5 && set.containsAll(const [1, 2, 3, 4, 5])) return l10n.autoWeekdays;
  if (set.length == 2 && set.containsAll(const [6, 7])) return l10n.autoWeekends;
  return [for (final d in (days.toList()..sort())) dayShort(ml, d)].join(' ');
}

/// ISO day (1 = Monday) to the locale's narrow name.
String dayShort(MaterialLocalizations ml, int isoDay) => ml.narrowWeekdays[isoDay % 7];

String conditionText(AppLocalizations l10n, AutomationCondition c, {String? deviceName}) => switch (c) {
      HoursCondition() => l10n.autoBetween(c.from, c.to),
      DeviceCondition() => l10n.autoDeviceIs(deviceName ?? c.label ?? c.ieee, valueText(l10n, c.property, c.equals)),
    };

String actionText(AppLocalizations l10n, AutomationAction a, {String? name}) {
  final label = name ?? a.label ?? '';
  final base = a.kind == ActionKind.scene
      ? l10n.autoRunScene(label)
      : l10n.autoSetDevice(label, valueText(l10n, 'state', a.deviceState));
  return a.offAfter > 0 ? l10n.autoOffAfter(base, a.offAfter) : base;
}

/// A name for a rule saved without one.
String autoName(AppLocalizations l10n, MaterialLocalizations ml, Automation r) =>
    '${triggerText(l10n, ml, r.trigger)} → ${actionText(l10n, r.action)}';

String hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay? parseHhmm(String? s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s ?? '');
  return m == null ? null : TimeOfDay(hour: int.parse(m[1]!), minute: int.parse(m[2]!));
}
