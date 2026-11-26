import 'dart:io';

import 'package:beyondrep/app/beyondrep_app.dart';
import 'package:beyondrep/features/train/exercise_catalog_page.dart';
import 'package:beyondrep/features/train/my_program_page.dart';
import 'package:beyondrep/features/train/programs_page.dart';
import 'package:beyondrep/features/train/workout_templates_page.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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
    await tester.tap(find.text(text));
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
