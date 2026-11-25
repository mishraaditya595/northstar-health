import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/features/account/account_auth_controller.dart';
import 'package:beyondrep/features/account/account_auth_provider.dart';
import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/domain/readiness.dart';
import 'package:beyondrep/features/progress/domain/workout_history_models.dart';
import 'package:beyondrep/features/progress/workout_history_state.dart';
import 'package:beyondrep/features/today/today_page.dart';
import 'package:beyondrep/features/train/active_workout_state.dart';
import 'package:beyondrep/features/train/train_library_state.dart';
import 'package:beyondrep/features/workouts/domain/live_workout_engine.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';

import '../support/fake_account_auth.dart';
import '../support/fake_health_overview.dart';
import '../support/fake_health_summary.dart';
import '../support/health_overview_fixtures.dart';

// Tuesday 24 Nov 2026, 23:02 local.
final _now = DateTime(2026, 11, 24, 23, 2);

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

WorkoutSessionRecord _done(String id, DateTime atUtc, {String? plan}) =>
    WorkoutSessionRecord(
      uuid: id,
      name: id,
      status: WorkoutStatus.completed,
      startedAtUtc: atUtc.subtract(const Duration(minutes: 40)),
      completedAtUtc: atUtc,
      originalOffsetMinutes: 0,
      revision: 1,
      planUuid: plan,
    );

class _FakeActions implements WorkoutActions {
  final started = <String>[];

  @override
  WorkoutSessionRecord startPlan(String planUuid) {
    started.add(planUuid);
    return _done('new', DateTime.utc(2026, 11, 24));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late List<String> pushed;
  late _FakeActions actions;

  Future<void> show(
    WidgetTester tester, {
    Future<List<WorkoutPlanRecord>>? plans,
    Future<List<WorkoutSessionRecord>>? sessions,
    AsyncValue<ActiveWorkoutView?> unfinished = const AsyncData(null),
    bool settle = true,
    HealthOverview? health,
  }) async {
    actions = _FakeActions();
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    pushed = [];
    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        GoRoute(
          path: '/today',
          builder: (_, _) => const Scaffold(body: TodayPage()),
        ),
        for (final path in [
          '/train',
          '/train/workout',
          '/train/plans/new',
          '/train/plans/:id/edit',
        ])
          GoRoute(
            path: path,
            builder: (_, state) {
              pushed.add(state.uri.path);
              return const Scaffold(body: Text('Train route'));
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
          localNowProvider.overrideWithValue(_now),
          activeWorkoutProvider.overrideWithValue(unfinished),
          workoutActionsProvider.overrideWithValue(actions),
          trainLibraryProvider.overrideWith(
            (ref) async => WorkoutLibrarySnapshot(
              exercises: const [],
              plans: await (plans ?? Future.value(const [])),
            ),
          ),
          completedWorkoutHistoryProvider.overrideWith(
            (ref) async => WorkoutHistorySnapshot(
              sessions: await (sessions ?? Future.value(const [])),
            ),
          ),
          fakeHealthSummary(
            FakeHealthSummaryController(
              health == null
                  ? const HealthNotConnected(
                      availability: HealthAvailability.available,
                      platform: HealthPlatformKind.appleHealth,
                    )
                  : HealthConnected(
                      readAt: _now,
                      platform: HealthPlatformKind.appleHealth,
                    ),
            ),
          ),
          accountAuthControllerProvider.overrideWithValue(auth),
          if (health != null) ...[
            fakeHealthOverview(FakeHealthOverviewController(health)),
            healthOwnerIdProvider.overrideWith((ref) => 'synthetic-owner'),
          ],
        ],
        child: MaterialApp.router(
          theme: BeyondRepTheme.build(Brightness.dark),
          routerConfig: router,
        ),
      ),
    );
    settle ? await tester.pumpAndSettle() : await tester.pump();
  }

  testWidgets('header shows the real date and no demo label', (tester) async {
    await show(tester);
    expect(find.text('TUESDAY · 24 NOV 2026'), findsOneWidget);
    expect(find.textContaining('FICTIONAL'), findsNothing);
    expect(find.textContaining('23 OCT'), findsNothing);
  });

  testWidgets('without plans the hero offers to create one', (tester) async {
    await show(tester);
    expect(find.text('Full Body A'), findsNothing);
    expect(find.text('No plans yet'), findsOneWidget);
    expect(find.textContaining('Around 45 min'), findsNothing);
    await tester.tap(find.text('Create a plan'));
    await tester.pumpAndSettle();
    expect(pushed, ['/train/plans/new']);
  });

  testWidgets('without plans the hero can go to Train', (tester) async {
    await show(tester);
    expect(find.text('Quick workout'), findsNothing);
    await tester.tap(find.text('Go to Train'));
    await tester.pumpAndSettle();
    expect(pushed, ['/train']);
    expect(find.text('Train route'), findsOneWidget);
  });

  testWidgets('Start workout starts the suggested plan', (tester) async {
    await show(tester, plans: Future.value([_plan('a', 'Push day', 2)]));
    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
    expect(actions.started, ['a']);
    expect(pushed, ['/train/workout']);
  });

