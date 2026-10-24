import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:northstar_health/core/design/northstar_theme.dart';
import 'package:northstar_health/core/storage/objectbox_store_provider.dart';
import 'package:northstar_health/features/progress/progress_page.dart';
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

  void writeWorkout(String id, {bool finish = true}) {
    final started = DateTime.now().toUtc().subtract(const Duration(hours: 2));
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
        reps: 8,
        loadGrams: 62500,
        completedAtUtc: started.add(const Duration(minutes: 5)),
      ),
    );
    if (finish) {
      engine.finishWorkout(
        id,
        expectedRevision: editor.getSession(id)!.revision,
        finishedAtUtc: started.add(const Duration(minutes: 30)),
      );
    }
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
    await tester.pumpAndSettle();
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
    writeWorkout('unfinished', finish: false);
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
    await tester.pumpAndSettle();
    expect(find.text('Workout wide'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
