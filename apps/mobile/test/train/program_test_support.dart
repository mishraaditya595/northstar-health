import 'dart:io';

import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/storage/objectbox_store_provider.dart';
import 'package:beyondrep/features/catalog/application/catalog_providers.dart';
import 'package:beyondrep/features/catalog/data/catalog_repository.dart';
import 'package:beyondrep/features/catalog/domain/catalog_models.dart';
import 'package:beyondrep/features/programs/data/objectbox_program_repository.dart';
import 'package:beyondrep/features/programs/domain/program_repository.dart';
import 'package:beyondrep/features/train/active_workout_state.dart';
import 'package:beyondrep/features/train/my_program_page.dart';
import 'package:beyondrep/features/train/program_detail_page.dart';
import 'package:beyondrep/features/train/programs_page.dart';
import 'package:beyondrep/features/train/train_page.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../catalog/catalog_fixtures.dart';
import '../support/fake_health_overview.dart';
import 'template_test_support.dart';

CatalogProgram _program(
  String id,
  String name,
  String level,
  List<String?> week, {
  List<String> goals = const ['general'],
  List<String> equipment = const ['barbell', 'dumbbell'],
  bool retired = false,
}) => CatalogProgram(
  id: id,
  name: name,
  description: 'Synthetic description for $name.',
  goals: goals,
  level: level,
  daysPerWeek: week.whereType<String>().length,
  estimatedMinutes: 40,
  equipment: equipment,
  retired: retired,
  week: week,
);

/// Templates of [templatesSnapshot] plus synthetic programs. `tpl.hidden` is
/// program-only.
CatalogSnapshot programsSnapshot() {
  final base = templatesSnapshot();
  return CatalogSnapshot(
    release: 4,
    schemaVersion: base.schemaVersion,
    minAppCatalogSchema: 1,
    publishedAt: base.publishedAt,
    sha256: base.sha256,
    exercises: base.exercises,
    templates: base.templates,
    programs: [
      _program('prog.three', 'Synthetic three-day', 'beginner', [
        'tpl.push',
        null,
        'tpl.pull',
        null,
        'tpl.hidden',
        null,
        null,
      ]),
      _program(
        'prog.six',
        'Synthetic six-day',
        'intermediate',
        [
          'tpl.push',
          'tpl.pull',
          'tpl.big',
          'tpl.push',
          'tpl.pull',
          'tpl.hidden',
          null,
        ],
        goals: const ['hypertrophy'],
        equipment: const ['barbell', 'dumbbell', 'cable'],
      ),
      _program('prog.old', 'Synthetic retired program', 'beginner', [
        'tpl.push',
        null,
        'tpl.pull',
        null,
        null,
        null,
        null,
      ], retired: true),
    ],
  );
}

CatalogState readyPrograms() =>
    CatalogState(snapshot: programsSnapshot(), status: CatalogStatus.ready);

/// Pumps the program screens inside a router that records navigation.
Future<List<String>> pumpPrograms(
  WidgetTester tester, {
  required Store store,
  required Directory directory,
  required String initial,
  CatalogState? state,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  DateTime? now,
  DateTime Function()? clock,
  ProgramRepository? programRepository,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final visited = <String>[];
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/train', builder: (_, _) => const TrainPage()),
      GoRoute(path: '/train/programs', builder: (_, _) => const ProgramsPage()),
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
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        objectBoxStoreProvider.overrideWithValue(store),
        if (programRepository != null)
          programRepositoryProvider.overrideWithValue(programRepository),
        fakeHealthOverview(FakeHealthOverviewController(null)),
        localNowProvider.overrideWithValue(now ?? DateTime(2026, 11, 25, 10)),
        workoutClockProvider.overrideWithValue(
          clock ?? () => now ?? DateTime(2026, 11, 25, 10),
        ),
        catalogRepositoryProvider.overrideWithValue(
          StubCatalogRepository(state ?? readyPrograms(), directory),
        ),
        ...overrides,
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

CatalogState unavailableCatalog() =>
    const CatalogState(status: CatalogStatus.unavailable);
