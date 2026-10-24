import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:northstar_health/core/design/northstar_theme.dart';
import 'package:northstar_health/features/train/plan_editor_page.dart';
import 'package:northstar_health/features/train/train_page.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_library_repository.dart';
import 'package:northstar_health/features/workouts/domain/workout_library_models.dart';
import 'package:northstar_health/features/workouts/domain/workout_library_repository.dart';

class FakeLibrary implements WorkoutLibraryRepository {
  final planRecords = <String, WorkoutPlanRecord>{};
  int archiveCalls = 0;
  final exercise = const ExerciseRecord(
    uuid: 'builtin.v1.bench-press',
    name: 'Barbell bench press',
    muscleGroup: 'Chest',
    equipment: 'Barbell',
    movementCategory: 'Push',
    inputMode: 'reps_load',
    isBuiltIn: true,
    updatedAtMs: 1,
  );

  @override
  void ensureCatalogSeeded() {}

  @override
  List<ExerciseRecord> listExercises({bool includeArchived = false}) => [
    exercise,
  ];

  @override
  ExerciseRecord saveCustomExercise({
    required String uuid,
    required String name,
    required String muscleGroup,
    required String equipment,
    int? expectedUpdatedAtMs,
  }) => throw UnimplementedError();

  @override
  void archiveCustomExercise(String uuid) => throw UnimplementedError();

  @override
  WorkoutPlanRecord? getPlan(String uuid) => planRecords[uuid];

  @override
  List<WorkoutPlanRecord> listPlans() => planRecords.values.toList();

  @override
  WorkoutPlanRecord savePlan({
    required String uuid,
    required String name,
    required String description,
    required List<PlanExerciseRecord> exercises,
    int? expectedUpdatedAtMs,
  }) {
    final original = planRecords[uuid];
    if ((original == null && expectedUpdatedAtMs != null) ||
        (original != null && original.updatedAtMs != expectedUpdatedAtMs)) {
      throw const PlanEditConflict();
    }
    final record = WorkoutPlanRecord(
      uuid: uuid,
      name: name,
      description: description,
      updatedAtMs: (original?.updatedAtMs ?? 0) + 1,
      exercises: List.unmodifiable(exercises),
    );
    planRecords[uuid] = record;
    return record;
  }

  @override
  void archivePlan(String uuid, {required int expectedUpdatedAtMs}) {
    final original = planRecords[uuid];
    if (original == null || original.updatedAtMs != expectedUpdatedAtMs) {
      throw const PlanEditConflict();
    }
    archiveCalls++;
    planRecords.remove(uuid);
  }
}

