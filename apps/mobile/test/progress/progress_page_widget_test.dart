import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:northstar_health/core/design/northstar_theme.dart';
import 'package:northstar_health/core/storage/objectbox_store_provider.dart';
import 'package:northstar_health/features/progress/progress_page.dart';
import 'package:northstar_health/features/progress/workout_history_state.dart';
import 'package:northstar_health/features/progress/data/objectbox_workout_history_repository.dart';
import 'package:northstar_health/features/progress/domain/workout_history_models.dart';
import 'package:northstar_health/features/train/active_workout_page.dart';
import 'package:northstar_health/features/today/today_page.dart';
import 'package:northstar_health/features/account/account_auth_provider.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_outbox.dart';

import '../support/fake_account_auth.dart';

import 'package:northstar_health/features/progress/workout_history_detail_page.dart';
import 'package:northstar_health/features/workouts/data/objectbox_live_workout_engine.dart';
import 'package:northstar_health/features/workouts/data/workout_entities.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_repository.dart';
import 'package:northstar_health/features/workouts/domain/workout_models.dart';
import 'package:northstar_health/objectbox.g.dart';

/// Progress now stacks overview, calendar and body map above the history, so
/// lower sections need a tall viewport to be built, as they are when scrolled.
void tallView(WidgetTester tester, {double? width}) {
  final view = tester.view;
  view.devicePixelRatio = 1;
  view.physicalSize = Size(width ?? 900, 4200);
  addTearDown(view.resetPhysicalSize);
  addTearDown(view.resetDevicePixelRatio);
}

