import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/domain/readiness.dart';
import 'package:beyondrep/features/progress/domain/workout_history_models.dart';
import 'package:beyondrep/features/progress/workout_history_state.dart';
import 'package:beyondrep/features/train/active_workout_state.dart';
import 'package:beyondrep/features/train/train_page.dart';
import 'package:beyondrep/features/train/train_library_state.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fake_health_overview.dart';
import '../support/health_overview_fixtures.dart';

class _Actions implements WorkoutActions {
  final started = <String>[];

  @override
  startPlan(String planUuid) {
    started.add(planUuid);
    throw StateError('synthetic: stop before navigation');
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected call: ${invocation.memberName}');
}

class _Failing extends FakeHealthOverviewController {
  _Failing() : super(null);

  @override
  Future<HealthOverview?> build() async => throw StateError('read failed');
}

Section<ReadinessOverview> _ready(int value) => SectionData(
  ReadinessOverview(
    result: ReadinessReady(
      Readiness(
        value: value,
        band: readinessBandOf(value),
        parts: const [
          ReadinessPart(input: ReadinessInput.hrv, score: 40, weight: .5),
          ReadinessPart(input: ReadinessInput.sleep, score: 50, weight: .5),
        ],
      ),
    ),
    hasHrv: true,
    hasRestingHr: false,
    hasSleep: true,
    hrvVsNormal: null,
    restingHrVsNormal: null,
    hrvBaseline: null,
    restingHrBaseline: null,
    hrvIsSdnn: true,
  ),
);

final _nowUtc = DateTime.utc(2026, 11, 24, 12);

ExerciseRecord _ex(String uuid, String group) => ExerciseRecord(
  uuid: uuid,
  name: 'Move $uuid',
  muscleGroup: group,
  equipment: 'Barbell',
  movementCategory: 'Push',
  inputMode: 'weightReps',
  isBuiltIn: false,
  updatedAtMs: 0,
);

WorkoutPlanRecord _plan(String uuid, String name, String exercise, int sets) =>
    WorkoutPlanRecord(
      uuid: uuid,
      name: name,
      description: '',
      updatedAtMs: 0,
      exercises: [
        PlanExerciseRecord(
          uuid: '$uuid-0',
          exerciseUuid: exercise,
          position: 0,
          targetSets: sets,
        ),
      ],
    );

/// A completed workout of [group] finished [hoursAgo] before [_nowUtc].
WorkoutSessionRecord _done(String group, int hoursAgo) {
  final at = _nowUtc.subtract(Duration(hours: hoursAgo));
  return WorkoutSessionRecord(
    uuid: 'done-$group',
    name: 'Done',
    status: WorkoutStatus.completed,
    startedAtUtc: at.subtract(const Duration(minutes: 40)),
    completedAtUtc: at,
    originalOffsetMinutes: 0,
    revision: 1,
    exercises: [
      WorkoutExerciseRecord(
        uuid: 'e',
        sessionUuid: 'done-$group',
        nameSnapshot: 'Move',
        muscleSnapshot: group,
        position: 0,
      ),
    ],
    sets: [
      for (var i = 0; i < 10; i++)
        WorkoutSetRecord(
          uuid: 's$i',
          exerciseUuid: 'e',
          position: i,
          kind: WorkoutSetKind.working,
          status: WorkoutSetStatus.completed,
          reps: 10,
          rpe: 8,
          completedAtUtc: at,
        ),
    ],
  );
}

final _exercises = [
  _ex('bench', 'Chest'),
  _ex('squat', 'Legs'),
  _ex('plank', 'Core'),
  _ex('stretch', 'Mobility'),
];

final _push = _plan('push', 'Push day', 'bench', 8);
final _legs = _plan('legs', 'Leg day', 'squat', 12);
final _core = _plan('core', 'Core day', 'plank', 4);
final _mobility = _plan('mob', 'Mobility day', 'stretch', 3);

late _Actions _actions;

Future<void> _pump(
  WidgetTester tester, {
  required List<WorkoutPlanRecord> plans,
  Object? history, // a snapshot, or an error to throw
  FakeHealthOverviewController? health,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  _actions = _Actions();
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: TrainPage()),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fakeHealthOverview(health ?? FakeHealthOverviewController(null)),
        localNowProvider.overrideWithValue(DateTime(2026, 11, 24, 9)),
        progressNowProvider.overrideWithValue(_nowUtc),
        workoutActionsProvider.overrideWithValue(_actions),
        trainLibraryProvider.overrideWith(
          (ref) async =>
              WorkoutLibrarySnapshot(exercises: _exercises, plans: plans),
        ),
        completedWorkoutHistoryProvider.overrideWith((ref) async {
          if (history is WorkoutHistorySnapshot) return history;
          throw StateError('history failed');
        }),
        activeWorkoutProvider.overrideWith(
          (ref) => const AsyncData<ActiveWorkoutView?>(null),
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

WorkoutHistorySnapshot _chestDone() =>
    WorkoutHistorySnapshot(sessions: [_done('Chest', 6)]);

void main() {
  testWidgets('a clear winner shows the card with reason and Start', (
    tester,
  ) async {
    await _pump(tester, plans: [_push, _legs], history: _chestDone());
    expect(find.text('Better fit today'), findsOneWidget);
    expect(
      find.text('Chest still recovering · this plan rests them'),
      findsOneWidget,
    );
    expect(find.text('Start'), findsOneWidget);
    // No outer label that would repeat the plan name and reason: the tag,
    // the card and Start each read once, in order.
    expect(
      find.bySemanticsLabel(RegExp('Better fit today: Leg day')),
      findsNothing,
    );
    expect(
      find.bySemanticsLabel(RegExp('Chest still recovering · this plan')),
      findsOneWidget,
    );
  });

  testWidgets('Start on the card starts the suggested plan', (tester) async {
    await _pump(tester, plans: [_push, _legs], history: _chestDone());
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(_actions.started, ['legs']);
  });

  testWidgets('a low readiness day picks the lightest recovered plan', (
    tester,
  ) async {
    await _pump(
      tester,
      plans: [_push, _legs, _core],
      history: _chestDone(),
      health: FakeHealthOverviewController(overview(readiness: _ready(48))),
    );
    expect(find.text('Better fit today'), findsOneWidget);
    expect(
      find.text(
        'Lightest plan with recovered muscles · keep effort around RPE 7',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(_actions.started, ['core']);
  });

  testWidgets('recovery lines read Recovered and Legs recovering', (
    tester,
  ) async {
    await _pump(
      tester,
      plans: [_push, _legs],
      history: WorkoutHistorySnapshot(sessions: [_done('Legs', 6)]),
    );
    expect(find.textContaining('Legs recovering'), findsOneWidget);
    expect(find.textContaining('Recovered'), findsOneWidget);
    expect(find.text('Move bench\nRecovered'), findsOneWidget);
    expect(find.text('Move squat\nLegs recovering'), findsOneWidget);
  });

  testWidgets('yesterday\'s low readiness does not pick the lightest plan', (
    tester,
  ) async {
    await _pump(
      tester,
      plans: [_push, _legs],
      history: _chestDone(),
      health: FakeHealthOverviewController(
        overview(readiness: _ready(48), readAt: DateTime(2026, 11, 23, 20)),
      ),
    );
    expect(find.textContaining('Lightest plan'), findsNothing);
    expect(find.text('Better fit today'), findsOneWidget);
    expect(
      find.text('Chest still recovering · this plan rests them'),
      findsOneWidget,
    );
  });

  testWidgets('no completed workouts shows no card and no lines', (
    tester,
  ) async {
    await _pump(
      tester,
      plans: [_push, _legs],
      history: const WorkoutHistorySnapshot(sessions: []),
    );
    expect(find.text('Better fit today'), findsNothing);
    expect(find.textContaining('Recovered'), findsNothing);
    expect(find.textContaining('recovering'), findsNothing);
  });

  testWidgets('a history error shows no card and no lines', (tester) async {
    await _pump(tester, plans: [_push, _legs], history: StateError('x'));
    expect(find.text('Better fit today'), findsNothing);
    expect(find.textContaining('Recovered'), findsNothing);
    expect(find.textContaining('recovering'), findsNothing);
    expect(find.text('Push day'), findsOneWidget);
  });

  testWidgets('a plan with only unmapped muscles gets no line', (tester) async {
    await _pump(tester, plans: [_push, _mobility], history: _chestDone());
    expect(find.textContaining('Chest recovering'), findsOneWidget);
    final row = find.ancestor(
      of: find.text('Mobility day'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: row.first, matching: find.textContaining('ecover')),
      findsNothing,
    );
  });

  testWidgets('a health overview error still shows plan fit', (tester) async {
    await _pump(
      tester,
      plans: [_push, _legs],
      history: _chestDone(),
      health: _Failing(),
    );
    expect(find.text('Better fit today'), findsOneWidget);
    expect(find.textContaining('Chest recovering'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('fits 2x text at 390 px, $brightness', (tester) async {
      await _pump(
        tester,
        plans: [_push, _legs],
        history: _chestDone(),
        textScale: 2,
        brightness: brightness,
      );
      // The Train header row already overflows by 204 px at 2x on `main`;
      // the new card and recovery lines must add no other exception.
      Object? error;
      while ((error = tester.takeException()) != null) {
        expect('$error', contains('overflowed by 204 pixels'));
      }
      await tester.scrollUntilVisible(find.text('Start'), 300);
      expect(find.text('Better fit today'), findsOneWidget);
    });
  }
}
