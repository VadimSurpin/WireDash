import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/data/database/database.dart';
import 'package:wiredash/data/database/tables/panels.dart';
import 'package:wiredash/features/panels/models/panel_config.dart';
import 'package:wiredash/features/panels/widgets/panel_tile.dart';
import 'package:wiredash/features/panels/widgets/panel_reliability_frame.dart';
import 'package:wiredash/l10n/app_localizations.dart';
import 'package:wiredash/mqtt/mqtt_status.dart';
import 'package:wiredash/mqtt/providers/mqtt_manager_provider.dart';
import 'package:wiredash/plugins/panel_plugins.dart';
import 'package:wiredash_video/wiredash_video.dart';
import 'plugin_test_fakes.dart';

void main() {
  testWidgets(
    'dashboard video is usable without MQTT and survives the intrinsic-height grid layout',
    (tester) async {
      final host = MemoryHost();
      final session = FakeSession();
      final date = DateTime(2026);
      final panel = Panel(
        id: 'video',
        dashboardId: 'd',
        name: 'Front gate',
        type: PanelType.plugin,
        topic: '',
        qos: 1,
        retain: false,
        width: PanelWidth.full,
        sortOrder: 0,
        mergeFlags: 0,
        config: PluginPanelConfig(
          pluginId: VideoPanelPlugin.pluginId,
          settings: const VideoConfig(streamUrl: 'rtsp://camera/live').toJson(),
        ).encode(),
        createdAt: date,
        updatedAt: date,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            panelPluginsProvider.overrideWithValue({
              VideoPanelPlugin.pluginId: VideoPanelPlugin(
                sessionFactory: () => session,
              ),
            }),
            pluginHostProvider.overrideWith((ref, key) => host),
            connectionStatusProvider.overrideWith(
              (ref, _) => Stream.value(MqttStatus.disconnected),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 320,
                        child: PanelTile(
                          connectionId: 'home',
                          dashboardId: 'd',
                          topicPrefix: 'zigbee2mqtt',
                          panel: panel,
                          locked: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final frame = tester.widget<PanelReliabilityFrame>(
        find.byType(PanelReliabilityFrame),
      );
      expect(frame.controlsEnabled, isTrue);
      expect(frame.stale, isFalse);
      await tester.tap(find.byTooltip('Play live video'));
      await tester.pumpAndSettle();
      expect(session.opened!.host, 'camera');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(session.closed, isTrue);
    },
  );
}
