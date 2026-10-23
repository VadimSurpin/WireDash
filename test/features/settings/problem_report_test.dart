import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:zigdash/features/support/support_details.dart';
import 'package:zigdash/features/support/support_facts.dart';
import 'package:zigdash/l10n/app_localizations.dart';
import 'package:zigdash/core/review/review_launcher.dart';
import 'package:zigdash/features/settings/screens/settings_screen.dart';
import 'package:zigdash/features/support/project_links.dart';

void main() {
  for (final copy in [true, false]) {
    testWidgets('Settings report is manual (copy only: $copy)', (tester) async {
      final saved = openSupportLink;
      addTearDown(() => openSupportLink = saved);
      final opened = <Uri>[];
      openSupportLink = (url) async {
        opened.add(url);
        return true;
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appVersionProvider.overrideWith((ref) async => '3.1.2 (72)'),
            supportDetailsProvider.overrideWith(
              (ref, query) async => SupportDetails(
                appVersion: '3.1.2',
                build: '72',
                openedFrom: query.openedFrom,
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => sendProblemReport(context, ref),
                  child: const Text('Report'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(find.textContaining('Public draft'), findsOneWidget);
      expect(find.text('By email'), findsNothing);
      await tester.tap(find.text(copy ? 'Copy details' : 'On GitHub'));
      await tester.pumpAndSettle();
      if (copy) {
        expect(opened, isEmpty);
      } else {
        expect(opened, hasLength(1));
        expect(opened.single.path, '/VadimSurpin/WireDash/issues/new');
        expect(opened.single.queryParameters['version'], '3.1.2 (72)');
        expect(
          opened.single.queryParameters['details'],
          contains('Settings › Report a problem'),
        );
      }
    });
  }

  test('releases and setup help belong to WireDash', () {
    expect(releasesUrl.toString(), '$projectUrl/releases/latest');
    expect(
      setupGuideUrl.toString(),
      '$projectUrl/blob/HEAD/docs/USER_GUIDE.md',
    );
  });

  test(
    'problem report opens an editable WireDash issue with version and details',
    () {
      const details = 'WireDash 3.1.2 (72)\nLast error: timed out';
      final url = problemReportGithubUrl('3.1.2 (72)', details: details);
      expect(url.scheme, 'https');
      expect(url.host, 'github.com');
      expect(url.path, '/VadimSurpin/WireDash/issues/new');
      expect(url.queryParameters['template'], 'bug_report.yml');
      expect(url.queryParameters['version'], '3.1.2 (72)');
      expect(url.queryParameters['details'], details);
    },
  );

  test(
    'WireDash does not automatically request upstream Play reviews',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final launcher = container.read(reviewLauncherProvider);
      expect(launcher, isA<DisabledReviewLauncher>());
      expect(await launcher.isAvailable(), isFalse);
    },
  );
}
