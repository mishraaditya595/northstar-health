import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/app/beyondrep_app.dart';
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
import 'package:beyondrep/features/train/active_workout_state.dart';
import 'package:beyondrep/features/train/train_library_state.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';

import '../support/fake_account_auth.dart';
import '../support/fake_health_summary.dart';

// Wednesday 25 Nov 2026. The program starts on Monday.
final programWednesday = DateTime(2026, 11, 25, 10);

WorkoutPlanRecord programPlan(String id, String name, int exercises) =>
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

WorkoutSessionRecord programFinished(String date) => WorkoutSessionRecord(
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
ProgramWeek programWeekFixture({
  DateTime? now,
  List<String?> plans = const ['push', null, 'pull', null, 'legs', null, null],
  List<WorkoutSessionRecord> sessions = const [],
  String? activated = '2026-11-23',
}) {
  final today = now ?? programWednesday;
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
    'push': programPlan('push', 'Push day', 3),
    'pull': programPlan('pull', 'Pull day', 2),
    'legs': programPlan('legs', 'Leg day', 4),
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

class ProgramStartCall {
  ProgramStartCall(this.program, this.expectedPlanUuid, this.missedDate);
  final TrainingProgramRecord program;
  final String? expectedPlanUuid;
  final DateTime? missedDate;
}

class FakeProgramActions implements WorkoutActions {
  final calls = <ProgramStartCall>[];
  Object? failWith;

  @override
  WorkoutSessionRecord startProgramDay(
    TrainingProgramRecord program, {
    required String? expectedPlanUuid,
    DateTime? missedDate,
  }) {
    if (failWith != null) throw failWith!;
    calls.add(ProgramStartCall(program, expectedPlanUuid, missedDate));
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

/// Pumps Today with the program card on a fixed [week], at any size.
/// [shell] wraps it in the app's adaptive shell (tab bar or rail).
Future<FakeProgramActions> pumpTodayProgram(
  WidgetTester tester, {
  ProgramWeek? week,
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
  double textScale = 1,
  bool shell = false,
}) async {
  final actions = FakeProgramActions();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/today',
    routes: [
      GoRoute(
        path: '/today',
        builder: (_, _) => shell
            ? AdaptiveShell(location: '/today', child: const TodayPage())
            : const Scaffold(body: TodayPage()),
      ),
      for (final path in ['/train', '/train/workout', '/train/program/:uuid'])
        GoRoute(
          path: path,
          builder: (_, _) => const Scaffold(body: Text('Route')),
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
        localNowProvider.overrideWithValue(
          week?.localToday ?? programWednesday,
        ),
        activeWorkoutProvider.overrideWithValue(const AsyncData(null)),
        workoutActionsProvider.overrideWithValue(actions),
        programWeekProvider.overrideWith((ref) => week),
        trainLibraryProvider.overrideWith(
          (ref) async => const WorkoutLibrarySnapshot(exercises: [], plans: []),
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
  return actions;
}
