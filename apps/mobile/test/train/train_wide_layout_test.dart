import 'dart:io';

import 'package:beyondrep/features/workouts/data/objectbox_workout_library_repository.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'training_library_harness.dart';

const _wide = Size(1194, 834);
const _planNames = ['Plan A', 'Plan B', 'Plan C'];

void main() {
  late Directory directory;
  late Store store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-train-wide-');
    store = Store(getObjectBoxModel(), directory: directory.path);
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  Future<void> openTrain(
    WidgetTester tester, {
    required bool program,
    Size size = _wide,
  }) async {
    if (program) seedLibraryProgram(store, 'prog.three');
    final library = ObjectBoxWorkoutLibraryRepository(store);
    for (final name in _planNames) {
      library.savePlan(
        uuid: name,
        name: name,
        description: '',
        exercises: const [],
      );
    }
    await pumpLibraryScreen(
      tester,
      store: store,
      directory: directory,
      location: '/train',
      size: size,
    );
  }

  testWidgets('wide Train puts Your program beside Start training', (
    tester,
  ) async {
    await openTrain(tester, program: true);
    final start = tester.getTopLeft(find.text('Start training'));
    final program = tester.getTopLeft(find.text('Your program'));
    expect(program.dy, start.dy);
    expect(program.dx, greaterThan(start.dx));
  });

  testWidgets('wide Train without a program keeps Start training full width', (
    tester,
  ) async {
    await openTrain(tester, program: false);
    expect(find.text('Your program'), findsNothing);
    final card = find.ancestor(
      of: find.text('Build the work.'),
      matching: find.byType(Card),
    );
    expect(
      tester.getSize(card.first).width,
      tester.getSize(find.byType(ListView).first).width - 32,
    );
  });

  testWidgets('wide Train lays plans in two columns', (tester) async {
    // Tall, so the lazy list builds all three plans.
    await openTrain(tester, program: false, size: const Size(1194, 1600));
    final spots =
        [
          for (final name in _planNames)
            tester.getTopLeft(find.text(name).first),
        ]..sort(
          (a, b) => a.dy != b.dy ? a.dy.compareTo(b.dy) : a.dx.compareTo(b.dx),
        );
    expect(spots[0].dy, spots[1].dy);
    expect(spots[1].dx, greaterThan(spots[0].dx));
    expect(spots[2].dy, greaterThan(spots[0].dy));
  });
}
