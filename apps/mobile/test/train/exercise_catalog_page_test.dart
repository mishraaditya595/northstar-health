import 'dart:io';

import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/inputs.dart';
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

CatalogSnapshot snapshot() => catalogSnapshotOf([
  catalogExercise(
    'builtin.v1.hip-thrust',
    'Hip thrust',
    aliases: ['Hip bridge'],
  ),
  catalogExercise('builtin.v1.row', 'Barbell row'),
]);

CatalogState ready() =>
    CatalogState(snapshot: snapshot(), status: CatalogStatus.ready);

const noCacheFailureCopy =
    "Couldn't download the exercise library. Check your connection and try again.";
const failureCopy =
    "Couldn't update the exercise library. Showing the saved copy.";

// The list's own scrollable, not the horizontal chip row above it.
final listScrollable = find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

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
    Size size = const Size(800, 1000),
  }) async {
    tester.view.physicalSize = size;
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
    await open(tester, ready(), size: const Size(800, 2000));

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
    await open(tester, ready(), size: const Size(800, 2000));
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
      size: const Size(800, 2000),
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
      expect(find.byType(NsListCard), findsWidgets);
    });
  }

  testWidgets(
    'pull to refresh failure with no cache says the download failed',
    (tester) async {
      await open(
        tester,
        const CatalogState(status: CatalogStatus.unavailable),
        outcome: CatalogRefreshOutcome.failed,
      );

      await tester.fling(find.byType(ListView), const Offset(0, 500), 2000);
      await tester.pumpAndSettle();

      expect(find.text(noCacheFailureCopy), findsOneWidget);
      expect(find.text(failureCopy), findsNothing);
      expect(find.text('Barbell bench press'), findsOneWidget);
    },
  );

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
    for (final status in [CatalogStatus.unavailable, CatalogStatus.ready]) {
      testWidgets('no overflow at 390x844, text scale 2.0, ${brightness.name}, '
          '${status.name}', (tester) async {
        await open(
          tester,
          status == CatalogStatus.ready
              ? ready()
              : const CatalogState(status: CatalogStatus.unavailable),
          brightness: brightness,
          textScale: 2,
          size: const Size(390, 844),
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Custom only'),
          200,
          scrollable: listScrollable,
        );
        await tester.tap(find.text('Custom only'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  CatalogState many() => CatalogState(
    snapshot: manyExercisesSnapshot(),
    status: CatalogStatus.ready,
  );

  Future<void> pickLegsAndDumbbell(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(NsChip, 'Legs'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NsDropdown<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dumbbell').last);
    await tester.pumpAndSettle();
  }

  testWidgets('group chip and equipment dropdown filter 250 rows', (
    tester,
  ) async {
    await open(tester, many(), size: const Size(800, 4000));

    await pickLegsAndDumbbell(tester);

    expect(find.text('Synthetic 026 Legs dumbbell'), findsOneWidget);
    expect(find.text('Synthetic 056 Legs dumbbell'), findsOneWidget);
    expect(find.text('Synthetic 000 Chest barbell'), findsNothing);
    expect(find.text('Synthetic 002 Legs cable'), findsNothing);
    expect(find.text('Barbell bench press'), findsNothing);

    await tester.enterText(find.byType(TextField), '056');
    await tester.pumpAndSettle();
    expect(find.text('Synthetic 056 Legs dumbbell'), findsOneWidget);
    expect(find.text('Synthetic 026 Legs dumbbell'), findsNothing);

    await tester.tap(find.widgetWithText(NsChip, 'All'));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic 056 Legs dumbbell'), findsOneWidget);
  });

  testWidgets('the list is lazy', (tester) async {
    await open(tester, many(), size: const Size(800, 1000));

    expect(find.text('Barbell bench press'), findsOneWidget);
    expect(find.text('Synthetic 249 Shoulders bodyweight'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Synthetic 249 Shoulders bodyweight'),
      800,
      scrollable: listScrollable,
    );
    expect(find.text('Synthetic 249 Shoulders bodyweight'), findsOneWidget);
  });

  testWidgets('custom exercises still show under All', (tester) async {
    await open(tester, many());
    await tester.enterText(find.byType(TextField), 'sled');
    await tester.pumpAndSettle();
    expect(find.text('Sled push'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('filters have no overflow at text scale 2.0, '
        '${brightness.name}', (tester) async {
      await open(
        tester,
        many(),
        brightness: brightness,
        textScale: 2,
        size: const Size(390, 844),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(NsChip, 'Legs'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(listScrollable, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
