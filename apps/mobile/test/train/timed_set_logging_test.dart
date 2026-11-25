import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/storage/objectbox_store_provider.dart';
import 'package:beyondrep/features/progress/data/objectbox_workout_history_repository.dart';
import 'package:beyondrep/features/progress/domain/workout_history_models.dart';
import 'package:beyondrep/features/train/active_workout_page.dart';
import 'package:beyondrep/features/train/timed_sets.dart';
import 'package:beyondrep/features/workouts/data/objectbox_live_workout_engine.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_library_repository.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_repository.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:beyondrep/objectbox.g.dart';

const sessionId = 'session-timed';

var clockNow = DateTime.utc(2026, 11, 26, 10);

/// The stopwatch reads wall-clock time, which tester.pump does not move.
Future<void> advance(WidgetTester tester, Duration d) async {
  clockNow = clockNow.add(d);
  await tester.pump(d);
}

void main() {
  late Directory directory;
  late Store store;
  late GoRouter router;
  late ObjectBoxWorkoutRepository repository;

  setUp(() {
    clockNow = DateTime.utc(2026, 11, 26, 10);
    directory = Directory.systemTemp.createTempSync('beyondrep-timed-ui-');
    store = Store(getObjectBoxModel(), directory: directory.path);
    repository = ObjectBoxWorkoutRepository(store);
    ObjectBoxWorkoutLibraryRepository(store).ensureCatalogSeeded();
    router = GoRouter(
      initialLocation: '/train/workout',
      routes: [
        GoRoute(
          path: '/train/workout',
          builder: (_, _) => const ActiveWorkoutPage(),
        ),
        GoRoute(path: '/train', builder: (_, _) => const Text('Train')),
      ],
    );
  });

  tearDown(() {
    router.dispose();
    store.close();
    directory.deleteSync(recursive: true);
  });

  /// A workout with a plank (timed) and optionally a squat, each with one
  /// planned set.
  void seed({bool squat = false}) {
    ObjectBoxLiveWorkoutEngine(store).startWorkout(
      sessionUuid: sessionId,
      quickName: 'Mixed',
      startedAtUtc: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      originalOffsetMinutes: 0,
    );
    var position = 0;
    void add(String id, String definition, String name) {
      repository.addExercise(
        WorkoutExerciseRecord(
          uuid: 'exercise-$id',
          sessionUuid: sessionId,
          definitionUuid: definition,
          nameSnapshot: name,
          position: position++,
        ),
      );
      repository.saveSet(
        sessionUuid: sessionId,
        expectedRevision: repository.getSession(sessionId)!.revision,
        set: WorkoutSetRecord(
          uuid: 'set-$id',
          exerciseUuid: 'exercise-$id',
          position: 0,
          kind: WorkoutSetKind.working,
          status: WorkoutSetStatus.planned,
        ),
      );
    }

    add('plank', 'builtin.v1.plank', 'Plank');
    if (squat) add('squat', 'builtin.v1.squat', 'Squat');
  }

  Future<void> show(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double textScale = 1,
    Size size = const Size(800, 3000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          timedSetClockProvider.overrideWithValue(() => clockNow),
          workoutHistoryRepositoryProvider.overrideWithValue(
            _ImmediateHistoryRepository(store),
          ),
        ],
        child: MaterialApp.router(
          theme: BeyondRepTheme.build(brightness),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  WorkoutSetEntity saved(String uuid) => store
      .box<WorkoutSetEntity>()
      .query(WorkoutSetEntity_.uuid.equals(uuid))
      .build()
      .findFirst()!;

  testWidgets('a plank card shows TIMER and SEC with no reps or load field', (
    tester,
  ) async {
    seed();
    await show(tester);
    expect(find.text('TIMER'), findsOneWidget);
    expect(find.text('SEC'), findsOneWidget);
    expect(find.text('REPS'), findsNothing);
    expect(find.byKey(const ValueKey('seconds-set-plank')), findsOneWidget);
    expect(find.byKey(const ValueKey('reps-set-plank')), findsNothing);
    expect(find.byKey(const ValueKey('weight-set-plank')), findsNothing);
    expect(find.byTooltip('Start timer for set 1'), findsOneWidget);
  });

  testWidgets('a session started from a template logs the plank in seconds', (
    tester,
  ) async {
    ObjectBoxLiveWorkoutEngine(store).startTemplateWorkout(
      sessionUuid: sessionId,
      name: 'Template day',
      rows: const [
        PlanExerciseRecord(
          uuid: 'row-plank',
          exerciseUuid: 'builtin.v1.plank',
          position: 0,
          targetSets: 1,
          targetDurationSeconds: 45,
        ),
      ],
      startedAtUtc: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      originalOffsetMinutes: 0,
    );
    await show(tester);
    expect(find.text('SEC'), findsOneWidget);
    expect(find.text('REPS'), findsNothing);
    final set = store.box<WorkoutSetEntity>().getAll().single;
    expect(find.byKey(ValueKey('seconds-${set.uuid}')), findsOneWidget);
  });

  testWidgets('the rest chip starts at the planned rest of each exercise', (
    tester,
  ) async {
    ObjectBoxLiveWorkoutEngine(store).startTemplateWorkout(
      sessionUuid: sessionId,
      name: 'Template day',
      rows: const [
        PlanExerciseRecord(
          uuid: 'r1',
          exerciseUuid: 'builtin.v1.squat',
          position: 0,
          targetSets: 1,
          targetRepsMin: 5,
          targetRepsMax: 5,
          restSeconds: 0,
        ),
        PlanExerciseRecord(
          uuid: 'r2',
          exerciseUuid: 'builtin.v1.plank',
          position: 1,
          targetSets: 1,
          targetDurationSeconds: 30,
          restSeconds: 60,
        ),
        PlanExerciseRecord(
          uuid: 'r3',
          exerciseUuid: 'builtin.v1.bench-press',
          position: 2,
          targetSets: 1,
          targetRepsMin: 5,
          targetRepsMax: 5,
        ),
      ],
      startedAtUtc: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      originalOffsetMinutes: 0,
    );
    await show(tester);
    expect(find.text('Rest: off'), findsOneWidget);
    expect(find.text('Rest: 60s'), findsOneWidget);
    expect(find.text('Rest: 90s'), findsOneWidget);
  });

  testWidgets('typing 45 and recording saves seconds and no reps', (
    tester,
  ) async {
    seed();
    await show(tester);
    await tester.enterText(
      find.byKey(const ValueKey('seconds-set-plank')),
      '45',
    );
    await tester.tap(find.byTooltip('Save set 1'));
    await tester.pumpAndSettle();
    final set = saved('set-plank');
    expect(set.durationSeconds, 45);
    expect(set.reps, isNull);
    expect(set.loadGrams, isNull);
    expect(set.status, 'completed');
  });

  testWidgets('start, three seconds, stop fills 3', (tester) async {
    seed();
    await show(tester);
    await tester.tap(find.byTooltip('Start timer for set 1'));
    await tester.pump();
    await advance(tester, const Duration(seconds: 3));
    expect(find.byTooltip('Stop timer for set 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Stop timer for set 1'));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('seconds-set-plank')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, '3');
    expect(find.byTooltip('Start timer for set 1'), findsOneWidget);
  });

  testWidgets('stopping inside the first second records 1, never 0', (
    tester,
  ) async {
    seed();
    await show(tester);
    await tester.tap(find.byTooltip('Start timer for set 1'));
    await advance(tester, const Duration(milliseconds: 200));
    await tester.tap(find.byTooltip('Stop timer for set 1'));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('seconds-set-plank')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, '1');
  });

  testWidgets('recording while the timer runs saves the shown value', (
    tester,
  ) async {
    seed();
    await show(tester);
    await tester.tap(find.byTooltip('Start timer for set 1'));
    await tester.pump();
    await advance(tester, const Duration(seconds: 2));
    await tester.tap(find.byTooltip('Save set 1'));
    await tester.pumpAndSettle();
    expect(saved('set-plank').durationSeconds, 2);
    expect(find.byTooltip('Start timer for set 1'), findsOneWidget);
    await advance(tester, const Duration(seconds: 5));
    expect(saved('set-plank').durationSeconds, 2);
  });

  testWidgets('a running timer on one set does not block saving another', (
    tester,
  ) async {
    seed();
    repository.saveSet(
      sessionUuid: sessionId,
      expectedRevision: repository.getSession(sessionId)!.revision,
      set: const WorkoutSetRecord(
        uuid: 'set-plank-2',
        exerciseUuid: 'exercise-plank',
        position: 1,
        kind: WorkoutSetKind.working,
        status: WorkoutSetStatus.planned,
      ),
    );
    await show(tester);
    await tester.tap(find.byTooltip('Start timer for set 1'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('seconds-set-plank-2')),
      '30',
    );
    await tester.tap(find.byTooltip('Save set 2'));
    await tester.pumpAndSettle();
    expect(saved('set-plank-2').durationSeconds, 30);
    expect(find.byTooltip('Stop timer for set 1'), findsOneWidget);
  });

  testWidgets('skipping a set while its timer runs stops the timer', (
    tester,
  ) async {
    seed();
    await show(tester);
    await tester.tap(find.byTooltip('Start timer for set 1'));
    await tester.pump();
    await advance(tester, const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Set 1 options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip set'));
    await tester.pumpAndSettle();
    await advance(tester, const Duration(seconds: 3));
    expect(saved('set-plank').status, 'skipped');
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('seconds-set-plank')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, isEmpty);
    expect(find.byTooltip('Start timer for set 1'), findsOneWidget);
    expect(find.byTooltip('Stop timer for set 1'), findsNothing);
  });

  testWidgets('a squat card in the same session is unchanged', (tester) async {
    seed(squat: true);
    await show(tester);
    expect(find.text('REPS'), findsOneWidget);
    expect(find.text('SEC'), findsOneWidget);
    expect(find.byKey(const ValueKey('reps-set-squat')), findsOneWidget);
    expect(find.byKey(const ValueKey('weight-set-squat')), findsOneWidget);
    expect(find.byKey(const ValueKey('seconds-set-squat')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('reps-set-squat')), '5');
    await tester.tap(find.byTooltip('Save set 1').last);
    await tester.pumpAndSettle();
    expect(saved('set-squat').reps, 5);
    expect(saved('set-squat').durationSeconds, isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('timed card fits at text scale 2.0 in ${brightness.name}', (
      tester,
    ) async {
      seed();
      await show(
        tester,
        brightness: brightness,
        textScale: 2,
        size: const Size(390, 844),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('seconds-set-plank')),
        200,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('seconds-set-plank')), findsOneWidget);
    });
  }

  testWidgets('Use previous from a 45 s set fills the seconds field', (
    tester,
  ) async {
    // History: a finished plank workout; then a new workout starts.
    final engine = ObjectBoxLiveWorkoutEngine(store);
    engine.startWorkout(
      sessionUuid: 'old',
      quickName: 'Old',
      startedAtUtc: DateTime.now().toUtc().subtract(const Duration(days: 2)),
      originalOffsetMinutes: 0,
    );
    repository.addExercise(
      const WorkoutExerciseRecord(
        uuid: 'old-plank',
        sessionUuid: 'old',
        definitionUuid: 'builtin.v1.plank',
        nameSnapshot: 'Plank',
        position: 0,
      ),
    );
    repository.saveSet(
      sessionUuid: 'old',
      expectedRevision: repository.getSession('old')!.revision,
      set: WorkoutSetRecord(
        uuid: 'old-set',
        exerciseUuid: 'old-plank',
        position: 0,
        kind: WorkoutSetKind.working,
        status: WorkoutSetStatus.completed,
        durationSeconds: 45,
        completedAtUtc: DateTime.now().toUtc().subtract(
          const Duration(days: 2),
        ),
      ),
    );
    engine.finishWorkout(
      'old',
      expectedRevision: repository.getSession('old')!.revision,
      finishedAtUtc: DateTime.now().toUtc().subtract(
        const Duration(days: 2, minutes: -10),
      ),
    );
    seed();
    await show(tester);
    expect(find.byTooltip('Use previous 45 s'), findsOneWidget);
    await tester.tap(find.byTooltip('Use previous 45 s'));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('seconds-set-plank')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, '45');
  });

  test('isTimedExercise follows the definition, then the sets', () {
    const plank = WorkoutExerciseRecord(
      uuid: 'e',
      sessionUuid: 's',
      definitionUuid: 'builtin.v1.plank',
      nameSnapshot: 'Plank',
      position: 0,
    );
    ExerciseRecord definition(String mode) => ExerciseRecord(
      uuid: 'builtin.v1.plank',
      name: 'Plank',
      muscleGroup: 'Core',
      equipment: 'Bodyweight',
      movementCategory: 'Core',
      inputMode: mode,
      isBuiltIn: true,
      updatedAtMs: 1,
    );
    const timedSet = WorkoutSetRecord(
      uuid: 'a',
      exerciseUuid: 'e',
      position: 0,
      kind: WorkoutSetKind.working,
      status: WorkoutSetStatus.planned,
      durationSeconds: 30,
    );
    expect(
      isTimedExercise(plank, const [], {
        'builtin.v1.plank': definition('duration'),
      }),
      isTrue,
    );
    expect(
      isTimedExercise(
        plank,
        const [timedSet],
        {'builtin.v1.plank': definition('reps_load')},
      ),
      isFalse,
    );
    expect(isTimedExercise(plank, const [timedSet], {}), isTrue);
    expect(isTimedExercise(plank, const [], {}), isFalse);
  });
}

class _ImmediateHistoryRepository implements WorkoutHistoryRepository {
  _ImmediateHistoryRepository(Store store)
    : _native = ObjectBoxWorkoutHistoryRepository(store);
  final ObjectBoxWorkoutHistoryRepository _native;
  @override
  WorkoutHistorySnapshot readCompleted() => _native.readCompleted();
  @override
  Future<WorkoutHistorySnapshot> readCompletedAsync() async => readCompleted();
}
