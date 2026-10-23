import 'package:zigdash/data/database/daos/connection_dao.dart';
import 'package:zigdash/data/database/daos/dashboard_dao.dart';
import 'package:zigdash/data/database/daos/section_dao.dart';
import 'package:zigdash/data/database/daos/panel_dao.dart';
import 'package:drift/native.dart';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/data/database/database.dart';
import 'package:zigdash/data/database/tables/connections.dart';
import 'package:zigdash/data/database/tables/panels.dart';
import 'package:zigdash/data/repositories/connection_repo.dart';
import 'package:zigdash/data/repositories/dashboard_repo.dart';
import 'package:zigdash/data/repositories/panel_repo.dart';
import 'package:zigdash/data/repositories/section_repo.dart';
import 'package:zigdash/core/storage/secure_storage.dart';
import 'package:zigdash/features/discovery/models/wirenboard_device.dart';
import 'package:zigdash/features/discovery/models/z2m_device.dart';
import 'package:zigdash/features/discovery/wirenboard_dashboard_importer.dart';
import 'package:zigdash/features/onboarding/setup/setup_creator.dart';
import 'package:zigdash/features/panels/models/panel_config.dart';
import 'package:zigdash/l10n/app_localizations.dart';

class _Storage implements SecureStore {
  @override
  Future<String?> readWireGuard(String id) async => null;
  @override
  Future<void> writeWireGuard(String id, String config) async {}
  @override
  Future<void> deleteWireGuard(String id) async {}

  @override
  Future<void> writePassword(String id, String password) async {}
  @override
  Future<void> deletePassword(String id) async {}
  @override
  Future<String?> readPassword(String id) async => null;
}

