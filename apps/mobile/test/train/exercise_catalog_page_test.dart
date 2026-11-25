import 'dart:io';

import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/page_header.dart';
import 'package:beyondrep/core/storage/objectbox_store_provider.dart';
import 'package:beyondrep/features/catalog/application/catalog_providers.dart';
import 'package:beyondrep/features/catalog/data/catalog_repository.dart';
import 'package:beyondrep/features/catalog/domain/catalog_models.dart';
import 'package:beyondrep/features/train/exercise_catalog_page.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/catalog_fixtures.dart';

CatalogExercise cat(
  String id,
  String name, {
  List<String> aliases = const [],
}) => CatalogExercise(
  id: id,
  name: name,
  aliases: aliases,
  muscleGroup: 'Legs',
  primaryMuscles: const ['glutes'],
  secondaryMuscles: const [],
  equipment: const ['barbell'],
  category: 'hinge',
  mode: 'reps_load',
  cues: const [],
  retired: false,
);

CatalogSnapshot snapshot() => CatalogSnapshot(
  release: 4,
  schemaVersion: 1,
  minAppCatalogSchema: 1,
  publishedAt: '2026-11-26T00:00:00Z',
  sha256: 'a' * 64,
  exercises: [
    cat('builtin.v1.hip-thrust', 'Hip thrust', aliases: ['Hip bridge']),
    cat('builtin.v1.row', 'Barbell row'),
  ],
  templates: const [],
  programs: const [],
);

CatalogState ready() =>
    CatalogState(snapshot: snapshot(), status: CatalogStatus.ready);

const failureCopy =
    "Couldn't update the exercise library. Showing the saved copy.";

void main() {
  late Directory directory;
  late Store store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-catalog-page-');
    store = Store(getObjectBoxModel(), directory: directory.path);
    store.box<ExerciseDefinitionEntity>().put(
      ExerciseDefinitionEntity(
        uuid: 'custom-1',
        name: 'Sled push',
        createdAtMs: 1,
        updatedAtMs: 1,
      ),
    );
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  Future<StubCatalogRepository> open(
    WidgetTester tester,
    CatalogState state, {
    CatalogRefreshOutcome outcome = CatalogRefreshOutcome.updated,
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = StubCatalogRepository(
      state,
      directory,
      outcome: outcome,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          catalogRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: BeyondRepTheme.build(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const ExerciseCatalogPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('shows catalogue exercises with Built-in tag', (tester) async {
    await open(tester, ready());

    expect(find.text('Hip thrust'), findsOneWidget);
    expect(find.text('Barbell row'), findsOneWidget);
    expect(find.text('Sled push'), findsOneWidget);
    expect(find.text('Barbell bench press'), findsOneWidget);
    final hipThrustCard = find.ancestor(
      of: find.text('Hip thrust'),
      matching: find.byType(NsListCard),
    );
    expect(
      find.descendant(of: hipThrustCard, matching: find.byType(NsTag)),
      findsOneWidget,
    );
    final sledCard = find.ancestor(
      of: find.text('Sled push'),
      matching: find.byType(NsListCard),
    );
    expect(
      find.descendant(of: sledCard, matching: find.byType(NsTag)),
      findsNothing,
    );
    expect(find.text('Built-in'), findsWidgets);
  });

  testWidgets('alias search', (tester) async {
    await open(tester, ready());

    await tester.enterText(find.byType(TextField), 'hip bridge');
    await tester.pumpAndSettle();

    expect(find.text('Hip thrust'), findsOneWidget);
    expect(find.text('Barbell row'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('No matching exercises.'), findsOneWidget);
  });

  testWidgets('custom only still filters', (tester) async {
    await open(tester, ready());

    await tester.tap(find.text('Custom only'));
    await tester.pumpAndSettle();

    expect(find.text('Sled push'), findsOneWidget);
    expect(find.text('Hip thrust'), findsNothing);
    expect(find.text('Barbell bench press'), findsNothing);
  });

  testWidgets('custom exercises keep their edit and archive menu', (
    tester,
  ) async {
    await open(tester, ready());
    final menu = find.byTooltip('Exercise actions for Sled push');
    await tester.ensureVisible(menu);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
  });

  testWidgets('unavailable shows retry copy', (tester) async {
    final repository = await open(
      tester,
      const CatalogState(status: CatalogStatus.unavailable),
    );

    expect(
      find.text(
        "The exercise library hasn't downloaded yet. "
        'Your own exercises and the basics still work.',
      ),
      findsOneWidget,
    );
    expect(find.text('Barbell bench press'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(repository.forceCalls, [true]);
  });

  testWidgets('outdated app copy', (tester) async {
    await open(
      tester,
      CatalogState(snapshot: snapshot(), status: CatalogStatus.outdatedApp),
    );
    expect(
      find.text('Update BeyondRep to get the latest exercises.'),
      findsOneWidget,
    );
    expect(find.text('Hip thrust'), findsOneWidget);
  });

  testWidgets('no status copy when ready', (tester) async {
    await open(tester, ready());
    expect(find.textContaining("hasn't downloaded"), findsNothing);
    expect(find.textContaining('Update BeyondRep'), findsNothing);
  });

  for (final outcome in [
    CatalogRefreshOutcome.invalid,
    CatalogRefreshOutcome.failed,
    CatalogRefreshOutcome.notLive,
    CatalogRefreshOutcome.unauthorized,
  ]) {
    testWidgets('pull to refresh ${outcome.name} shows the message and keeps '
        'the list', (tester) async {
      final repository = await open(tester, ready(), outcome: outcome);

      await tester.fling(find.byType(ListView), const Offset(0, 500), 2000);
      await tester.pumpAndSettle();

      expect(repository.forceCalls, [true]);
      expect(find.text(failureCopy), findsOneWidget);
      expect(find.text('Hip thrust'), findsOneWidget);
    });
  }

  for (final outcome in [
    CatalogRefreshOutcome.updated,
    CatalogRefreshOutcome.upToDate,
    CatalogRefreshOutcome.noLiveRelease,
    CatalogRefreshOutcome.outdatedApp,
  ]) {
    testWidgets('pull to refresh ${outcome.name} shows no failure message', (
      tester,
    ) async {
      final repository = await open(tester, ready(), outcome: outcome);

      await tester.fling(find.byType(ListView), const Offset(0, 500), 2000);
      await tester.pumpAndSettle();

      expect(repository.forceCalls, [true]);
      expect(find.text(failureCopy), findsNothing);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('no overflow at text scale 2.0 in ${brightness.name}', (
      tester,
    ) async {
      await open(
        tester,
        const CatalogState(status: CatalogStatus.unavailable),
        brightness: brightness,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Custom only'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
