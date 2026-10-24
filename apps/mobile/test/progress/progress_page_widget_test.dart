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
import 'package:northstar_health/features/progress/workout_history_detail_page.dart';
import 'package:northstar_health/features/workouts/data/objectbox_live_workout_engine.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_repository.dart';
import 'package:northstar_health/features/workouts/domain/workout_models.dart';
import 'package:northstar_health/objectbox.g.dart';

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
          path: '/train', builder: (_, _) => const Scaffold(body: Text('Train')),
        ),
        GoRoute(
          path: '/train/workout', builder: (_, _) => const ActiveWorkoutPage(),
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

  void writeWorkout(String id, {
    bool finish = true,
    bool pause = false,
    int? loadGrams = 62500,
    int? reps = 8,
    DateTime? startedAtUtc,
  }) {
    final started = startedAtUtc ??
        DateTime.now().toUtc().subtract(const Duration(hours: 2));
    final engine = ObjectBoxLiveWorkoutEngine(store);
    final editor = ObjectBoxWorkoutRepository(store);
    engine.startWorkout(
      sessionUuid: id,
      quickName: 'Workout $id',
      startedAtUtc: started,
      originalOffsetMinutes: 330,
    );
    editor.addExercise(
      WorkoutExerciseRecord(
        uuid: 'movement-$id',
        sessionUuid: id,
        definitionUuid: 'builtin.v1.bench-press',
        nameSnapshot: 'Bench press',
        position: 0,
      ),
    );
    final active = editor.getSession(id)!;
    editor.saveSet(
      sessionUuid: id,
      expectedRevision: active.revision,
      set: WorkoutSetRecord(
        uuid: 'set-$id',
        exerciseUuid: 'movement-$id',
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
        id,
        expectedRevision: editor.getSession(id)!.revision,
        finishedAtUtc: started.add(const Duration(minutes: 30)),
      );
    } else if (pause) {
      engine.pauseWorkout(id,
        expectedRevision: editor.getSession(id)!.revision);
    }
  }

  Future<void> settleHistory(WidgetTester tester) async {
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProgressPage)),
    );
    await tester.runAsync(() async {
      try {
        await container.read(completedWorkoutHistoryProvider.future);
      } catch (_) {
        // Error state itself is asserted in the retry test.
      }
    });
    await tester.pumpAndSettle();
  }

  Future<void> showProgress(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [objectBoxStoreProvider.overrideWithValue(store)],
        child: MaterialApp.router(
          theme: NorthstarTheme.build(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await settleHistory(tester);
  }


  testWidgets('empty history is honest and contains no fictional best set', (
    tester,
  ) async {
    await showProgress(tester);
    expect(find.text('Nothing logged yet'), findsOneWidget);
    expect(find.textContaining('Squat · demo'), findsNothing);
    expect(find.text('WORKOUT HISTORY'), findsNothing);
  });

  testWidgets('one completed session supplies real progress and detail', (
    tester,
  ) async {
    writeWorkout('first');
    await showProgress(tester);
    expect(find.text('500'), findsOneWidget); // 8 × 62.5 kg
    await tester.scrollUntilVisible(
      find.textContaining('62.5 kg'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('62.5 kg'), findsOneWidget);
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
    writeWorkout('unfinished', finish: false, pause: true);
    expect(ObjectBoxWorkoutRepository(store).getSession('unfinished')!.status,
      WorkoutStatus.paused);
    await showProgress(tester);
    expect(find.text('Nothing logged yet'), findsOneWidget);
    expect(find.text('Workout unfinished'), findsNothing);
  });

  testWidgets('history handles tablet width and dark theme', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    writeWorkout('wide');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [objectBoxStoreProvider.overrideWithValue(store)],
        child: MaterialApp.router(
          theme: NorthstarTheme.build(Brightness.dark),
          routerConfig: router,
        ),
      ),
    );
    await settleHistory(tester);
    expect(find.text('Workout wide'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.byType(ChoiceChip), findsAtLeastNWidgets(3));
    expect(find.textContaining('62.5 kg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed unloaded session shows missing volume instead of zero',
      (tester) async {
    writeWorkout('unloaded', loadGrams: null);
    await showProgress(tester);
    expect(find.text('No loaded sets'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('No loaded working sets yet'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('completed zero-load session has no best-weight claim',
      (tester) async {
    writeWorkout('zero', loadGrams: 0);
    await showProgress(tester);
    expect(find.text('No loaded sets'), findsOneWidget);
    expect(find.textContaining('recorded with 0 kg'), findsOneWidget);
    expect(find.text('Best logged load · 0 kg'), findsNothing);
  });

  testWidgets('date and reps are visible on trend, with an lb toggle',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    writeWorkout('trend');
    await showProgress(tester);
    await tester.scrollUntilVisible(
      find.textContaining('Best logged load'), 200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('8 reps'), findsOneWidget);
    final at = DateTime.now().toUtc().subtract(
        const Duration(hours: 1, minutes: 55));
    final local = at.add(const Duration(minutes: 330));
    expect(find.text(
      '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}',
    ), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'lb'));
    await tester.pumpAndSettle();
    expect(find.textContaining('lb'), findsWidgets);
  });

  testWidgets('period filter honors injected UTC clock and boundary',
      (tester) async {
    final anchor = DateTime.utc(2026, 10, 24, 12);
    writeWorkout('recent', startedAtUtc: anchor.subtract(
      const Duration(days: 10)));
    writeWorkout('older', startedAtUtc: anchor.subtract(
      const Duration(days: 65)));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        objectBoxStoreProvider.overrideWithValue(store),
        progressNowProvider.overrideWithValue(anchor),
      ],
      child: MaterialApp.router(
        theme: NorthstarTheme.build(Brightness.light),
        routerConfig: router,
      ),
    ));
    await settleHistory(tester);
    await tester.scrollUntilVisible(find.text('Workout recent'), 200,
      scrollable: find.byType(Scrollable).first);
    expect(find.text('Workout older'), findsNothing);
    await tester.scrollUntilVisible(find.text('90 days'), -240,
      scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('90 days'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Workout older'), 200,
      scrollable: find.byType(Scrollable).first);
    expect(find.text('Workout older'), findsOneWidget);
  });

  testWidgets('finish through ActiveWorkoutPage refreshes cached Progress',
      (tester) async {
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
    await settleHistory(tester);
    await tester.scrollUntilVisible(find.text('Workout finishing'), 200,
      scrollable: find.byType(Scrollable).first);
    expect(find.text('Workout finishing'), findsOneWidget);
  });

  testWidgets('history is cached across navigation and refresh is explicit',
      (tester) async {
    final fake = _CountingHistoryRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        objectBoxStoreProvider.overrideWithValue(store),
        workoutHistoryRepositoryProvider.overrideWithValue(fake),
      ],
      child: MaterialApp.router(
        theme: NorthstarTheme.build(Brightness.light),
        routerConfig: router,
      ),
    ));
    await settleHistory(tester);
    expect(fake.calls, 1);
    expect(find.text('Nothing logged yet'), findsOneWidget);
    router.go('/train');
    await tester.pumpAndSettle();
    router.go('/progress');
    await settleHistory(tester);
    expect(fake.calls, 1);
    await tester.tap(find.byTooltip('Refresh completed workouts'));
    await settleHistory(tester);
    expect(fake.calls, 2);
  });

  testWidgets('error and retry show loading and recover without false data',
      (tester) async {
    final fake = _FlakyHistoryRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        objectBoxStoreProvider.overrideWithValue(store),
        workoutHistoryRepositoryProvider.overrideWithValue(fake),
      ],
      child: MaterialApp.router(
        theme: NorthstarTheme.build(Brightness.light),
        routerConfig: router,
      ),
    ));
    await settleHistory(tester);
    expect(find.textContaining('Could not load completed workouts'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing logged yet'), findsOneWidget);
    expect(fake.calls, 2);
  });
}

class _FlakyHistoryRepository implements WorkoutHistoryRepository {
  int calls = 0;
  @override
  WorkoutHistorySnapshot readCompleted() =>
      const WorkoutHistorySnapshot(sessions: []);
  @override
  Future<WorkoutHistorySnapshot> readCompletedAsync() async {
    calls++;
    if (calls == 1) throw StateError('synthetic read failure');
    return readCompleted();
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