void main() {
  testWidgets('user creates a local training plan from an empty Train page', (
    tester,
  ) async {
    final fake = FakeLibrary();
    final router = GoRouter(
      initialLocation: '/train',
      routes: [
        GoRoute(path: '/train', builder: (_, _) => const TrainPage()),
        GoRoute(
          path: '/train/plans/new',
          builder: (_, _) => const PlanEditorPage(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [workoutLibraryRepositoryProvider.overrideWithValue(fake)],
        child: MaterialApp.router(
          theme: NorthstarTheme.build(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No plans yet'), findsOneWidget);

    await tester.tap(find.text('Create training plan'));
    await tester.pumpAndSettle();
    expect(find.text('PLAN THE WORK'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Push day');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Barbell bench press').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('3 sets'), findsOneWidget);

    await tester.ensureVisible(find.text('Save plan offline'));
    await tester.pumpAndSettle();
    // ensureVisible can align to the exact bottom edge of the test viewport.
    // Move the list farther so the simulated tap hits the button.
    await tester.drag(find.byType(ListView).last, const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save plan offline'));
    await tester.pumpAndSettle();

    expect(fake.planRecords.values.single.name, 'Push day');
    expect(
      fake.planRecords.values.single.exercises.single.exerciseUuid,
      'builtin.v1.bench-press',
    );
    expect(find.text('Push day'), findsOneWidget);
  });

  testWidgets('editor changes an existing plan without losing its exercises', (
    tester,
  ) async {
    final fake = FakeLibrary();
    fake.planRecords['existing'] = const WorkoutPlanRecord(
      uuid: 'existing',
      name: 'Upper A',
      description: '',
      updatedAtMs: 7,
      exercises: [
        PlanExerciseRecord(
          uuid: 'item-a',
          exerciseUuid: 'builtin.v1.bench-press',
          position: 0,
          targetSets: 3,
          targetRepsMax: 12,
        ),
      ],
    );
    final router = GoRouter(
      initialLocation: '/train/plans/existing/edit',
      routes: [
        GoRoute(path: '/train', builder: (_, _) => const TrainPage()),
        GoRoute(
          path: '/train/plans/:id/edit',
          builder: (_, _) => const PlanEditorPage(planUuid: 'existing'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [workoutLibraryRepositoryProvider.overrideWithValue(fake)],
        child: MaterialApp.router(
          theme: NorthstarTheme.build(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(' · up to 12 reps'), findsNothing);
    expect(find.textContaining('up to 12 reps'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Upper B');
    await tester.ensureVisible(find.text('Save plan offline'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save plan offline'));
    await tester.pumpAndSettle();
    expect(fake.planRecords['existing']!.name, 'Upper B');
    expect(fake.planRecords['existing']!.exercises.single.uuid, 'item-a');
    expect(fake.planRecords['existing']!.updatedAtMs, 8);
  });

  testWidgets(
    'conflict gives reload action and warns before discarding edits',
    (tester) async {
      final fake = FakeLibrary();
      fake.planRecords['existing'] = const WorkoutPlanRecord(
        uuid: 'existing',
        name: 'Version 1',
        description: '',
        updatedAtMs: 4,
        exercises: [],
      );
      final router = GoRouter(
        initialLocation: '/train/plans/existing/edit',
        routes: [
          GoRoute(path: '/train', builder: (_, _) => const TrainPage()),
          GoRoute(
            path: '/train/plans/:id/edit',
            builder: (_, _) => const PlanEditorPage(planUuid: 'existing'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [workoutLibraryRepositoryProvider.overrideWithValue(fake)],
          child: MaterialApp.router(
            theme: NorthstarTheme.build(Brightness.dark),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      fake.planRecords['existing'] = const WorkoutPlanRecord(
        uuid: 'existing',
        name: 'Newer version',
        description: '',
        updatedAtMs: 5,
        exercises: [],
      );
      await tester.enterText(find.byType(TextField).first, 'Stale edit');
      await tester.ensureVisible(find.text('Save plan offline'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -150));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save plan offline'));
      await tester.pumpAndSettle();
      expect(find.text('Reload latest plan'), findsOneWidget);
      expect(fake.planRecords['existing']!.name, 'Newer version');
      await tester.tap(find.text('Reload latest plan'));
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Reload latest plan'), findsOneWidget);
      await tester.tap(find.text('Reload latest plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.text('Newer version'), findsOneWidget);
      expect(find.text('Reload latest plan'), findsNothing);
    },
  );

  testWidgets('stale archiving is rejected; current archiving is allowed', (
    tester,
  ) async {
    final fake = FakeLibrary();
    fake.planRecords['existing'] = const WorkoutPlanRecord(
      uuid: 'existing',
      name: 'Original',
      description: '',
      updatedAtMs: 4,
      exercises: [],
    );
    final router = GoRouter(
      initialLocation: '/train/plans/existing/edit',
      routes: [
        GoRoute(path: '/train', builder: (_, _) => const TrainPage()),
        GoRoute(
          path: '/train/plans/:id/edit',
          builder: (_, _) => const PlanEditorPage(planUuid: 'existing'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [workoutLibraryRepositoryProvider.overrideWithValue(fake)],
        child: MaterialApp.router(
          theme: NorthstarTheme.build(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    fake.planRecords['existing'] = const WorkoutPlanRecord(
      uuid: 'existing',
      name: 'Updated externally',
      description: '',
      updatedAtMs: 5,
      exercises: [],
    );
    await tester.tap(find.byTooltip('Archive plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(fake.archiveCalls, 0);
    expect(find.text('Reload latest plan'), findsOneWidget);
    await tester.tap(find.text('Reload latest plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Archive plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(fake.archiveCalls, 1);
    expect(fake.planRecords, isEmpty);
  });

  testWidgets('unsaved back navigation requires explicit confirmation', (
    tester,
  ) async {
    final fake = FakeLibrary();
    final router = GoRouter(
      initialLocation: '/train',
      routes: [
        GoRoute(path: '/train', builder: (_, _) => const TrainPage()),
        GoRoute(
          path: '/train/plans/new',
          builder: (_, _) => const PlanEditorPage(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [workoutLibraryRepositoryProvider.overrideWithValue(fake)],
        child: MaterialApp.router(
          theme: NorthstarTheme.build(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create training plan'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Draft');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('PLAN THE WORK'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.text('No plans yet'), findsOneWidget);
    expect(fake.planRecords, isEmpty);
  });
}
