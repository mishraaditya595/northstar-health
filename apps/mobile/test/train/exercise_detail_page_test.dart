import 'dart:io';

import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/storage/objectbox_store_provider.dart';
import 'package:beyondrep/features/catalog/application/catalog_providers.dart';
import 'package:beyondrep/features/catalog/data/catalog_repository.dart';
import 'package:beyondrep/features/catalog/domain/catalog_models.dart';
import 'package:beyondrep/features/progress/muscle_map.dart';
import 'package:beyondrep/features/progress/muscle_recovery.dart';
import 'package:beyondrep/features/train/exercise_catalog_page.dart';
import 'package:beyondrep/features/train/exercise_detail_page.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../catalog/catalog_fixtures.dart';

const rdl = CatalogExercise(
  id: 'builtin.v1.rdl',
  name: 'Romanian deadlift',
  aliases: ['RDL', 'Stiff-leg deadlift'],
  muscleGroup: 'Legs',
  primaryMuscles: ['hamstrings', 'glutes'],
  secondaryMuscles: ['lowerBack'],
  equipment: ['barbell'],
  category: 'hinge',
  mode: 'reps_load',
  cues: ['Push the hips back', 'Keep the bar close'],
  retired: false,
);

const plank = CatalogExercise(
  id: 'builtin.v1.plank',
  name: 'Plank',
  aliases: [],
  muscleGroup: 'Core',
  primaryMuscles: ['abs'],
  secondaryMuscles: [],
  equipment: ['bodyweight'],
  category: 'core',
  mode: 'duration',
  cues: [],
  retired: false,
);

void main() {
  late Directory directory;
  late Store store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-detail-');
    store = Store(getObjectBoxModel(), directory: directory.path);
    store.box<ExerciseDefinitionEntity>().put(
      ExerciseDefinitionEntity(
        uuid: 'custom-1',
        name: 'Sled push',
        muscleGroup: 'Legs',
        equipment: 'Sled',
        createdAtMs: 1,
        updatedAtMs: 1,
      ),
    );
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  Future<void> open(
    WidgetTester tester,
    String id, {
    Brightness brightness = Brightness.light,
    double textScale = 1,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final catalog = CatalogState(
      snapshot: catalogSnapshotOf([rdl, plank]),
      status: CatalogStatus.ready,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          catalogRepositoryProvider.overrideWithValue(
            StubCatalogRepository(catalog, directory),
          ),
        ],
        child: MaterialApp(
          theme: BeyondRepTheme.build(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: ExerciseDetailPage(exerciseId: id),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a catalogue exercise shows muscles, details and cues', (
    tester,
  ) async {
    await open(tester, rdl.id, size: const Size(390, 2400));

    expect(find.text('Romanian deadlift'), findsWidgets);
    expect(find.text('RDL · Stiff-leg deadlift'), findsOneWidget);
    expect(find.text('Primary'), findsOneWidget);
    expect(find.text('Secondary'), findsOneWidget);
    expect(find.text('Hamstrings'), findsOneWidget);
    expect(find.text('Glutes'), findsOneWidget);
    expect(find.text('Lower back'), findsOneWidget);
    expect(find.text('Barbell'), findsOneWidget);
    expect(find.text('Hinge'), findsOneWidget);
    expect(find.text('Reps and weight'), findsOneWidget);
    expect(find.text('Push the hips back'), findsOneWidget);
    expect(find.text('Keep the bar close'), findsOneWidget);
    expect(find.byType(MuscleMap), findsNWidgets(2));
  });

  testWidgets('the body maps have one label and the name is a header', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await open(tester, rdl.id, size: const Size(390, 2400));
    expect(
      find.bySemanticsLabel(
        'Body map: Hamstrings, Glutes; secondary Lower back',
      ),
      findsOneWidget,
    );
    final heading = tester.getSemantics(find.text('Romanian deadlift').last);
    expect(heading.flagsCollection.isHeader, isTrue);
    handle.dispose();
  });

  testWidgets('the body maps draw primary at full and secondary at half', (
    tester,
  ) async {
    await open(tester, rdl.id);
    for (final map in tester.widgetList<MuscleMap>(find.byType(MuscleMap))) {
      expect(map.recovery.loadOf(Muscle.hamstrings), 1);
      expect(map.recovery.loadOf(Muscle.glutes), 1);
      expect(map.recovery.loadOf(Muscle.lowerBack), 0.5);
      expect(map.recovery.loadOf(Muscle.quads), 0);
    }
  });

  testWidgets('a timed exercise says Time and shows no secondary list', (
    tester,
  ) async {
    await open(tester, plank.id);
    expect(find.text('Time'), findsOneWidget);
    expect(find.text('Primary'), findsOneWidget);
    expect(find.text('Secondary'), findsNothing);
    expect(find.text('Abs'), findsOneWidget);
  });

  testWidgets('a custom exercise shows the custom text and no maps', (
    tester,
  ) async {
    await open(tester, 'custom-1');
    expect(find.text('Sled push'), findsWidgets);
    expect(
      find.text("Custom exercise. Muscles aren't mapped yet."),
      findsOneWidget,
    );
    expect(find.text('Legs'), findsOneWidget);
    expect(find.text('Sled'), findsOneWidget);
    expect(find.byType(MuscleMap), findsNothing);
    expect(find.text('Primary'), findsNothing);
  });

  testWidgets('an unknown id says it is not available', (tester) async {
    await open(tester, 'builtin.v1.nope');
    expect(find.text("This exercise isn't available."), findsOneWidget);
    expect(find.byType(MuscleMap), findsNothing);
  });

  for (final brightness in Brightness.values) {
    for (final id in [rdl.id, 'custom-1']) {
      testWidgets('no overflow at 390x844, text scale 2.0, '
          '${brightness.name}, $id', (tester) async {
        await open(tester, id, brightness: brightness, textScale: 2.0);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView), const Offset(0, -2000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('the Exercises page opens the detail', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const ExerciseCatalogPage()),
        GoRoute(
          path: '/train/exercises/:id',
          builder: (_, state) =>
              ExerciseDetailPage(exerciseId: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          catalogRepositoryProvider.overrideWithValue(
            StubCatalogRepository(
              CatalogState(
                snapshot: catalogSnapshotOf([rdl, plank]),
                status: CatalogStatus.ready,
              ),
              directory,
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: BeyondRepTheme.build(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Romanian deadlift'));
    await tester.pumpAndSettle();

    expect(find.text('Primary'), findsOneWidget);
    expect(find.text('Push the hips back'), findsOneWidget);
  });
}