  testWidgets('a Low readiness day asks before starting; Not now starts '
      'nothing', (tester) async {
    await show(
      tester,
      plans: Future.value([_plan('a', 'Push day', 2)]),
      health: overview(
        readiness: SectionData(
          ReadinessOverview(
            result: ReadinessReady(
              Readiness(
                value: 48,
                band: readinessBandOf(48),
                parts: const [
                  ReadinessPart(
                    input: ReadinessInput.sleep,
                    score: 48,
                    weight: 1,
                  ),
                ],
              ),
            ),
            hasHrv: false,
            hasRestingHr: false,
            hasSleep: true,
            hrvVsNormal: null,
            restingHrVsNormal: null,
            hrvBaseline: null,
            restingHrBaseline: null,
            hrvIsSdnn: true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
    expect(find.text('Recovery is low today'), findsWidgets);
    expect(find.text('Not now'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(actions.started, isEmpty);
    expect(pushed, isEmpty);
  });

  testWidgets('an unfinished workout is offered for resume first', (
    tester,
  ) async {
    await show(
      tester,
      plans: Future.value([_plan('a', 'Push day', 2)]),
      unfinished: AsyncData(
        ActiveWorkoutView(
          WorkoutSessionRecord(
            uuid: 'open',
            name: 'Morning lift',
            status: WorkoutStatus.paused,
            startedAtUtc: DateTime.utc(2026, 11, 24, 7),
            originalOffsetMinutes: 0,
            revision: 2,
          ),
          const WorkoutRecoveryCheckpoint(
            sessionUuid: 'open',
            checkpointRevision: 1,
          ),
        ),
      ),
    );
    expect(find.text('UNFINISHED WORKOUT'), findsOneWidget);
    expect(find.text('Morning lift'), findsOneWidget);
    expect(find.text('Start workout'), findsNothing);
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(actions.started, isEmpty);
    expect(pushed, ['/train/workout']);
  });

  testWidgets('a broken workout recovery is not hidden behind Start', (
    tester,
  ) async {
    await show(
      tester,
      plans: Future.value([_plan('a', 'Push day', 2)]),
      unfinished: AsyncError(StateError('checkpoint'), StackTrace.empty),
    );
    expect(find.text('Workout recovery needs attention'), findsOneWidget);
    expect(find.text('Start workout'), findsNothing);
    await tester.tap(find.text('Open Train'));
    await tester.pumpAndSettle();
    expect(actions.started, isEmpty);
    expect(pushed, ['/train']);
  });

  testWidgets('a failed load offers retry', (tester) async {
    await show(
      tester,
      plans: Future.delayed(Duration.zero, () => throw StateError('disk')),
    );
    expect(find.text('Could not load your plans'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('hero suggests the next saved plan with real facts', (
    tester,
  ) async {
    await show(
      tester,
      plans: Future.value([_plan('a', 'Push day', 4), _plan('b', 'Legs', 5)]),
      sessions: Future.value([
        _done('1', DateTime.utc(2026, 11, 20, 9), plan: 'b'),
        _done('2', DateTime.utc(2026, 11, 23, 9), plan: 'a'),
      ]),
    );
    expect(find.text('NEXT UP'), findsOneWidget);
    expect(find.text('Legs'), findsOneWidget);
    expect(find.text('5 exercises · Last done 20/11/2026'), findsOneWidget);
    expect(find.text('Move'), findsNothing);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(pushed, ['/train/plans/b/edit']);
  });

  testWidgets('a plan never finished says so', (tester) async {
    await show(tester, plans: Future.value([_plan('a', 'Push day', 1)]));
    expect(find.text('1 exercise · Not done yet'), findsOneWidget);
  });

  testWidgets('hero waits for plans instead of guessing', (tester) async {
    final plans = Completer<List<WorkoutPlanRecord>>();
    await show(tester, plans: plans.future, settle: false);
    expect(find.text('No plans yet'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Loading your plans')), findsOneWidget);
    plans.complete(const []);
    await tester.pumpAndSettle();
    expect(find.text('No plans yet'), findsOneWidget);
  });

  testWidgets('no demo energy check-in is shown', (tester) async {
    await show(tester);
    expect(find.text('Energy check-in'), findsNothing);
  });

  testWidgets('this week counts real finished workouts', (tester) async {
    await show(
      tester,
      sessions: Future.value([
        _done('sun', DateTime.utc(2026, 11, 22, 9)),
        _done('tue', DateTime.utc(2026, 11, 24, 9)),
        _done('last-week', DateTime.utc(2026, 11, 19, 9)),
      ]),
    );
    expect(find.text('2 workouts finished this week'), findsOneWidget);
    expect(find.textContaining('planned sessions'), findsNothing);
    // The card reads as one node: each day says whether it was trained.
    expect(
      find.bySemanticsLabel(
        RegExp('Sunday, trained\nMonday\nTuesday, today, trained\nWednesday'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an empty week says so instead of inventing sessions', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('No workouts finished yet this week'), findsOneWidget);
  });
}
