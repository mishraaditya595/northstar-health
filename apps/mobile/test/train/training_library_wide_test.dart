import 'dart:io';

import 'package:beyondrep/app/beyondrep_app.dart';
import 'package:beyondrep/core/design/page_header.dart';
import 'package:beyondrep/features/catalog/application/catalog_providers.dart';
import 'package:beyondrep/features/catalog/data/catalog_repository.dart';
import 'package:beyondrep/features/catalog/domain/catalog_models.dart';
import 'package:beyondrep/features/train/exercise_catalog_page.dart';
import 'package:beyondrep/features/train/exercise_detail_page.dart';
import 'package:beyondrep/features/train/my_program_page.dart';
import 'package:beyondrep/features/train/programs_page.dart';
import 'package:beyondrep/features/train/workout_templates_page.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../catalog/catalog_fixtures.dart';
import 'program_test_support.dart';
import 'training_library_harness.dart';

const _wide = Size(1194, 834);
const _phone = Size(390, 844);

void main() {
  late Directory directory;
  late Store store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-lib-wide-');
    store = Store(getObjectBoxModel(), directory: directory.path);
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  Future<void> open(WidgetTester tester, String location, Size size) =>
      pumpLibraryScreen(
        tester,
        store: store,
        directory: directory,
        location: location,
        size: size,
      );

  Future<void> tapRow(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(
      find.text(text),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    if (tester.view.physicalSize.width < 840) {
      await tester.tap(find.text(text));
    } else {
      // The wide list's floating button can cover the middle of a bottom row:
      // tap the card's right edge.
      final card = find
          .ancestor(of: find.text(text), matching: find.byType(NsListCard))
          .first;
      await tester.tapAt(
        tester.getRect(card).centerRight + const Offset(-8, 0),
      );
    }
    await tester.pumpAndSettle();
  }

  GoRouter router(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(AdaptiveShell)));

  String path(WidgetTester tester) => router(tester).state.uri.path;

  testWidgets('wide exercise catalogue opens detail beside the list', (
    tester,
  ) async {
    await open(tester, '/train/exercises', _wide);
    expect(find.text("Pick an exercise to see how it's done."), findsOneWidget);
    await tapRow(tester, 'Synthetic move 1');
    expect(find.text('Exercise'), findsOneWidget);
    expect(find.byType(ExerciseCatalogPage), findsOneWidget);
    expect(path(tester), '/train/exercises');
    expect(find.text("Pick an exercise to see how it's done."), findsNothing);
  });

  testWidgets(
    'wide workouts list opens a template beside the list and Copy to My Plans '
    'works there',
    (tester) async {
      await open(tester, '/train/workouts', _wide);
      expect(
        find.text('Pick a workout to see every exercise.'),
        findsOneWidget,
      );
      await tapRow(tester, 'Synthetic push');
      expect(path(tester), '/train/workouts');
      final before = store.box<WorkoutPlanEntity>().count();
      await tester.tap(find.text('Copy to My Plans'));
      await tester.pumpAndSettle();
      expect(store.box<WorkoutPlanEntity>().count(), before + 1);
      expect(find.textContaining('Saved to My Plans'), findsOneWidget);
      expect(find.byType(WorkoutTemplatesPage), findsOneWidget);
    },
  );

  testWidgets('wide Add program from the pane keeps the programs list '
      'underneath', (tester) async {
    await open(tester, '/train/programs', _wide);
    expect(find.text('Pick a program to see its weeks.'), findsOneWidget);
    await tapRow(tester, 'Synthetic three-day');
    expect(path(tester), '/train/programs');
    await tester.tap(find.text('Add program'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add program').last);
    await tester.pumpAndSettle();
    expect(find.byType(MyProgramPage), findsOneWidget);
    router(tester).pop();
    await tester.pumpAndSettle();
    expect(find.byType(MyProgramPage), findsNothing);
    expect(find.byType(ProgramsPage), findsOneWidget);
    expect(path(tester), '/train/programs');
  });

  StubCatalogRepository stub(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(AdaptiveShell)))
              .read(catalogRepositoryProvider)
          as StubCatalogRepository;

  CatalogSnapshot withoutTemplatesAndPrograms() {
    final base = programsSnapshot();
    return CatalogSnapshot(
      release: base.release,
      schemaVersion: base.schemaVersion,
      minAppCatalogSchema: base.minAppCatalogSchema,
      publishedAt: base.publishedAt,
      sha256: base.sha256,
      exercises: base.exercises,
      templates: [
        for (final t in base.templates)
          if (t.id != 'tpl.push') t,
      ],
      programs: [
        for (final p in base.programs)
          if (p.id != 'prog.three') p,
      ],
    );
  }

  testWidgets('wide Start now then narrowing keeps the logger on top', (
    tester,
  ) async {
    await open(tester, '/train/workouts', _wide);
    await tapRow(tester, 'Synthetic push');
    await tester.tap(find.text('Start now'));
    await tester.pumpAndSettle();
    expect(path(tester), '/train/workout');
    tester.view.physicalSize = const Size(507, 1024);
    await tester.pumpAndSettle();
    expect(path(tester), '/train/workout');
    router(tester).pop();
    await tester.pumpAndSettle();
    expect(path(tester), '/train/workouts');
  });

  testWidgets('wide workouts and programs panes handle the catalogue changing '
      'under an open item', (tester) async {
    for (final (location, row, empty, detail) in [
      (
        '/train/workouts',
        'Synthetic push',
        'Pick a workout to see every exercise.',
        'Start now',
      ),
      (
        '/train/programs',
        'Synthetic three-day',
        'Pick a program to see its weeks.',
        'Add program',
      ),
    ]) {
      await open(tester, location, _wide);
      await tapRow(tester, row);
      expect(find.text(empty), findsNothing);
      // Still loading: the selection is kept.
      stub(tester).emit(const CatalogState(status: CatalogStatus.loading));
      await tester.pumpAndSettle();
      stub(tester).emit(readyPrograms());
      await tester.pumpAndSettle();
      expect(find.text(empty), findsNothing, reason: location);
      expect(find.text(detail), findsWidgets, reason: location);
      // Loaded without the item: back to the empty message.
      stub(tester).emit(
        CatalogState(
          snapshot: withoutTemplatesAndPrograms(),
          status: CatalogStatus.ready,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(empty), findsOneWidget, reason: location);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('wide Custom exercise button stays off the detail pane', (
    tester,
  ) async {
    await open(tester, '/train/exercises', _wide);
    await tapRow(tester, 'Synthetic move 1');
    final fab = tester.getRect(find.byType(FloatingActionButton));
    final pane = tester.getRect(find.byType(ExerciseDetailPage));
    expect(fab.overlaps(pane), isFalse);
  });

  testWidgets('narrow library taps still push', (tester) async {
    for (final (location, row, expected) in [
      (
        '/train/exercises',
        'Synthetic move 1',
        '/train/exercises/builtin.v1.synthetic-move-1',
      ),
      ('/train/workouts', 'Synthetic push', '/train/workouts/tpl.push'),
      ('/train/programs', 'Synthetic three-day', '/train/programs/prog.three'),
    ]) {
      await open(tester, location, _phone);
      await tapRow(tester, row);
      expect(path(tester), expected);
    }
  });
}
