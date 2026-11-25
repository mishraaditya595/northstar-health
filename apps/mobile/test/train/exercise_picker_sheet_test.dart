import 'dart:io';

import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/inputs.dart';
import 'package:beyondrep/core/storage/objectbox_store_provider.dart';
import 'package:beyondrep/features/catalog/application/catalog_providers.dart';
import 'package:beyondrep/features/catalog/data/catalog_repository.dart';
import 'package:beyondrep/features/catalog/domain/catalog_models.dart';
import 'package:beyondrep/features/train/exercise_picker_sheet.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';
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
  catalogExercise('builtin.v1.squat', 'Back squat'),
]);

// The list's own scrollable, not the horizontal chip row above it.
final listScrollable = find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

void main() {
  late Directory directory;
  late Store store;
  ExerciseRecord? picked;
  var pickedCalls = 0;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-picker-');
    store = Store(getObjectBoxModel(), directory: directory.path);
    picked = null;
    pickedCalls = 0;
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  Future<StubCatalogRepository> open(
    WidgetTester tester,
    CatalogState state, {
    Brightness brightness = Brightness.light,
    double textScale = 1,
    Size size = const Size(800, 4000),
  }) async {
    // Tall enough that the lazy list builds every row.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = StubCatalogRepository(state, directory);
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
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () async {
                  picked = await showExercisePicker(
                    context,
                    ref,
                    title: 'ADD EXERCISE',
                  );
                  pickedCalls++;
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    return repository;
  }

  CatalogState ready() =>
      CatalogState(snapshot: snapshot(), status: CatalogStatus.ready);

  int definitions() => store.box<ExerciseDefinitionEntity>().count();

  testWidgets('lists catalogue-only exercises when cache is ready', (
    tester,
  ) async {
    await open(tester, ready());

    expect(find.text('Hip thrust'), findsOneWidget);
    expect(find.text('Back squat'), findsOneWidget);
    expect(find.text('Barbell bench press'), findsOneWidget);
    expect(find.textContaining('hasn\'t downloaded'), findsNothing);
  });

  testWidgets('picking a catalogue-only exercise materializes it and returns '
      'the record', (tester) async {
    await open(tester, ready());
    final before = definitions();
    expect(
      store
          .box<ExerciseDefinitionEntity>()
          .query(ExerciseDefinitionEntity_.uuid.equals('builtin.v1.hip-thrust'))
          .build()
          .count(),
      0,
    );

    await tester.tap(find.text('Hip thrust'));
    await tester.pumpAndSettle();

    expect(pickedCalls, 1);
    expect(picked?.uuid, 'builtin.v1.hip-thrust');
    expect(picked?.name, 'Hip thrust');
    expect(picked?.equipment, 'Barbell, Bench');
    expect(definitions(), before + 1);
    final entity = store
        .box<ExerciseDefinitionEntity>()
        .query(ExerciseDefinitionEntity_.uuid.equals('builtin.v1.hip-thrust'))
        .build()
        .findFirst()!;
    expect(entity.catalogVersion, 4);
    expect(entity.isBuiltIn, isTrue);
  });

  ExerciseDefinitionEntity entity(String id) => store
      .box<ExerciseDefinitionEntity>()
      .query(ExerciseDefinitionEntity_.uuid.equals(id))
      .build()
      .findFirst()!;

  testWidgets('an exercise already copied from this release is not written', (
    tester,
  ) async {
    await open(tester, ready());
    final seeded = entity('builtin.v1.squat')
      ..name = 'Back squat'
      ..muscleGroup = 'Legs'
      ..equipment = 'Barbell, Bench'
      ..movementCategory = 'Hinge'
      ..catalogVersion = 4
      ..primaryMuscles = ['glutes']
      ..updatedAtMs = 42;
    store.box<ExerciseDefinitionEntity>().put(seeded);
    final before = definitions();

    await tester.tap(find.text('Back squat'));
    await tester.pumpAndSettle();

    expect(picked?.uuid, 'builtin.v1.squat');
    expect(definitions(), before);
    expect(entity('builtin.v1.squat').updatedAtMs, 42);
  });

  testWidgets('a renamed exercise in a newer release updates the local name', (
    tester,
  ) async {
    await open(tester, ready());
    expect(entity('builtin.v1.squat').name, 'Barbell back squat');
    expect(entity('builtin.v1.squat').catalogVersion, 1);

    await tester.tap(find.text('Back squat'));
    await tester.pumpAndSettle();

    expect(picked?.name, 'Back squat');
    expect(entity('builtin.v1.squat').name, 'Back squat');
    expect(entity('builtin.v1.squat').catalogVersion, 4);
    expect(entity('builtin.v1.squat').inputMode, 'reps_load');
  });

  testWidgets('a refresh while the sheet is open does not stamp a newer '
      'release on older data', (tester) async {
    final repository = await open(tester, ready());

    await tester.tap(find.text('Hip thrust'));
    await tester.pump();
    repository.emit(
      CatalogState(
        snapshot: catalogSnapshotOf([
          catalogExercise('builtin.v1.hip-thrust', 'Hip thrust v5'),
        ], release: 5),
        status: CatalogStatus.ready,
      ),
    );
    await tester.pumpAndSettle();

    expect(picked?.name, 'Hip thrust', reason: 'the data the user saw');
    expect(entity('builtin.v1.hip-thrust').catalogVersion, 4);
  });

  testWidgets('picking a local-only exercise writes nothing', (tester) async {
    await open(tester, ready());
    final box = store.box<ExerciseDefinitionEntity>();
    box.put(
      ExerciseDefinitionEntity(
        uuid: 'custom-1',
        name: 'Sled push',
        createdAtMs: 1,
        updatedAtMs: 7,
      ),
    );
    // Reopen so the new custom exercise is listed.
    await tester.pumpWidget(const SizedBox());
    await open(tester, ready());
    final before = definitions();
    final bench = entity('builtin.v1.bench-press').updatedAtMs;

    await tester.tap(find.text('Sled push'));
    await tester.pumpAndSettle();
    expect(picked?.uuid, 'custom-1');
    expect(entity('custom-1').updatedAtMs, 7);

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Barbell bench press'));
    await tester.pumpAndSettle();
    expect(picked?.uuid, 'builtin.v1.bench-press');
    expect(entity('builtin.v1.bench-press').updatedAtMs, bench);
    expect(definitions(), before);
  });

  for (final brightness in Brightness.values) {
    testWidgets('no overflow at text scale 2.0 in ${brightness.name}', (
      tester,
    ) async {
      await open(
        tester,
        const CatalogState(status: CatalogStatus.unavailable),
        brightness: brightness,
        textScale: 2,
        size: const Size(390, 844),
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Retry'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Retry'), findsOneWidget);
    });
  }

  testWidgets('dismissing the sheet returns null and writes nothing', (
    tester,
  ) async {
    await open(tester, ready());
    final before = definitions();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(pickedCalls, 1);
    expect(picked, isNull);
    expect(definitions(), before);
  });

  testWidgets('shows unavailable copy and Retry with no cache', (tester) async {
    await open(tester, const CatalogState(status: CatalogStatus.unavailable));

    expect(
      find.text(
        "The exercise library hasn't downloaded yet. "
        'Your own exercises and the basics still work.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Barbell bench press'), findsOneWidget);
  });

  testWidgets('Retry forces a refresh', (tester) async {
    final repository = await open(
      tester,
      const CatalogState(status: CatalogStatus.unavailable),
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(repository.forceCalls, [true]);
  });

  testWidgets('search finds an exercise by alias and says when none match', (
    tester,
  ) async {
    await open(tester, ready());

    await tester.enterText(find.byType(TextField), 'hip bridge');
    await tester.pumpAndSettle();
    expect(find.text('Hip thrust'), findsOneWidget);
    expect(find.text('Back squat'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('No matching exercises.'), findsOneWidget);
  });

  testWidgets('custom exercises appear and archived ones do not', (
    tester,
  ) async {
    final box = store.box<ExerciseDefinitionEntity>();
    box.put(
      ExerciseDefinitionEntity(
        uuid: 'custom-1',
        name: 'Sled push',
        createdAtMs: 1,
        updatedAtMs: 1,
      ),
    );
    box.put(
      ExerciseDefinitionEntity(
        uuid: 'custom-2',
        name: 'Hidden lift',
        createdAtMs: 1,
        updatedAtMs: 1,
        archivedAtMs: 2,
      ),
    );
    await open(tester, ready());
    expect(find.text('Sled push'), findsOneWidget);
    expect(find.text('Hidden lift'), findsNothing);
  });

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
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Synthetic 249 Shoulders bodyweight'), findsOneWidget);
  });

  testWidgets('custom exercises still show under All', (tester) async {
    store.box<ExerciseDefinitionEntity>().put(
      ExerciseDefinitionEntity(
        uuid: 'custom-1',
        name: 'Sled push',
        createdAtMs: 1,
        updatedAtMs: 1,
      ),
    );
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
