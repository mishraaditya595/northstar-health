import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:northstar_health/core/design/northstar_theme.dart';
import 'package:northstar_health/core/design/page_header.dart';
import 'package:northstar_health/core/storage/objectbox_store_provider.dart';
import 'package:northstar_health/features/train/active_workout_page.dart';
import 'package:northstar_health/features/train/train_page.dart';
import 'package:northstar_health/features/workouts/data/objectbox_live_workout_engine.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_repository.dart';
import 'package:northstar_health/features/workouts/data/workout_entities.dart';
import 'package:northstar_health/features/workouts/domain/workout_models.dart';
import 'package:northstar_health/objectbox.g.dart';

void main() {
  late Directory directory;
  late Store store;
  late GoRouter router;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('northstar-workout-ui-');
    store = Store(getObjectBoxModel(), directory: directory.path);
    router = GoRouter(
      initialLocation: '/train',
      routes: [
        GoRoute(path: '/train', builder: (_, _) => const TrainPage()),
        GoRoute(
          path: '/train/workout',
          builder: (_, _) => const ActiveWorkoutPage(),
        ),
      ],
    );
  });

  tearDown(() {
    router.dispose();
    store.close();
    directory.deleteSync(recursive: true);
  });

  Future<void> showApp(WidgetTester tester) async {
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

  testWidgets('user removes planned and recorded sets from a workout', (
    tester,
  ) async {
    await showApp(tester);
    await tester.tap(find.text('Quick workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Barbell bench press').last);
    await tester.pumpAndSettle();
    for (var n = 0; n < 2; n++) {
      await tester.ensureVisible(find.text('Add set'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add set'));
      await tester.pumpAndSettle();
    }
    expect(store.box<WorkoutSetEntity>().count(), 2);

    // A planned set holds no recorded data, so it goes without a question.
    await tester.ensureVisible(find.byTooltip('Remove set 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove set 2'));
    await tester.pumpAndSettle();
    expect(find.text('Remove this set?'), findsNothing);
    expect(store.box<WorkoutSetEntity>().count(), 1);

    // A recorded set is deleted only after the user confirms.
    final fields = find.descendant(
      of: find.byType(SetEditorTile),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), '5');
    await tester.ensureVisible(find.text('Save set'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save set'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Remove set 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove set 1'));
    await tester.pumpAndSettle();
    expect(find.text('Remove this set?'), findsOneWidget);
    await tester.tap(find.text('Keep set'));
    await tester.pumpAndSettle();
    expect(store.box<WorkoutSetEntity>().count(), 1);

    await tester.tap(find.byTooltip('Remove set 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove set'));
    await tester.pumpAndSettle();
    expect(store.box<WorkoutSetEntity>().count(), 0);
  });

  testWidgets('quick workout records real sets and finishes locally', (
    tester,
  ) async {
    await showApp(tester);
    await tester.tap(find.text('Quick workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
    expect(find.text('Workout in progress'), findsOneWidget);
    // A pushed route must provide a real back stack; navigating back does
    // not finish or discard the current offline workout.
    expect(router.canPop(), isTrue);
    router.pop();
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(PageHeader),
        matching: find.text('Train'),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Resume: Quick workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resume: Quick workout'));
    await tester.pumpAndSettle();
    expect(find.text('Workout in progress'), findsOneWidget);

    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Barbell bench press').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add set'));
    await tester.pumpAndSettle();

    final fields = find.descendant(
      of: find.byType(SetEditorTile),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), '8');
    await tester.enterText(fields.at(1), '42.5');
    await tester.enterText(fields.at(2), '8.5');
    await tester.ensureVisible(find.byType(DropdownButton<WorkoutSetKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<WorkoutSetKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Warm-up').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save set'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save set'));
    await tester.pumpAndSettle();

    final sessionUuid = store.box<WorkoutSessionEntity>().getAll().single.uuid;
    final repository = ObjectBoxWorkoutRepository(store);
    final recorded = repository.getSession(sessionUuid)!;
    expect(recorded.sets.single.status, WorkoutSetStatus.completed);
    expect(recorded.sets.single.reps, 8);
    expect(recorded.sets.single.kind, WorkoutSetKind.warmup);
    expect(recorded.sets.single.loadGrams, 42500);
    expect(recorded.sets.single.rpe, 8.5);
    expect(
      store.box<WorkoutSessionStateEntity>().getAll().single.restState,
      'running',
    );

    await tester.scrollUntilVisible(
      find.text('Pause'),
      -240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    expect(repository.getSession(sessionUuid)!.status, WorkoutStatus.paused);
    expect(
      store.box<WorkoutSessionStateEntity>().getAll().single.restState,
      'paused',
    );

    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(
      repository.getSession(sessionUuid)!.status,
      WorkoutStatus.inProgress,
    );

    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish workout'));
    await tester.pumpAndSettle();
    expect(repository.getSession(sessionUuid)!.status, WorkoutStatus.completed);
    expect(store.box<WorkoutSessionStateEntity>().count(), 0);
  });

  testWidgets('saving row A retains unsaved reps and load in row B', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final engine = ObjectBoxLiveWorkoutEngine(store);
    final repo = ObjectBoxWorkoutRepository(store);
    final start = engine.startWorkout(
      sessionUuid: 'session-rows',
      quickName: 'Two rows',
      startedAtUtc: DateTime.now().toUtc(),
      originalOffsetMinutes: 330,
    );
    repo.addExercise(
      const WorkoutExerciseRecord(
        uuid: 'exercise-rows',
        sessionUuid: 'session-rows',
        nameSnapshot: 'Squat',
        position: 0,
      ),
    );
    for (final (index, uuid) in [(0, 'set-a'), (1, 'set-b')]) {
      repo.saveSet(
        sessionUuid: start.uuid,
        expectedRevision: repo.getSession(start.uuid)!.revision,
        set: WorkoutSetRecord(
          uuid: uuid,
          exerciseUuid: 'exercise-rows',
          position: index,
          kind: WorkoutSetKind.working,
          status: WorkoutSetStatus.planned,
        ),
      );
    }
    await showApp(tester);
    router.go('/train/workout');
    await tester.pumpAndSettle();

    final draftReps = find.descendant(
      of: find.byKey(const ValueKey('reps-set-b')),
      matching: find.byType(TextField),
    );
    final draftWeight = find.descendant(
      of: find.byKey(const ValueKey('weight-set-b')),
      matching: find.byType(TextField),
    );
    expect(draftReps, findsOneWidget);
    expect(draftWeight, findsOneWidget);
    await tester.enterText(draftReps, '9');
    await tester.enterText(draftWeight, '75.75');
    await tester.enterText(find.byKey(const ValueKey('reps-set-a')), '8');
    await tester.enterText(find.byKey(const ValueKey('weight-set-a')), '55');
    await tester.tap(find.text('Save set').first);
    await tester.pumpAndSettle();

    expect(
      repo
          .getSession(start.uuid)!
          .sets
          .singleWhere((record) => record.uuid == 'set-a')
          .status,
      WorkoutSetStatus.completed,
    );
    expect(
      repo
          .getSession(start.uuid)!
          .sets
          .singleWhere((record) => record.uuid == 'set-b')
          .status,
      WorkoutSetStatus.planned,
    );
    expect(tester.widget<TextField>(draftReps).controller!.text, '9');
    expect(tester.widget<TextField>(draftWeight).controller!.text, '75.75');
  });

  testWidgets(
    'Train offers an unfinished workout after app and Store restart',
    (tester) async {
      await showApp(tester);
      await tester.tap(find.text('Quick workout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start workout'));
      await tester.pumpAndSettle();
      final id = store.box<WorkoutSessionEntity>().getAll().single.uuid;

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      router.dispose();
      store.close();

      store = Store(getObjectBoxModel(), directory: directory.path);
      router = GoRouter(
        initialLocation: '/train',
        routes: [
          GoRoute(path: '/train', builder: (_, _) => const TrainPage()),
          GoRoute(
            path: '/train/workout',
            builder: (_, _) => const ActiveWorkoutPage(),
          ),
        ],
      );
      await showApp(tester);
      expect(find.text('Resume: Quick workout'), findsOneWidget);
      await tester.ensureVisible(find.text('Resume: Quick workout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resume: Quick workout'));
      await tester.pumpAndSettle();
      expect(find.text('Workout in progress'), findsOneWidget);
      expect(
        ObjectBoxWorkoutRepository(store).getSession(id)!.status,
        WorkoutStatus.inProgress,
      );
    },
  );
}