void main() {
  late Directory directory;
  late Store store;
  late GoRouter router;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('northstar-progress-ui-');
    store = Store(getObjectBoxModel(), directory: directory.path);
    router = GoRouter(
      initialLocation: '/progress',
      routes: [
        GoRoute(
          path: '/train',
          builder: (_, _) => const Scaffold(body: Text('Train')),
        ),
        GoRoute(
          path: '/train/workout',
          builder: (_, _) => const ActiveWorkoutPage(),
        ),
        GoRoute(
          path: '/today',
          builder: (_, _) => const Scaffold(body: TodayPage()),
        ),
        GoRoute(
          path: '/progress',
          builder: (_, _) => const Scaffold(body: ProgressPage()),
        ),
        GoRoute(
          path: '/progress/workouts/:id',
          builder: (_, state) => WorkoutHistoryDetailPage(
            sessionUuid: state.pathParameters['id']!,
          ),
        ),
      ],
    );
  });

  tearDown(() {
    router.dispose();
    store.close();
    directory.deleteSync(recursive: true);
  });

  void writeWorkout(
    String id, {
    bool finish = true,
    bool pause = false,
    int? loadGrams = 62500,
    int? reps = 8,
    DateTime? startedAtUtc,
  }) {
    final started =
        startedAtUtc ??
        DateTime.now().toUtc().subtract(const Duration(hours: 2));
    // Only the route-driven completion uses the production cloud outbox.
    // Supply canonical UUIDs there; other read-only test fixtures remain local.
    final sessionId = id == 'finishing'
        ? '00000000-0000-4000-8000-000000000101'
        : id;
    final movementId = id == 'finishing'
        ? '00000000-0000-4000-8000-000000000201'
        : 'movement-$id';
    final setId = id == 'finishing'
        ? '00000000-0000-4000-8000-000000000301'
        : 'set-$id';
    final engine = ObjectBoxLiveWorkoutEngine(store);
    final editor = ObjectBoxWorkoutRepository(store);
    engine.startWorkout(
      sessionUuid: sessionId,
      quickName: 'Workout $id',
      startedAtUtc: started,
      originalOffsetMinutes: 330,
    );
    editor.addExercise(
      WorkoutExerciseRecord(
        uuid: movementId,
        sessionUuid: sessionId,
        definitionUuid: 'builtin.v1.bench-press',
        nameSnapshot: 'Bench press',
        position: 0,
      ),
    );
    final active = editor.getSession(sessionId)!;
    editor.saveSet(
      sessionUuid: sessionId,
      expectedRevision: active.revision,
      set: WorkoutSetRecord(
        uuid: setId,
        exerciseUuid: movementId,
        position: 0,
        kind: WorkoutSetKind.working,
        status: WorkoutSetStatus.completed,
        reps: reps,
        loadGrams: loadGrams,
        completedAtUtc: started.add(const Duration(minutes: 5)),
      ),
    );
    if (finish) {
      engine.finishWorkout(
        sessionId,
        expectedRevision: editor.getSession(sessionId)!.revision,
        finishedAtUtc: started.add(const Duration(minutes: 30)),
      );
    } else if (pause) {
      engine.pauseWorkout(
        sessionId,
        expectedRevision: editor.getSession(sessionId)!.revision,
      );
    }
  }

  Future<void> showProgress(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          workoutHistoryRepositoryProvider.overrideWithValue(
            _ImmediateHistoryRepository(store),
          ),
        ],
        child: MaterialApp.router(
          theme: NorthstarTheme.build(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> showProgressAt(WidgetTester tester, DateTime nowUtc) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          workoutHistoryRepositoryProvider.overrideWithValue(
            _ImmediateHistoryRepository(store),
          ),
          progressNowProvider.overrideWithValue(nowUtc),
        ],
        child: MaterialApp.router(
          theme: NorthstarTheme.build(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('overview, consistency, body map and summary show real history', (
    tester,
  ) async {
    tallView(tester);
    // Thursday 22 Oct 2026 10:00 UTC; the clock says Saturday 24 Oct.
    writeWorkout('wk', startedAtUtc: DateTime.utc(2026, 10, 22, 10));
    await showProgressAt(tester, DateTime.utc(2026, 10, 24, 12));

    expect(find.text('Volume'), findsWidgets);
    expect(find.text('Workout time'), findsOneWidget);
    expect(find.text('30m'), findsWidgets); // this week's workout time
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.bySemanticsLabel('22 October, trained'), findsOneWidget);
    expect(find.bySemanticsLabel('24 October, today'), findsOneWidget);
    expect(find.text('Total sessions'), findsOneWidget);
    expect(find.text('Week streak'), findsOneWidget);
    expect(find.text('Muscle Recovery'), findsOneWidget);
    expect(find.text('Sample data'), findsOneWidget);
    expect(find.text('Training summary'), findsOneWidget);
    expect(find.text('Workout wk'), findsOneWidget);
    expect(find.text('00:30:00'), findsOneWidget);
    expect(find.text('View details'), findsOneWidget);
  });

  testWidgets('View details opens the session with its exercises', (
    tester,
  ) async {
    tallView(tester);
    writeWorkout('wk', startedAtUtc: DateTime.utc(2026, 10, 22, 10));
    await showProgressAt(tester, DateTime.utc(2026, 10, 24, 12));
    await tester.ensureVisible(find.text('View details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View details'));
    await tester.pumpAndSettle();
    expect(find.text('Workout details'), findsOneWidget);
    expect(find.text('started at 15:30'), findsOneWidget); // 10:00Z at +05:30
    expect(find.text('30m'), findsOneWidget);
    expect(find.text('1 exercise'), findsOneWidget);
    expect(find.text('Bench press'), findsOneWidget);
    expect(find.textContaining('8 reps'), findsOneWidget);
  });

  testWidgets('unsynced and local-only workouts are tagged', (tester) async {
    tallView(tester);
    writeWorkout('wk', startedAtUtc: DateTime.utc(2026, 10, 22, 10));
    writeWorkout('old', startedAtUtc: DateTime.utc(2026, 10, 21, 10));
    writeWorkout('ok', startedAtUtc: DateTime.utc(2026, 10, 20, 10));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          workoutHistoryRepositoryProvider.overrideWithValue(
            _ImmediateHistoryRepository(store),
          ),
          progressNowProvider.overrideWithValue(DateTime.utc(2026, 10, 24, 12)),
          workoutSyncFlagsProvider.overrideWithValue({
            'wk': WorkoutSyncFlag.notSynced,
            'old': WorkoutSyncFlag.localOnly,
            'ok': WorkoutSyncFlag.needsReview,
          }),
        ],
        child: MaterialApp.router(
          theme: NorthstarTheme.build(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Not synced'), findsOneWidget);
    expect(find.text('Local only'), findsOneWidget);
    expect(find.text('Needs review'), findsOneWidget);
    await tester.ensureVisible(find.text('View details').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View details').first);
    await tester.pumpAndSettle();
    expect(find.text('Workout details'), findsOneWidget);
    expect(find.text('Not synced'), findsOneWidget);
  });

  testWidgets('the month arrows browse history and stop at this month', (
    tester,
  ) async {
    tallView(tester);
    writeWorkout('old', startedAtUtc: DateTime.utc(2026, 9, 10, 10));
    await showProgressAt(tester, DateTime.utc(2026, 10, 24, 12));
    IconButton next() => tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right).first,
    );
    expect(next().onPressed, isNull);
    expect(find.bySemanticsLabel('10 September, trained'), findsNothing);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('September 2026'), findsOneWidget);
    expect(find.bySemanticsLabel('10 September, trained'), findsOneWidget);
    expect(next().onPressed, isNotNull);

    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
  });

  testWidgets('empty history is honest and contains no fictional best set', (
    tester,
  ) async {
    tallView(tester);
    await showProgress(tester);
    expect(find.text('Nothing logged yet'), findsOneWidget);
    expect(find.textContaining('Squat · demo'), findsNothing);
    expect(find.text('Workout history'), findsNothing);
  });

  testWidgets('one completed session supplies real progress and detail', (
    tester,
  ) async {
    tallView(tester);
    writeWorkout('first');
    await showProgress(tester);
    expect(find.text('500'), findsOneWidget); // 8 × 62.5 kg
    await tester.scrollUntilVisible(
      find.textContaining('Best logged load'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Best logged load · 62.5 kg'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Workout first'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workout first'));
    await tester.pumpAndSettle();
    expect(find.text('Workout details'), findsOneWidget);
    expect(find.text('Bench press'), findsOneWidget);
    expect(find.textContaining('8 reps'), findsOneWidget);
  });

  testWidgets('paused workout is excluded even when a set was completed', (
    tester,
  ) async {
    tallView(tester);
    writeWorkout('unfinished', finish: false, pause: true);
    expect(
      ObjectBoxWorkoutRepository(store).getSession('unfinished')!.status,
      WorkoutStatus.paused,
    );
    await showProgress(tester);
    expect(find.text('Nothing logged yet'), findsOneWidget);
    expect(find.text('Workout unfinished'), findsNothing);
  });

  testWidgets('history handles tablet width and dark theme', (tester) async {
    tallView(tester);
    tallView(tester, width: 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    writeWorkout('wide');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          workoutHistoryRepositoryProvider.overrideWithValue(
            _ImmediateHistoryRepository(store),
          ),
        ],
        child: MaterialApp.router(
          theme: NorthstarTheme.build(Brightness.dark),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1'), findsWidgets);
    expect(find.byType(ChoiceChip), findsAtLeastNWidgets(3));
    expect(find.textContaining('Best logged load · 62.5 kg'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Workout wide'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Workout wide'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'completed unloaded session shows missing volume instead of zero',
    (tester) async {
      tallView(tester);
      writeWorkout('unloaded', loadGrams: null);
      await showProgress(tester);
      expect(find.text('No loaded sets'), findsOneWidget);
      // Missing volume shows as a dash wherever it appears, never as zero.
      expect(find.text('—'), findsWidgets);
      expect(find.text('No loaded working sets yet'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.textContaining('0 kg'), findsNothing);
    },
  );

  testWidgets('completed zero-load session has no best-weight claim', (
    tester,
  ) async {
    tallView(tester);
    writeWorkout('zero', loadGrams: 0);
    await showProgress(tester);
    expect(find.text('No loaded sets'), findsOneWidget);
    expect(find.textContaining('recorded with 0 kg'), findsOneWidget);
    expect(find.text('Best logged load · 0 kg'), findsNothing);
  });

  testWidgets('date and reps are visible on trend, with an lb toggle', (
    tester,
  ) async {
    tallView(tester, width: 1024);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    writeWorkout('trend');
    await showProgress(tester);
    await tester.scrollUntilVisible(
      find.textContaining('Best logged load'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('8 reps'), findsOneWidget);
    final session = ObjectBoxWorkoutRepository(store).getSession('trend')!;
    final local = session.completedAtUtc!.add(const Duration(minutes: 330));
    expect(
      find.text(
        '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'lb'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Best logged load · 137.79 lb'), findsOneWidget);
    expect(find.textContaining('lb'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('LOADED VOLUME'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('lb × reps'), findsOneWidget);
    expect(find.text('1102.31'), findsOneWidget);
    expect(find.text('kg × reps'), findsNothing);
  });

  testWidgets('period filter honors injected UTC clock and boundary', (
    tester,
  ) async {
    tallView(tester);
    final anchor = DateTime.utc(2026, 10, 24, 12);
    writeWorkout(
      'recent',
      startedAtUtc: anchor.subtract(const Duration(days: 10)),
    );
    writeWorkout(
      'older',
      startedAtUtc: anchor.subtract(const Duration(days: 65)),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          progressNowProvider.overrideWithValue(anchor),
          workoutHistoryRepositoryProvider.overrideWithValue(
            _ImmediateHistoryRepository(store),
          ),
        ],
        child: MaterialApp.router(
          theme: NorthstarTheme.build(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Workout recent'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Workout older'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('90 days'),
      -240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('90 days'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Workout older'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Workout older'), findsOneWidget);
  });

  testWidgets(
    'later Progress visit samples a fresh clock without re-reading history',
    (tester) async {
      tallView(tester);
      var clock = DateTime.utc(2026, 10, 24, 12);
      var sampled = 0;
      final repository = _CountingLoadedHistoryRepository(store);
      writeWorkout(
        'aging',
        startedAtUtc: clock.subtract(const Duration(days: 29)),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            objectBoxStoreProvider.overrideWithValue(store),
            workoutHistoryRepositoryProvider.overrideWithValue(repository),
            progressNowProvider.overrideWith((ref) {
              sampled++;
              return clock;
            }),
          ],
          child: MaterialApp.router(
            theme: NorthstarTheme.build(Brightness.light),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Workout aging'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Workout aging'), findsOneWidget);
      expect(sampled, 1);
      expect(repository.calls, 1);
      router.go('/train');
      await tester.pumpAndSettle();
      clock = clock.add(const Duration(days: 3));
      router.go('/progress');
      await tester.pumpAndSettle();
      expect(find.text('No sessions in this period'), findsOneWidget);
      expect(sampled, 2);
      // History remains cached while the autoDisposed clock is resampled.
      expect(repository.calls, 1);
    },
  );

  testWidgets('returning from background updates 30-day boundary in place', (
    tester,
  ) async {
    tallView(tester);
    var clock = DateTime.utc(2026, 10, 24, 12);
    var sampled = 0;
    final repository = _CountingLoadedHistoryRepository(store);
    writeWorkout(
      'background',
      startedAtUtc: clock.subtract(const Duration(days: 29)),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          workoutHistoryRepositoryProvider.overrideWithValue(repository),
          progressNowProvider.overrideWith((ref) {
            sampled++;
            return clock;
          }),
        ],
        child: MaterialApp.router(
          theme: NorthstarTheme.build(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No sessions in this period'), findsNothing);
    expect(sampled, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    clock = clock.add(const Duration(days: 3));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('No sessions in this period'), findsOneWidget);
    expect(sampled, 2);
    expect(repository.calls, 1);
  });

  testWidgets('finish through ActiveWorkoutPage refreshes cached Progress', (
    tester,
  ) async {
    tallView(tester);
    writeWorkout('finishing', finish: false);
    await showProgress(tester);
    expect(find.text('Nothing logged yet'), findsOneWidget);
    router.go('/train/workout');
    await tester.pumpAndSettle();
    expect(find.text('Workout in progress'), findsOneWidget);
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish workout'));
    await tester.pumpAndSettle();
    router.go('/progress');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Workout finishing'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Workout finishing'), findsOneWidget);
  });

  testWidgets(
    'finishing an invalid-backup workout refreshes the Today blocked notice',
    (tester) async {
      tallView(tester);
      writeWorkout('finishing', finish: false);
      final exerciseBox = store.box<WorkoutExerciseEntity>();
      final exercise = exerciseBox.getAll().single;
      // This exceeds the server's 160-codepoint exercise-name limit but
      // must not prevent an otherwise valid offline workout from finishing.
      exercise.nameSnapshot = '🏋️' * 161;
      exerciseBox.put(exercise);

      final api = FakeAuthApi()..sessionId = accountA;
      final binding = FakeBoundAccountStore()..saved = accountA;
      final auth = controller(api, binding);
      addTearDown(auth.dispose);
      await auth.restore();

      final container = ProviderContainer(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          workoutHistoryRepositoryProvider.overrideWithValue(
            _ImmediateHistoryRepository(store),
          ),
          accountAuthControllerProvider.overrideWithValue(auth),
          blockedWorkoutCountProvider.overrideWith(
            (ref) => ref.watch(workoutOutboxProvider).blockedCount(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: NorthstarTheme.build(Brightness.light),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Prime the count while no receipt exists. This specifically guards
      // against the old never-invalidated cached provider behavior.
      expect(container.read(blockedWorkoutCountProvider), 0);
      router.go('/train/workout');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish workout'));
      await tester.pumpAndSettle();
      expect(container.read(blockedWorkoutCountProvider), 1);
      expect(
        store.box<WorkoutSyncOutboxEntity>().getAll().single.state,
        'blocked',
      );

      router.go('/today');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('1 completed workout saved locally'),
        findsOneWidget,
      );
      expect(
        find.textContaining('No upload will be attempted'),
        findsOneWidget,
      );
    },
  );

  testWidgets('history is cached across navigation and refresh is explicit', (
    tester,
  ) async {
    tallView(tester);
    final fake = _CountingHistoryRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          workoutHistoryRepositoryProvider.overrideWithValue(fake),
        ],
        child: MaterialApp.router(
          theme: NorthstarTheme.build(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fake.calls, 1);
    expect(find.text('Nothing logged yet'), findsOneWidget);
    router.go('/train');
    await tester.pumpAndSettle();
    router.go('/progress');
    await tester.pumpAndSettle();
    expect(fake.calls, 1);
    await tester.tap(find.byTooltip('Refresh completed workouts'));
    await tester.pumpAndSettle();
    expect(fake.calls, 2);
  });

  testWidgets('initial loading, error and retry recover without false data', (
    tester,
  ) async {
    tallView(tester);
    final fake = _FlakyHistoryRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          workoutHistoryRepositoryProvider.overrideWithValue(fake),
        ],
        child: MaterialApp.router(
          theme: NorthstarTheme.build(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    // A pending first read must show a loading indicator, not an empty
    // history or invented numbers.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Nothing logged yet'), findsNothing);
    fake.initialRead.completeError(StateError('synthetic read failure'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not load completed workouts'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing logged yet'), findsOneWidget);
    expect(fake.calls, 2);
  });
}

/// Widget tests use immediate native read of the same ObjectBox Store;
/// worker-isolate behavior is independently tested by the native suite.
class _ImmediateHistoryRepository implements WorkoutHistoryRepository {
  _ImmediateHistoryRepository(Store store)
    : _native = ObjectBoxWorkoutHistoryRepository(store);
  final ObjectBoxWorkoutHistoryRepository _native;
  @override
  WorkoutHistorySnapshot readCompleted() => _native.readCompleted();
  @override
  Future<WorkoutHistorySnapshot> readCompletedAsync() async => readCompleted();
}

class _FlakyHistoryRepository implements WorkoutHistoryRepository {
  final initialRead = Completer<WorkoutHistorySnapshot>();
  int calls = 0;
  @override
  WorkoutHistorySnapshot readCompleted() =>
      const WorkoutHistorySnapshot(sessions: []);
  @override
  Future<WorkoutHistorySnapshot> readCompletedAsync() {
    calls++;
    if (calls == 1) return initialRead.future;
    return Future.value(readCompleted());
  }
}

class _CountingHistoryRepository implements WorkoutHistoryRepository {
  int calls = 0;
  @override
  WorkoutHistorySnapshot readCompleted() =>
      const WorkoutHistorySnapshot(sessions: []);
  @override
  Future<WorkoutHistorySnapshot> readCompletedAsync() async {
    calls++;
    return readCompleted();
  }
}

class _CountingLoadedHistoryRepository implements WorkoutHistoryRepository {
  _CountingLoadedHistoryRepository(Store store)
    : _native = ObjectBoxWorkoutHistoryRepository(store);
  final ObjectBoxWorkoutHistoryRepository _native;
  int calls = 0;

  @override
  WorkoutHistorySnapshot readCompleted() => _native.readCompleted();
  @override
  Future<WorkoutHistorySnapshot> readCompletedAsync() async {
    calls++;
    return readCompleted();
  }
}
