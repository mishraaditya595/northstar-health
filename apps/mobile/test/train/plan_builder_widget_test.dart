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
  List<ExerciseRecord> listExercises({bool includeArchived = false}) => [exercise];

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
    final record = WorkoutPlanRecord(
      uuid: uuid,
      name: name,
      description: description,
      updatedAtMs: 1,
      exercises: List.unmodifiable(exercises),
    );
    planRecords[uuid] = record;
    return record;
  }

  @override
  void archivePlan(String uuid) => planRecords.remove(uuid);
}

void main() {
  testWidgets('user creates a local training plan from an empty Train page',
      (tester) async {
    final fake = FakeLibrary();
    final router = GoRouter(initialLocation: '/train', routes: [
      GoRoute(path: '/train', builder: (_, _) => const TrainPage()),
      GoRoute(path: '/train/plans/new', builder: (_, _) => const PlanEditorPage()),
    ]);
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        workoutLibraryRepositoryProvider.overrideWithValue(fake),
      ],
      child: MaterialApp.router(
        theme: NorthstarTheme.build(Brightness.light),
        routerConfig: router,
      ),
    ));
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
    await tester.tap(find.text('Save plan offline'));
    await tester.pumpAndSettle();

    expect(fake.planRecords.values.single.name, 'Push day');
    expect(fake.planRecords.values.single.exercises.single.exerciseUuid,
        'builtin.v1.bench-press');
    expect(find.text('Push day'), findsOneWidget);
  });
}
