import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zigdash/core/analytics/analytics.dart';
import 'package:zigdash/data/database/database.dart';
import 'package:zigdash/data/database/tables/connections.dart';
import 'package:zigdash/data/repositories/connection_repo.dart';
import 'package:zigdash/features/dashboards/widgets/community_card.dart';
import 'package:zigdash/features/dashboards/widgets/poll_card.dart';
import 'package:zigdash/features/onboarding/demo_service.dart' show demoHost;
import 'package:zigdash/features/settings/providers/settings_controller.dart';
import 'package:zigdash/features/support/community.dart';
import 'package:zigdash/l10n/app_localizations.dart';

class _Sink implements AnalyticsSink {
  final sent = <String>[];
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  void send(String name, Map<String, String> props) => sent.add('$name $props');
}

Connection _home(String host) => Connection(
      id: 'c1',
      name: 'Home',
      host: host,
      port: 1883,
      protocol: MqttProtocol.tcp,
      keepAliveSeconds: 60,
      autoConnect: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Future<(SharedPreferences, _Sink)> _card(WidgetTester tester,
    {Map<String, Object> prefs = const {}, String host = '192.168.1.2'}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final sink = _Sink();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(p),
      analyticsAvailableProvider.overrideWithValue(true),
      analyticsSinkProvider.overrideWithValue(sink),
      connectionByIdProvider.overrideWith((ref, _) async => _home(host)),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: CommunityCard(connectionId: 'c1')),
    ),
  ));
  await tester.pumpAndSettle();
  return (p, sink);
}

void main() {
  const title = 'Join the ZigDash community';
  const ready = {
    'analytics_consent': true,
    'review_sessions': 5,
    pollDoneKey: '1',
  };

  testWidgets('shown on the fifth day once the poll is done; Join opens the group',
      (tester) async {
    Uri? opened;
    openCommunityLink = (url) async {
      opened = url;
      return true;
    };
    final (prefs, sink) = await _card(tester, prefs: ready);
    expect(find.text(title), findsOneWidget);
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(opened, communityUrl);
    expect(sink.sent, ['community_opened {from: card}']);
    expect(find.text(title), findsNothing);
    expect(prefs.getString(communityCardDoneKey), '1');
  });

  testWidgets('not before the fifth day', (tester) async {
    await _card(tester, prefs: {...ready, 'review_sessions': 4});
    expect(find.text(title), findsNothing);
  });

  testWidgets('waits for the poll card', (tester) async {
    await _card(tester,
        prefs: {'analytics_consent': true, 'review_sessions': 9});
    expect(find.text(title), findsNothing);
  });

  testWidgets('waits while the usage-data question is open', (tester) async {
    await _card(tester, prefs: {'review_sessions': 9, pollDoneKey: '1'});
    expect(find.text(title), findsNothing);
  });

  testWidgets('Not now puts it away for good, sending nothing', (tester) async {
    final (prefs, sink) = await _card(tester, prefs: ready);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(sink.sent, isEmpty);
    expect(find.text(title), findsNothing);
    expect(prefs.getString(communityCardDoneKey), '1');
  });

  testWidgets('never on the demo Home', (tester) async {
    await _card(tester, prefs: ready, host: demoHost);
    expect(find.text(title), findsNothing);
  });

  testWidgets('shown only once', (tester) async {
    await _card(tester, prefs: {...ready, communityCardDoneKey: '1'});
    expect(find.text(title), findsNothing);
  });
}
