import 'dart:io';

import 'package:beyondrep/core/design/beyondrep_theme.dart';
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
  equipment: const ['barbell', 'bench'],
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
    cat('builtin.v1.squat', 'Back squat'),
  ],
  templates: const [],
  programs: const [],
);

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
    CatalogState state,
  ) async {
    // Tall enough that the lazy list builds every row.
    tester.view.physicalSize = const Size(800, 4000);
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
          theme: BeyondRepTheme.build(Brightness.light),
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

  testWidgets('picking a local exercise does not write', (tester) async {
    await open(tester, ready());
    final before = definitions();
    final updatedBefore = store
        .box<ExerciseDefinitionEntity>()
        .query(ExerciseDefinitionEntity_.uuid.equals('builtin.v1.squat'))
        .build()
        .findFirst()!
        .updatedAtMs;

    await tester.tap(find.text('Back squat'));
    await tester.pumpAndSettle();

    expect(picked?.uuid, 'builtin.v1.squat');
    expect(definitions(), before);
    final after = store
        .box<ExerciseDefinitionEntity>()
        .query(ExerciseDefinitionEntity_.uuid.equals('builtin.v1.squat'))
        .build()
        .findFirst()!;
    expect(after.updatedAtMs, updatedBefore);
    expect(after.catalogVersion, 1);
  });

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
}
