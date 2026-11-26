import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/dialogs.dart';
import 'package:beyondrep/features/account/account_auth_controller.dart';
import 'package:beyondrep/features/account/account_auth_provider.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/programs/application/program_providers.dart';
import 'package:beyondrep/features/programs/domain/program_models.dart';
import 'package:beyondrep/features/programs/domain/program_status.dart';
import 'package:beyondrep/features/progress/domain/workout_history_models.dart';
import 'package:beyondrep/features/progress/workout_history_state.dart';
import 'package:beyondrep/features/today/today_page.dart';
import 'package:beyondrep/features/today/today_program_card.dart';
import 'package:beyondrep/features/train/active_workout_state.dart';
import 'package:beyondrep/features/train/train_library_state.dart';
import 'package:beyondrep/features/workouts/domain/live_workout_engine.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';

import '../support/fake_account_auth.dart';
import '../support/fake_health_summary.dart';

// Wednesday 25 Nov 2026. The program starts on Monday.
final _wednesday = DateTime(2026, 11, 25, 10);

WorkoutPlanRecord _plan(String id, String name, int exercises) =>
    WorkoutPlanRecord(
      uuid: id,
      name: name,
      description: '',
      updatedAtMs: 1,
      exercises: [
        for (var i = 0; i < exercises; i++)
          PlanExerciseRecord(
            uuid: '$id-$i',
            exerciseUuid: 'squat',
            position: i,
            targetSets: 3,
          ),
      ],
    );

WorkoutSessionRecord _finished(String date) => WorkoutSessionRecord(
  uuid: 'done-$date',
  name: 'Done',
  status: WorkoutStatus.completed,
  startedAtUtc: DateTime.utc(2026, 11, 23),
  originalOffsetMinutes: 0,
  revision: 1,
  programUuid: 'prog',
  programDayLocalDate: date,
);

/// Monday push, Tuesday rest, Wednesday pull (2 exercises), Thursday rest,
/// Friday legs, then rest.
ProgramWeek _week({
  DateTime? now,
  List<String?> plans = const ['push', null, 'pull', null, 'legs', null, null],
  List<WorkoutSessionRecord> sessions = const [],
  String? activated = '2026-11-23',
}) {
  final today = now ?? _wednesday;
  final program = TrainingProgramRecord(
    uuid: 'prog',
    name: 'Synthetic program',
    description: '',
    sourceId: 'prog.x',
    sourceRelease: 4,
    firstDayWeekday: 1,
    isActive: true,
    activatedLocalDate: activated,
    updatedAtMs: 0,
    days: [
      for (var i = 0; i < 7; i++)
        ProgramDayRecord(uuid: 'd$i', dayIndex: i, planUuid: plans[i]),
    ],
  );
  final library = {
    'push': _plan('push', 'Push day', 3),
    'pull': _plan('pull', 'Pull day', 2),
    'legs': _plan('legs', 'Leg day', 4),
  };
  final available = library.keys.toSet();
  return ProgramWeek(
    program: program,
    localToday: today,
    rows: programWeekStatus(
      program: program,
      localToday: today,
      sessions: sessions,
      availablePlanUuids: available,
    ),
    plans: library,
    latestMissed: latestMissed(
      program: program,
      localToday: today,
      sessions: sessions,
      availablePlanUuids: available,
    ),
    nextTraining: nextTraining(
      program: program,
      localToday: today,
      availablePlanUuids: available,
    ),
  );
}

class _Call {
  _Call(this.program, this.expectedPlanUuid, this.missedDate);
  final TrainingProgramRecord program;
  final String? expectedPlanUuid;
  final DateTime? missedDate;
}

class _FakeActions implements WorkoutActions {
  final calls = <_Call>[];
  Object? failWith;

  @override
  WorkoutSessionRecord startProgramDay(
    TrainingProgramRecord program, {
    required String? expectedPlanUuid,
    DateTime? missedDate,
  }) {
    if (failWith != null) throw failWith!;
    calls.add(_Call(program, expectedPlanUuid, missedDate));
    return WorkoutSessionRecord(
      uuid: 'new',
      name: 'New',
      status: WorkoutStatus.inProgress,
      startedAtUtc: DateTime.utc(2026, 11, 25),
      originalOffsetMinutes: 0,
      revision: 1,
    );
  }

  @override
  WorkoutSessionRecord startPlan(String planUuid) =>
      throw StateError('not expected');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late List<String> pushed;
  late _FakeActions actions;

