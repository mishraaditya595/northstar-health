import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/domain/readiness.dart';
import 'package:beyondrep/features/health/widgets/readiness_note.dart';
import 'package:beyondrep/features/train/active_workout_state.dart';
import 'package:beyondrep/features/train/train_library_state.dart';
import 'package:beyondrep/features/train/train_page.dart';
import 'package:beyondrep/features/workouts/domain/live_workout_engine.dart';
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

class _Value<T> extends Notifier<T> {
  _Value(this.initial);
  final T initial;
  @override
  T build() => initial;
  void set(T value) => state = value;
}

NotifierProvider<_Value<T>, T> _value<T>(T initial) =>
    NotifierProvider<_Value<T>, T>(() => _Value(initial));

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

const _notReady = SectionData(
  ReadinessOverview(
    result: ReadinessNotReady(noSleep: true),
    hasHrv: false,
    hasRestingHr: false,
    hasSleep: false,
    hrvVsNormal: null,
    restingHrVsNormal: null,
    hrvBaseline: null,
    restingHrBaseline: null,
    hrvIsSdnn: true,
  ),
);

final _nowProvider = _value(DateTime(2026, 11, 24, 9));
final _ownerProvider = _value<String?>('synthetic-owner');

const _plan = WorkoutPlanRecord(
  uuid: 'plan-1',
  name: 'Push day',
  description: '',
  updatedAtMs: 0,
  exercises: [],
);

late _Actions _actions;
late ProviderContainer _container;
late FakeHealthOverviewController _controller;

Future<void> _pump(
  WidgetTester tester,
  HealthOverview? health, {
  AsyncValue<ActiveWorkoutView?> active = const AsyncData(null),
}) async {
  _actions = _Actions();
  _controller = FakeHealthOverviewController(health);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: TrainPage()),
      ),
    ],
  );
  addTearDown(router.dispose);
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  _container = ProviderContainer(
    overrides: [
      fakeHealthOverview(_controller),
      healthOwnerIdProvider.overrideWith((ref) => ref.watch(_ownerProvider)),
      localNowProvider.overrideWith((ref) => ref.watch(_nowProvider)),
      workoutActionsProvider.overrideWithValue(_actions),
      trainLibraryProvider.overrideWith(
        (ref) async =>
            const WorkoutLibrarySnapshot(exercises: [], plans: [_plan]),
      ),
      activeWorkoutProvider.overrideWith((ref) => active),
    ],
  );
  addTearDown(_container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container,
      child: MaterialApp.router(
        theme: BeyondRepTheme.build(Brightness.light),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapStart(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Start Push day'));
  await tester.pumpAndSettle();
}

HealthOverview _low() => overview(readiness: _ready(48));

void main() {
  testWidgets('first low-day start shows the note, the second does not', (
    tester,
  ) async {
    await _pump(tester, _low());
    await _tapStart(tester);
    expect(find.text('Recovery is low today'), findsOneWidget);
    expect(find.textContaining('Your plans are not changed'), findsNWidgets(2));
    expect(_actions.started, isEmpty);
    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
    expect(_actions.started, ['plan-1']);

    await _tapStart(tester);
    expect(_actions.started, ['plan-1', 'plan-1']);
    expect(find.text('Not now'), findsNothing);
  });

  testWidgets('an unfinished workout blocks the start before the note', (
    tester,
  ) async {
    await _pump(
      tester,
      _low(),
      active: AsyncData(
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
    await _tapStart(tester);
    expect(find.text('Not now'), findsNothing);
    expect(find.textContaining('Could not start this workout'), findsOneWidget);
    expect(_actions.started, isEmpty);
    expect(_container.read(readinessStartNoteShownProvider), isNull);
  });

  testWidgets('Not now starts nothing and marks the note shown', (
    tester,
  ) async {
    await _pump(tester, _low());
    await _tapStart(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(_actions.started, isEmpty);

    await _tapStart(tester);
    expect(find.text('Not now'), findsNothing);
    expect(_actions.started, ['plan-1']);
  });

  testWidgets('dismissing the note counts as Not now', (tester) async {
    await _pump(tester, _low());
    await _tapStart(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Not now'), findsNothing);
    expect(_actions.started, isEmpty);
  });

  testWidgets('a low overview read yesterday does not gate today', (
    tester,
  ) async {
    await _pump(
      tester,
      overview(readiness: _ready(48), readAt: DateTime(2026, 11, 23, 22)),
    );
    await _tapStart(tester);
    expect(find.text('Not now'), findsNothing);
    expect(_actions.started, ['plan-1']);
    expect(_container.read(readinessStartNoteShownProvider), isNull);
  });

  testWidgets('the next day shows the note again', (tester) async {
    await _pump(tester, _low());
    await _tapStart(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    _container.read(_nowProvider.notifier).set(DateTime(2026, 11, 25, 7));
    _controller.replace(
      overview(readiness: _ready(48), readAt: DateTime(2026, 11, 25, 7)),
    );
    await tester.pump();
    await _tapStart(tester);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('another owner sees the note again', (tester) async {
    await _pump(tester, _low());
    await _tapStart(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    _container.read(_ownerProvider.notifier).set('other-owner');
    await tester.pump();
    await _tapStart(tester);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('no owner starts without the note', (tester) async {
    await _pump(tester, _low());
    _container.read(_ownerProvider.notifier).set(null);
    await tester.pump();
    await _tapStart(tester);
    expect(find.text('Not now'), findsNothing);
    expect(_actions.started, ['plan-1']);
  });

  for (final (name, health) in <(String, HealthOverview?)>[
    ('Fair', overview(readiness: _ready(64))),
    ('Good', overview(readiness: _ready(82))),
    ('NotReady', overview(readiness: _notReady)),
    ('a gap', overview(readiness: const SectionGap(MetricGap.noData))),
    ('not connected', null),
  ]) {
    testWidgets('$name never shows the note', (tester) async {
      await _pump(tester, health);
      await _tapStart(tester);
      expect(find.text('Not now'), findsNothing);
      expect(_actions.started, ['plan-1']);
    });
  }

  testWidgets('the workout store sees only the normal start call', (
    tester,
  ) async {
    await _pump(tester, _low());
    await _tapStart(tester);
    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
    // _Actions throws on every call except startPlan, so any other write
    // (including health or readiness persistence) would surface here.
    expect(_actions.started, ['plan-1']);
    expect(tester.takeException(), isNull);
  });
}
