import 'dart:io';

import 'package:beyondrep/features/catalog/application/catalog_definition_sync.dart';
import 'package:beyondrep/features/catalog/data/catalog_repository.dart';
import 'package:beyondrep/features/train/train_library_state.dart';
import 'package:beyondrep/core/storage/objectbox_store_provider.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_library_repository.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beyondrep/features/catalog/domain/catalog_models.dart';

import '../catalog/catalog_fixtures.dart';

import 'package:beyondrep/features/catalog/application/catalog_providers.dart';

class CountingLibrary extends ObjectBoxWorkoutLibraryRepository {
  CountingLibrary(super.store);

  int syncCalls = 0;

  @override
  int syncCatalogDefinitions(List<CatalogDefinitionInput> items, int release) {
    syncCalls++;
    return super.syncCatalogDefinitions(items, release);
  }
}

void main() {
  late Directory dir;
  late Store store;
  late CountingLibrary library;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('catalog_def_sync');
    store = Store(getObjectBoxModel(), directory: dir.path);
    library = CountingLibrary(store);
  });

  tearDown(() {
    store.close();
    dir.deleteSync(recursive: true);
  });

  Widget harness(StubCatalogRepository catalog) => ProviderScope(
    overrides: [
      objectBoxStoreProvider.overrideWithValue(store),
      workoutLibraryRepositoryProvider.overrideWithValue(library),
      catalogRepositoryProvider.overrideWithValue(catalog),
    ],
    child: MaterialApp(
      home: CatalogDefinitionSyncHost(
        child: Consumer(
          builder: (context, ref, _) {
            final data = ref.watch(trainLibraryProvider).value;
            final deadlift = data?.exercises
                .where((e) => e.uuid == 'builtin.v1.deadlift')
                .firstOrNull;
            return Text(
              'deadlift ${deadlift?.primaryMuscles.join(',')}'
              '/${deadlift?.secondaryMuscles.join(',')}',
            );
          },
        ),
      ),
    ),
  );

  CatalogState ready(
    List<String> primary,
    List<String> secondary,
    int release,
  ) => CatalogState(
    status: CatalogStatus.ready,
    snapshot: catalogSnapshotOf([
      CatalogExercise(
        id: 'builtin.v1.deadlift',
        name: 'Deadlift',
        aliases: const [],
        muscleGroup: 'Back',
        primaryMuscles: primary,
        secondaryMuscles: secondary,
        equipment: const ['barbell'],
        category: 'hinge',
        mode: 'reps_load',
        cues: const [],
        retired: false,
      ),
    ], release: release),
  );

  testWidgets('a ready snapshot syncs once and the library shows muscles', (
    tester,
  ) async {
    final catalog = StubCatalogRepository(
      ready(['hamstrings', 'glutes'], ['lowerBack'], 1),
      Directory.systemTemp,
    );
    await tester.pumpWidget(harness(catalog));
    await tester.pumpAndSettle();

    expect(library.syncCalls, 1);
    expect(find.text('deadlift hamstrings,glutes/lowerBack'), findsOneWidget);
  });

  testWidgets('no snapshot never touches the library', (tester) async {
    final catalog = StubCatalogRepository(
      const CatalogState(status: CatalogStatus.unavailable),
      Directory.systemTemp,
    );
    await tester.pumpWidget(harness(catalog));
    await tester.pumpAndSettle();

    expect(library.syncCalls, 0);
    expect(find.text('deadlift /'), findsOneWidget);
  });

  testWidgets('an updated snapshot syncs again and refreshes the library', (
    tester,
  ) async {
    final catalog = StubCatalogRepository(
      ready(['hamstrings'], const [], 1),
      Directory.systemTemp,
    );
    await tester.pumpWidget(harness(catalog));
    await tester.pumpAndSettle();
    expect(find.text('deadlift hamstrings/'), findsOneWidget);

    catalog.emit(ready(['hamstrings', 'glutes'], const [], 2));
    await tester.pumpAndSettle();

    expect(library.syncCalls, 2);
    expect(find.text('deadlift hamstrings,glutes/'), findsOneWidget);
  });
}
