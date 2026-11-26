import 'dart:io';

import 'package:beyondrep/app/beyondrep_app.dart';
import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/storage/objectbox_store_provider.dart';
import 'package:beyondrep/features/catalog/application/catalog_providers.dart';
import 'package:beyondrep/features/catalog/data/catalog_repository.dart';
import 'package:beyondrep/features/catalog/domain/catalog_programs.dart';
import 'package:beyondrep/features/catalog/domain/catalog_templates.dart';
import 'package:beyondrep/features/programs/data/objectbox_program_repository.dart';
import 'package:beyondrep/features/train/active_workout_state.dart';
import 'package:beyondrep/features/train/exercise_catalog_page.dart';
import 'package:beyondrep/features/train/exercise_detail_page.dart';
import 'package:beyondrep/features/train/my_program_page.dart';
import 'package:beyondrep/features/train/program_detail_page.dart';
import 'package:beyondrep/features/train/programs_page.dart';
import 'package:beyondrep/features/train/template_detail_page.dart';
import 'package:beyondrep/features/train/train_page.dart';
import 'package:beyondrep/features/train/workout_templates_page.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../catalog/catalog_fixtures.dart';
import '../support/fake_health_overview.dart';
import 'program_test_support.dart';

/// The screen sizes the training library is checked at.
const librarySizes = <String, Size>{
  'phone 360x740': Size(360, 740),
  'tablet portrait 820x1180': Size(820, 1180),
  'tablet landscape 1180x820': Size(1180, 820),
  'split view 507x1024': Size(507, 1024),
};

/// Imports a synthetic program straight into [store]; returns its uuid.
String seedLibraryProgram(
  Store store,
  String id, {
  int firstDay = 3,
  bool active = true,
  DateTime? activatedOn,
}) {
  final snapshot = programsSnapshot();
  final program = browsablePrograms(snapshot).firstWhere((p) => p.id == id);
  final templates = {
    for (final t in program.week.whereType<String>())
      t: programTemplate(snapshot, t)!,
  };
  return ObjectBoxProgramRepository(store)
      .importProgram(
        requestUuid: 'seed-${store.box<TrainingProgramEntity>().count()}',
        program: program,
        templateRows: {
          for (final e in templates.entries)
            e.key: templateRowInputs(e.value, snapshot),
        },
        templateNames: {for (final e in templates.entries) e.key: e.value.name},
        release: 4,
        firstDayWeekday: firstDay,
        makeActive: active,
        localToday: activatedOn ?? DateTime(2026, 11, 25),
      )
      .uuid;
}

/// Pumps any store-backed library screen at [location] inside the app's
/// adaptive shell (tab bar on a phone, rail on a tablet).
Future<void> pumpLibraryScreen(
  WidgetTester tester, {
  required Store store,
  required Directory directory,
  required String location,
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
  double textScale = 1,
  DateTime? now,
  CatalogState? state,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      ShellRoute(
        builder: (_, s, child) =>
            AdaptiveShell(location: s.uri.path, child: child),
        routes: [
          GoRoute(path: '/train', builder: (_, _) => const TrainPage()),
          GoRoute(
            path: '/train/workouts',
            builder: (_, _) => const WorkoutTemplatesPage(),
          ),
          GoRoute(
            path: '/train/workouts/:id',
            builder: (_, s) =>
                TemplateDetailPage(templateId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/train/programs',
            builder: (_, _) => const ProgramsPage(),
          ),
          GoRoute(
            path: '/train/programs/:id',
            builder: (_, s) =>
                ProgramDetailPage(programId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/train/program/:uuid',
            builder: (_, s) =>
                MyProgramPage(programUuid: s.pathParameters['uuid']!),
          ),
          GoRoute(
            path: '/train/exercises',
            builder: (_, _) => const ExerciseCatalogPage(),
          ),
          GoRoute(
            path: '/train/exercises/:id',
            builder: (_, s) =>
                ExerciseDetailPage(exerciseId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/train/workout',
            builder: (_, _) => const Text('LOGGER'),
          ),
          GoRoute(
            path: '/train/plans/:id/edit',
            builder: (_, _) => const Text('EDITOR'),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  final clock = now ?? DateTime(2026, 11, 25, 10);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        objectBoxStoreProvider.overrideWithValue(store),
        fakeHealthOverview(FakeHealthOverviewController(null)),
        localNowProvider.overrideWithValue(clock),
        workoutClockProvider.overrideWithValue(() => clock),
        catalogRepositoryProvider.overrideWithValue(
          StubCatalogRepository(state ?? readyPrograms(), directory),
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
