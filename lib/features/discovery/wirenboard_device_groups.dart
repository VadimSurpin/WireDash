import '../../l10n/app_localizations.dart';
import 'models/wirenboard_device.dart';

String wirenBoardGroupLabel(
  WirenBoardDeviceGroup group,
  AppLocalizations l10n,
) => switch (group) {
  WirenBoardDeviceGroup.modules => l10n.wbAddedModules,
  WirenBoardDeviceGroup.z2m => l10n.wbZ2mDevices,
  WirenBoardDeviceGroup.builtins => l10n.wbControllerBuiltins,
};

/// Recognize automatic section names even after the app language changes.
Map<String, WirenBoardDeviceGroup> wirenBoardSectionGroups() => {
  for (final locale in AppLocalizations.supportedLocales)
    for (final group in WirenBoardDeviceGroup.values)
      wirenBoardGroupLabel(group, lookupAppLocalizations(locale)): group,
};
