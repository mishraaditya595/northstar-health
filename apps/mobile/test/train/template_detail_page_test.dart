import 'dart:io';

import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/storage/objectbox_store_provider.dart';
import 'package:beyondrep/features/catalog/application/catalog_providers.dart';
import 'package:beyondrep/features/catalog/data/catalog_repository.dart';
import 'package:beyondrep/features/train/template_detail_page.dart';
import 'package:beyondrep/features/workouts/data/objectbox_live_workout_engine.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../catalog/catalog_fixtures.dart';
import '../support/fake_health_overview.dart';
import 'template_test_support.dart';

void main() {
  late Directory directory;
  late Store store;
  late GoRouter currentRouter;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-tpl-detail-');
    store = Store(getObjectBoxModel(), directory: directory.path);
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  int plans() => store.box<WorkoutPlanEntity>().count();

  Future<List<String>> open(
    WidgetTester tester, {
    String id = 'tpl.push',
    CatalogState? state,
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final visited = <String>[];
    final router = GoRouter(
      initialLocation: '/detail',
      routes: [
        GoRoute(
          path: '/detail',
          builder: (_, _) => TemplateDetailPage(templateId: id),
        ),
        GoRoute(
          path: '/away',
          builder: (_, _) => const Scaffold(body: Text('AWAY')),
        ),
        GoRoute(
          path: '/train/workout',
          builder: (_, _) {
            visited.add('logger');
            return const Text('LOGGER');
          },
        ),
        GoRoute(
          path: '/train/plans/:id/edit',
          builder: (_, s) {
            visited.add('edit ${s.pathParameters['id']}');
            return const Text('EDITOR');
          },
        ),
        GoRoute(
          path: '/train/exercises/:id',
          builder: (_, s) {
            visited.add('exercise ${s.pathParameters['id']}');
            return const Text('EXERCISE');
          },
        ),
      ],
    );
    currentRouter = router;
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          fakeHealthOverview(FakeHealthOverviewController(null)),
          catalogRepositoryProvider.overrideWithValue(
            StubCatalogRepository(state ?? readyTemplates(), directory),
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
    return visited;
  }

  final copyButton = find.text('Copy to My Plans');
  final startButton = find.text('Start now');

  testWidgets('shows every exercise with its prescription, rest and note', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Synthetic push'), findsOneWidget);
    expect(find.text('Synthetic move 1'), findsOneWidget);
    expect(find.textContaining('4 × 6–8 reps'), findsOneWidget);
    expect(find.textContaining('Rest 2 min 30 s'), findsOneWidget);
    expect(find.textContaining('Pause at the bottom'), findsOneWidget);
    expect(find.text('Synthetic hold'), findsOneWidget);
    expect(find.textContaining('3 × 45 s'), findsOneWidget);
    expect(find.textContaining('Rest 60 s'), findsOneWidget);
  });

  testWidgets('tapping an exercise opens its detail', (tester) async {
    final visited = await open(tester);
    await tester.tap(find.text('Synthetic move 1'));
    await tester.pumpAndSettle();
    expect(visited, ['exercise builtin.v1.synthetic-move-1']);
  });

  testWidgets('an unknown or hidden template is not available', (tester) async {
    await open(tester, id: 'tpl.hidden');
    expect(find.text("This workout isn't available."), findsOneWidget);
    expect(copyButton, findsNothing);
  });

  testWidgets('a retired template says it is no longer available', (
    tester,
  ) async {
    await open(tester, id: 'tpl.old');
    expect(find.text('This workout is no longer available.'), findsOneWidget);
    expect(find.text("This workout isn't available."), findsNothing);
    expect(copyButton, findsNothing);
  });

  testWidgets('copying twice quickly makes one plan; a later copy numbers it', (
    tester,
  ) async {
    final visited = await open(tester);
    await tester.tap(copyButton);
    await tester.tap(copyButton, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(plans(), 1);
    expect(find.text('Saved to My Plans as Synthetic push'), findsOneWidget);
    final plan = store.box<WorkoutPlanEntity>().getAll().single;
    expect(plan.name, 'Synthetic push');
    expect(store.box<PlanExerciseEntity>().count(), 2);

    ScaffoldMessenger.of(tester.element(find.byType(TemplateDetailPage)))
        .clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(copyButton);
    await tester.pumpAndSettle();
    expect(plans(), 2);
    expect(
      find.text('Saved to My Plans as Synthetic push (2)'),
      findsOneWidget,
    );

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    final second = store.box<WorkoutPlanEntity>().getAll().last;
    expect(visited, ['edit ${second.uuid}']);
  });

  testWidgets('leaving the page takes its Saved snackbar away', (tester) async {
    final visited = await open(tester);
    await tester.tap(copyButton);
    await tester.pumpAndSettle();
    expect(find.text('Saved to My Plans as Synthetic push'), findsOneWidget);
    currentRouter.go('/away');
    await tester.pumpAndSettle();
    expect(find.text('AWAY'), findsOneWidget);
    expect(find.text('Saved to My Plans as Synthetic push'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(visited, isEmpty);
  });

  testWidgets('Start now opens the logger with a timed exercise in seconds', (
    tester,
  ) async {
    final visited = await open(tester);
    await tester.tap(startButton);
    await tester.pumpAndSettle();
    expect(visited, ['logger']);
    final session = store.box<WorkoutSessionEntity>().getAll().single;
    expect(session.name, 'Synthetic push');
    expect(session.planUuid, isNull);
    expect(plans(), 0);
    final workout = ObjectBoxLiveWorkoutEngine(store).recoverActiveWorkout()!;
    expect(workout.exercises.map((e) => e.nameSnapshot), [
      'Synthetic move 1',
      'Synthetic hold',
    ]);
    expect(workout.sets, hasLength(7));
  });

  testWidgets('Start now while a workout runs shows the message only', (
    tester,
  ) async {
    ObjectBoxLiveWorkoutEngine(store).startWorkout(
      sessionUuid: 'running',
      quickName: 'Running',
      startedAtUtc: DateTime.now().toUtc(),
      originalOffsetMinutes: 0,
    );
    final visited = await open(tester);
    final definitions = store.box<ExerciseDefinitionEntity>().count();
    await tester.tap(startButton);
    await tester.pumpAndSettle();
    expect(visited, isEmpty);
    expect(
      find.text(
        'Could not start this workout. Check the plan and any unfinished '
        'workout.',
      ),
      findsOneWidget,
    );
    expect(store.box<WorkoutSessionEntity>().count(), 1);
    expect(store.box<ExerciseDefinitionEntity>().count(), definitions);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'text scale 2.0 with seven exercises: no overflow, buttons reachable '
      '(${brightness.name})',
      (tester) async {
        await open(tester, id: 'tpl.big', brightness: brightness, textScale: 2);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Synthetic hold'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.scrollUntilVisible(
          copyButton,
          -300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.scrollUntilVisible(
          startButton,
          -300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
        expect(startButton.hitTestable(), findsOneWidget);
        expect(copyButton.hitTestable(), findsOneWidget);
      },
    );
  }
}
