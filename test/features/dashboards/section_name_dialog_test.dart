import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/data/database/database.dart';
import 'package:zigdash/data/repositories/section_repo.dart';
import 'package:zigdash/features/home/home_shell.dart';
import 'package:zigdash/features/panels/widgets/edit_grid.dart';
import 'package:zigdash/l10n/app_localizations.dart';

class _Sections implements SectionRepo {
  final created = <({String dashboardId, String name, int sortOrder})>[];

  @override
  Future<List<Section>> getByDashboard(String dashboardId) async => [];

  @override
  Future<String> create({
    required String dashboardId,
    required String name,
    int sortOrder = 0,
  }) async {
    created.add((dashboardId: dashboardId, name: name, sortOrder: sortOrder));
    return 's1';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Sections repo;
  String? renamed;

  setUp(() {
    repo = _Sections();
    renamed = null;
  });

  Widget app() => ProviderScope(
    overrides: [sectionRepoProvider.overrideWithValue(repo)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: Column(
            children: [
              TextButton(
                onPressed: () => addSection(context, ref, 'd1'),
                child: const Text('Add'),
              ),
              TextButton(
                onPressed: () async {
                  renamed = await askSectionName(context, initial: 'Lights');
                },
                child: const Text('Rename'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  for (final keyboard in [false, true]) {
    testWidgets(
      'adding a section closes safely via ${keyboard ? 'keyboard' : 'Save'}',
      (tester) async {
        await tester.pumpWidget(app());
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '  Sensors  ');
        if (keyboard) {
          await tester.testTextInput.receiveAction(TextInputAction.done);
        } else {
          await tester.tap(find.text('Save'));
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(AlertDialog), findsNothing);
        expect(repo.created, [
          (dashboardId: 'd1', name: 'Sensors', sortOrder: 0),
        ]);
      },
    );
  }

  testWidgets(
    'cancelling and reopening the name dialog does not create a section',
    (tester) async {
      await tester.pumpWidget(app());
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Unused');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(repo.created, isEmpty);
      }
    },
  );

  testWidgets('renaming uses the same safe dialog lifecycle', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Lights'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  Lighting  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(renamed, 'Lighting');
  });
}