void main() {
  late AppDatabase db;
  late PanelRepo panels;
  late SectionRepo sections;
  late DashboardRepo dashboards;
  late String dashboard;
  late WirenBoardDiscovery discovery;
  setUp(() async {
    db = AppDatabase.test(NativeDatabase.memory());
    panels = PanelRepo(PanelDao(db));
    sections = SectionRepo(SectionDao(db));
    dashboards = DashboardRepo(DashboardDao(db));
    await db
        .into(db.connections)
        .insert(
          ConnectionsCompanion.insert(
            id: 'c1',
            name: 'Home',
            host: 'broker',
            port: 1883,
            protocol: MqttProtocol.tcp,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        );
    dashboard = await dashboards.create(
      connectionId: 'c1',
      name: 'Home',
      colorSeed: 0,
      iconCodepoint: 0,
    );
    discovery = WirenBoardDiscovery()
      ..apply(
        '/devices/hwmon/controls/CPU/meta',
        '{"type":"temperature","readonly":true}',
      )
      ..apply('/devices/wb-mr6_10/controls/Relay 1/meta', '{"type":"switch"}')
      ..apply(
        '/devices/wb-msw_11/controls/Temperature/meta',
        '{"type":"temperature","readonly":true}',
      );
  });
  tearDown(() => db.close());

  test(
    'rediscovery preserves card labels and visibility without creating another whole-device panel',
    () async {
      final importer = WirenBoardDashboardImporter(
        dashboardId: dashboard,
        panels: panels,
        sections: sections,
        l10n: lookupAppLocalizations(const Locale('en')),
      );
      await importer.importDevices(discovery.devices);
      final saved = await panels.getByDashboard(dashboard);
      final tile = saved.firstWhere(
        (p) => p.topicPrefixOverride == '/devices/wb-mr6_10',
      );
      final config =
          PanelConfig.decode(tile.type, tile.config) as WirenBoardDeviceConfig;
      const display = DevicePanelDisplay(
        properties: ['Relay 1'],
        labels: {'Relay 1': 'Kitchen'},
        expressions: {'Relay 1': 'Number(value) ? "On" : "Off"'},
      );
      await panels.update(
        id: tile.id,
        name: tile.name,
        topic: tile.topic,
        width: tile.width,
        topicPrefixOverride: tile.topicPrefixOverride,
        config: WirenBoardDeviceConfig(device: config.device, display: display),
      );
      discovery.apply(
        '/devices/wb-mr6_10/controls/Relay 2/meta',
        '{"type":"switch"}',
      );
      expect(await importer.importDevices(discovery.devices), 0);
      final updated = await panels.getByDashboard(dashboard);
      expect(updated.length, saved.length);
      final panel = updated.singleWhere((p) => p.id == tile.id);
      final decoded =
          PanelConfig.decode(panel.type, panel.config)
              as WirenBoardDeviceConfig;
      expect(decoded.controlIds, isNull);
      expect(decoded.device.controls, hasLength(2));
      expect(decoded.display.toJson(), display.toJson());
    },
  );

  test(
    'chosen property widgets keep scalar topics and read-only controls reject writable widgets',
    () async {
      final importer = WirenBoardDashboardImporter(
        dashboardId: dashboard,
        panels: panels,
        sections: sections,
        l10n: lookupAppLocalizations(const Locale('en')),
      );
      final device = discovery.devices.firstWhere((d) => d.id == 'wb-msw_11');
      await importer.addControl(
        device,
        device.controls.single,
        label: 'Temperature bar',
        widgetType: PanelType.progress,
        valueExpression: '(Number(value) / 10).toFixed(2)',
      );
      final panel = (await panels.getByDashboard(dashboard)).single;
      expect(panel.type, PanelType.progress);
      expect(panel.name, 'Temperature bar');
      expect(
        PanelConfig.decode(panel.type, panel.config).valueExpression,
        '(Number(value) / 10).toFixed(2)',
      );
      expect(
        panel.topicPrefixOverride,
        '/devices/wb-msw_11/controls/Temperature',
      );
      expect(panel.subscribeTopic, '');
      expect(
        (PanelConfig.decode(panel.type, panel.config) as ProgressConfig)
            .jsonPath,
        isNull,
      );
      await expectLater(
        importer.addControl(
          device,
          device.controls.single,
          label: 'Invalid',
          widgetType: PanelType.toggle,
        ),
        throwsArgumentError,
      );
      expect(await panels.getByDashboard(dashboard), hasLength(1));
    },
  );

  test(
    'writable nonnumeric controls save raw input tiles and readonly ones reject input',
    () async {
      final importer = WirenBoardDashboardImporter(
        dashboardId: dashboard,
        panels: panels,
        sections: sections,
        l10n: lookupAppLocalizations(const Locale('en')),
      );
      for (final type in ['rgb', 'local_time', 'custom']) {
        final device =
            (WirenBoardDiscovery()..apply(
                  '/devices/config/controls/$type/meta',
                  '{"type":"$type"}',
                ))
                .devices
                .single;
        await importer.addControl(
          device,
          device.controls.single,
          label: type,
          widgetType: PanelType.textInput,
        );
        final panel = (await panels.getByDashboard(
          dashboard,
        )).singleWhere((p) => p.name == type);
        expect(panel.type, PanelType.textInput);
        expect(panel.topicPrefixOverride, '/devices/config/controls/$type');
        expect(panel.topic, 'on');
        expect(panel.subscribeTopic, '');
        expect(panel.retain, isFalse);
        expect(
          (PanelConfig.decode(panel.type, panel.config) as TextInputConfig)
              .template,
          '{value}',
        );
        final readonly =
            (WirenBoardDiscovery()..apply(
                  '/devices/config/controls/$type/meta',
                  '{"type":"$type","readonly":true}',
                ))
                .devices
                .single;
        await expectLater(
          importer.addControl(
            readonly,
            readonly.controls.single,
            label: 'Invalid',
            widgetType: PanelType.textInput,
          ),
          throwsArgumentError,
        );
      }
      expect(await panels.getByDashboard(dashboard), hasLength(3));
    },
  );

  test(
    'explicit command override saves a K1 toggle without changing device metadata',
    () async {
      final device =
          (WirenBoardDiscovery()..apply(
                '/devices/wb-mr6c_12/controls/K1/meta',
                '{"type":"switch","readonly":true}',
              ))
              .devices
              .single;
      final importer = WirenBoardDashboardImporter(
        dashboardId: dashboard,
        panels: panels,
        sections: sections,
        l10n: lookupAppLocalizations(const Locale('en')),
      );
      await importer.addControl(
        device,
        device.controls.single,
        label: 'Kitchen relay',
        widgetType: PanelType.toggle,
        allowCommands: true,
      );
      final saved = (await panels.getByDashboard(dashboard)).single;
      expect(saved.name, 'Kitchen relay');
      expect(saved.type, PanelType.toggle);
      expect(saved.topicPrefixOverride, '/devices/wb-mr6c_12/controls/K1');
      expect(saved.topic, 'on');
      expect(saved.subscribeTopic, '');
      expect(saved.retain, isFalse);
      final config =
          PanelConfig.decode(saved.type, saved.config) as ToggleConfig;
      expect((config.onPayload, config.offPayload), ('1', '0'));
      expect(config.jsonPath, isNull);
      expect(device.controls.single.readOnly, isTrue);
      await expectLater(
        importer.addControl(
          device,
          device.controls.single,
          label: 'Without override',
          widgetType: PanelType.toggle,
        ),
        throwsArgumentError,
      );
      expect(await panels.getByDashboard(dashboard), hasLength(1));
    },
  );

  test(
    'rediscovery moves service and mirrored panels while preserving custom labels, subsets and sections',
    () async {
      final importer = WirenBoardDashboardImporter(
        dashboardId: dashboard,
        panels: panels,
        sections: sections,
        l10n: lookupAppLocalizations(const Locale('en')),
      );
      final mirrorDiscovery = WirenBoardDiscovery()
        ..apply('/devices/room_lamp/controls/state/meta', '{"type":"switch"}');
      final mirror = mirrorDiscovery.devices.single;
      await importer.importDevices([mirror]);
      // Older versions could create subset tiles. Keep those usable on upgrade.
      for (final label in ['Only the light', 'My custom group']) {
        await panels.create(
          dashboardId: dashboard,
          name: label,
          type: PanelType.device,
          topic: '',
          config: WirenBoardDeviceConfig(device: mirror, controlIds: ['state']),
        );
      }
      var saved = await panels.getByDashboard(dashboard);
      final customPanel = saved.firstWhere((p) => p.name == 'My custom group');
      final customSection = await sections.create(
        dashboardId: dashboard,
        name: 'Kitchen',
        sortOrder: 1,
      );
      await panels.setSection(customPanel.id, customSection);
      final modules = (await sections.getByDashboard(
        dashboard,
      )).firstWhere((s) => s.name == 'Added modules');
      final service =
          (WirenBoardDiscovery()..apply(
                '/devices/cloud_status/controls/status/meta',
                '{"type":"text","readonly":true}',
              ))
              .devices
              .single;
      final serviceId = await panels.create(
        dashboardId: dashboard,
        name: 'My cloud status',
        type: PanelType.device,
        topic: '',
        sectionId: modules.id,
        config: WirenBoardDeviceConfig(device: service),
      );
      final classified = classifyWirenBoardDevices(
        [mirror, service],
        const [Z2mDevice(friendlyName: 'room/lamp', type: 'Router')],
      );
      expect(await importer.importDevices(classified), 0);
      expect(await importer.importDevices(classified), 0);
      saved = await panels.getByDashboard(dashboard);
      expect(saved, hasLength(4));
      final sectionList = await sections.getByDashboard(dashboard);
      final mirrorSection = sectionList.singleWhere(
        (s) => s.name == 'Wirenboard Z2M devices',
      );
      final builtinSection = sectionList.singleWhere(
        (s) => s.name == 'Controller built-ins',
      );
      expect(
        saved.singleWhere((p) => p.id == serviceId).sectionId,
        builtinSection.id,
      );
      final subset = saved.singleWhere((p) => p.name == 'Only the light');
      expect(subset.sectionId, mirrorSection.id);
      final subsetConfig =
          PanelConfig.decode(subset.type, subset.config)
              as WirenBoardDeviceConfig;
      expect(subsetConfig.controlIds, ['state']);
      expect(subsetConfig.device.isZ2mMirror, isTrue);
      expect(
        saved.singleWhere((p) => p.id == customPanel.id).sectionId,
        customSection,
      );
    },
  );

  test(
    'named property panels survive automatic whole-device imports and custom labels are kept',
    () async {
      final importer = WirenBoardDashboardImporter(
        dashboardId: dashboard,
        panels: panels,
        sections: sections,
        l10n: lookupAppLocalizations(const Locale('en')),
      );
      final module = discovery.devices.firstWhere((d) => d.id == 'wb-mr6_10');
      await importer.addControl(
        module,
        module.controls.single,
        label: 'Kitchen relay',
      );
      await importer.importDevices(discovery.devices);
      var saved = await panels.getByDashboard(dashboard);
      expect(saved, hasLength(3));
      final selected = saved.firstWhere((p) => p.name == 'Kitchen relay');
      expect(selected.type, PanelType.toggle);
      expect(
        selected.topicPrefixOverride,
        '/devices/wb-mr6_10/controls/Relay 1',
      );
      expect(selected.topic, 'on');
      expect(selected.subscribeTopic, '');
      expect(selected.retain, isFalse);
      expect(
        PanelConfig.decode(selected.type, selected.config),
        isA<ToggleConfig>(),
      );
      await importer.addDevice(module, label: 'All kitchen outputs');
      discovery.apply(
        '/devices/wb-mr6_10/controls/Relay 2/meta',
        '{"type":"switch"}',
      );
      await importer.importDevices(discovery.devices);
      saved = await panels.getByDashboard(dashboard);
      expect(saved, hasLength(3));
      expect(saved.any((p) => p.name == 'All kitchen outputs'), isTrue);
      final updated = saved.singleWhere((p) => p.id == selected.id);
      expect(updated.name, 'Kitchen relay');
      expect(updated.type, PanelType.toggle);
      expect(updated.config, selected.config);
      final section = (await sections.getByDashboard(
        dashboard,
      )).singleWhere((s) => s.id == updated.sectionId);
      expect(section.name, 'Added modules');
    },
  );

  test(
    'auto-import excludes built-ins and repeated/concurrent discovery does not duplicate tiles',
    () async {
      final importer = WirenBoardDashboardImporter(
        dashboardId: dashboard,
        panels: panels,
        sections: sections,
        l10n: lookupAppLocalizations(const Locale('ru')),
      );
      expect(await importer.importDevices(discovery.devices), 2);
      final first = (await panels.getByDashboard(dashboard)).first;
      await panels.update(
        id: first.id,
        name: 'My custom name',
        topic: first.topic,
        topicPrefixOverride: first.topicPrefixOverride,
        subscribeTopic: first.subscribeTopic,
        width: first.width,
        config: PanelConfig.decode(first.type, first.config),
      );
      discovery.apply(
        '/devices/wb-mr6_10/controls/Relay 2/meta',
        '{"type":"switch","readonly":true}',
      );
      expect(
        await Future.wait([
          importer.importDevices(discovery.devices),
          importer.importDevices(discovery.devices),
        ]),
        [0, 0],
      );
      final saved = await panels.getByDashboard(dashboard);
      expect(saved, hasLength(2));
      expect(saved.first.name, 'My custom name');
      expect(
        (PanelConfig.decode(saved.first.type, saved.first.config)
                as WirenBoardDeviceConfig)
            .device
            .controls,
        hasLength(2),
      );
      expect(
        (await sections.getByDashboard(dashboard)).single.name,
        'Добавленные модули',
      );
      expect(
        await importer.importDevices(
          discovery.devices.where((d) => d.isControllerBuiltin).toList(),
          includeBuiltins: true,
        ),
        1,
      );
      expect(await panels.getByDashboard(dashboard), hasLength(3));
    },
  );

  test(
    'first dashboard creation includes all external WB devices without any Z2M devices',
    () async {
      final creator = SetupCreator(
        connections: ConnectionRepo(ConnectionDao(db), _Storage()),
        dashboards: dashboards,
        sections: sections,
        panels: panels,
      );
      final result = await creator.createDashboard(
        connectionId: 'c1',
        selected: const [],
        wirenBoardDevices: discovery.devices,
      );
      expect(result.panelCount, 2);
      final saved = await panels.getByDashboard(result.dashboardId);
      expect(saved, hasLength(2));
      expect(
        saved.map(
          (p) =>
              (PanelConfig.decode(p.type, p.config) as WirenBoardDeviceConfig)
                  .device
                  .id,
        ),
        ['wb-mr6_10', 'wb-msw_11'],
      );
    },
  );
}