  Future<void> show(
    WidgetTester tester, {
    ProgramWeek? week,
    AsyncValue<ActiveWorkoutView?> unfinished = const AsyncData(null),
    double textScale = 1,
    Brightness brightness = Brightness.dark,
    List<WorkoutPlanRecord> libraryPlans = const [],
    void Function()? onWeekBuilt,
  }) async {
    actions = _FakeActions();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    pushed = [];
    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        GoRoute(
          path: '/today',
          builder: (_, _) => const Scaffold(body: TodayPage()),
        ),
        for (final path in ['/train', '/train/workout', '/train/program/:uuid'])
          GoRoute(
            path: path,
            builder: (_, state) {
              pushed.add(state.uri.path);
              return const Scaffold(body: Text('Route'));
            },
          ),
      ],
    );
    addTearDown(router.dispose);
    final auth = AccountAuthController(
      FakeAuthApi(),
      FakeBoundAccountStore(),
      FakeDeletionRecoveryStore(),
      cleanupStore: FakeConfirmedDeletionCleanupStore(),
      localCleaner: FakeLocalAccountDataCleaner(),
    );
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localNowProvider.overrideWithValue(week?.localToday ?? _wednesday),
          activeWorkoutProvider.overrideWithValue(unfinished),
          workoutActionsProvider.overrideWithValue(actions),
          programWeekProvider.overrideWith((ref) {
            onWeekBuilt?.call();
            return week;
          }),
          trainLibraryProvider.overrideWith(
            (ref) async => WorkoutLibrarySnapshot(
              exercises: const [],
              plans: libraryPlans,
            ),
          ),
          completedWorkoutHistoryProvider.overrideWith(
            (ref) async => const WorkoutHistorySnapshot(sessions: []),
          ),
          fakeHealthSummary(
            FakeHealthSummaryController(
              const HealthNotConnected(
                availability: HealthAvailability.available,
                platform: HealthPlatformKind.appleHealth,
              ),
            ),
          ),
          accountAuthControllerProvider.overrideWithValue(auth),
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

  group('estimatedPlanMinutes', () {
    test('rounds to five minutes with a floor of five', () {
      expect(estimatedPlanMinutes(_plan('a', 'A', 1)), 5);
      expect(estimatedPlanMinutes(_plan('a', 'A', 2)), 15);
      expect(estimatedPlanMinutes(_plan('a', 'A', 4)), 25);
    });
  });

  testWidgets('a training day shows the workout and Start opens the logger', (
    tester,
  ) async {
    await show(tester, week: _week());
    expect(find.text('TODAY · SYNTHETIC PROGRAM'), findsOneWidget);
    expect(find.text('Pull day'), findsWidgets);
    expect(find.text('2 exercises · about 15 min'), findsOneWidget);
    expect(find.text('Start workout'), findsNothing); // the old hero
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(actions.calls, hasLength(1));
    expect(actions.calls.single.expectedPlanUuid, 'pull');
    expect(actions.calls.single.missedDate, isNull);
    expect(pushed, ['/train/workout']);
  });

  testWidgets('Open program goes to the program screen', (tester) async {
    await show(tester, week: _week());
    await tester.tap(find.text('Open program'));
    await tester.pumpAndSettle();
    expect(pushed, ['/train/program/prog']);
  });

  testWidgets('a rest day says so and points at the next workout', (
    tester,
  ) async {
    await show(tester, week: _week(now: DateTime(2026, 11, 24, 10)));
    expect(find.text('Rest day'), findsOneWidget);
    expect(find.text('Next: Wednesday · Pull day'), findsOneWidget);
    expect(find.text('Start'), findsNothing);
    expect(find.text('Open program'), findsOneWidget);
  });

  testWidgets('after today is done: Done for today and the next workout', (
    tester,
  ) async {
    await show(
      tester,
      week: _week(sessions: [_finished('2026-11-23'), _finished('2026-11-25')]),
    );
    expect(find.text('Done for today'), findsOneWidget);
    expect(find.text('Next: Friday · Leg day'), findsOneWidget);
    expect(find.text('Start'), findsNothing);
    expect(find.textContaining('Missed'), findsNothing);
  });

  testWidgets('the missed line starts that day with its date after '
      'confirming', (tester) async {
    await show(tester, week: _week());
    expect(find.text('Missed Monday: Push day'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Missed Monday: Push day. Start it now'),
      findsOneWidget,
    );
    await tester.tap(find.text('Missed Monday: Push day'));
    await tester.pumpAndSettle();
    expect(find.text('Start Push day for Monday?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(actions.calls, isEmpty);

    await tester.tap(find.text('Missed Monday: Push day'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(NsDialog), matching: find.text('Start')),
    );
    await tester.pumpAndSettle();
    expect(actions.calls.single.missedDate, DateTime(2026, 11, 23));
    expect(actions.calls.single.expectedPlanUuid, 'push');
    expect(pushed, ['/train/workout']);
  });

  testWidgets('the missed line shows the most recent miss only', (
    tester,
  ) async {
    // Friday: Monday and Wednesday are both missed.
    await show(tester, week: _week(now: DateTime(2026, 11, 27, 9)));
    expect(find.text('Missed Wednesday: Pull day'), findsOneWidget);
    expect(find.text('Missed Monday: Push day'), findsNothing);
  });

  testWidgets('a new week clears the line', (tester) async {
    await show(tester, week: _week(now: DateTime(2026, 11, 30, 9)));
    expect(find.textContaining('Missed'), findsNothing);
    expect(find.text('Push day'), findsWidgets);
  });

  testWidgets('a change at the tap shows a message and starts nothing', (
    tester,
  ) async {
    await show(tester, week: _week());
    // Set after the page is built, so the tap hits the failure.
    actions.failWith = ProgramDayChanged();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(
      find.text("Today's workout changed. Check it and try again."),
      findsOneWidget,
    );
    expect(pushed, isEmpty);
  });

  testWidgets('any other start failure also refreshes the program state', (
    tester,
  ) async {
    var builds = 0;
    await show(tester, week: _week(), onWeekBuilt: () => builds++);
    final before = builds;
    actions.failWith = StateError('could not start');
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not start this workout'), findsOneWidget);
    expect(builds, greaterThan(before));
  });

  testWidgets('a double tap on Start starts once', (tester) async {
    await show(tester, week: _week());
    await tester.tap(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(actions.calls, hasLength(1));
    expect(pushed, ['/train/workout']);
    expect(find.textContaining('Could not start'), findsNothing);
  });

  testWidgets('a double tap on the missed line confirms and starts once', (
    tester,
  ) async {
    await show(tester, week: _week());
    await tester.tap(find.text('Missed Monday: Push day'));
    await tester.tap(find.text('Missed Monday: Push day'));
    await tester.pumpAndSettle();
    expect(find.text('Start Push day for Monday?'), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(NsDialog), matching: find.text('Start')),
    );
    await tester.pumpAndSettle();
    expect(actions.calls, hasLength(1));
  });

  testWidgets('a changed missed day shows the day message', (tester) async {
    await show(tester, week: _week());
    actions.failWith = ProgramDayChanged();
    await tester.tap(find.text('Missed Monday: Push day'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(NsDialog), matching: find.text('Start')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('This day changed. Check it and try again.'),
      findsOneWidget,
    );
    expect(pushed, isEmpty);
  });

  testWidgets('without an active program the Next up hero is unchanged', (
    tester,
  ) async {
    await show(tester, libraryPlans: [_plan('a', 'Own plan', 2)]);
    expect(find.text('NEXT UP'), findsOneWidget);
    expect(find.text('Own plan'), findsOneWidget);
    expect(find.textContaining('TODAY ·'), findsNothing);
    expect(find.text('Start workout'), findsOneWidget);
  });

  testWidgets('an unfinished workout comes before the program', (tester) async {
    await show(
      tester,
      week: _week(),
      unfinished: AsyncData(
        ActiveWorkoutView(
          WorkoutSessionRecord(
            uuid: 'open',
            name: 'Morning lift',
            status: WorkoutStatus.paused,
            startedAtUtc: DateTime.utc(2026, 11, 25, 7),
            originalOffsetMinutes: 0,
            revision: 2,
          ),
          const WorkoutRecoveryCheckpoint(
            sessionUuid: 'open',
            checkpointRevision: 2,
          ),
        ),
      ),
    );
    expect(find.text('UNFINISHED WORKOUT'), findsOneWidget);
    expect(find.text('Morning lift'), findsOneWidget);
    expect(find.textContaining('TODAY ·'), findsNothing);
    expect(find.textContaining('Missed'), findsNothing);
  });

  testWidgets('a recovery error also comes before the program', (tester) async {
    await show(
      tester,
      week: _week(),
      unfinished: AsyncError(StateError('x'), StackTrace.empty),
    );
    expect(find.text('Workout recovery needs attention'), findsOneWidget);
    expect(find.textContaining('TODAY ·'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('text scale 2.0 with the missed line (${brightness.name})', (
      tester,
    ) async {
      await show(tester, week: _week(), textScale: 2, brightness: brightness);
      expect(tester.takeException(), isNull);
      // The 48 dp header buttons push the line past the first build extent.
      await tester.scrollUntilVisible(
        find.text('Missed Monday: Push day'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Missed Monday: Push day'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Open program'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
