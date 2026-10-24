import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/units/load_units.dart';
import 'package:northstar_health/features/train/active_workout_page.dart';
import 'package:northstar_health/features/workouts/domain/workout_models.dart';

const planned = WorkoutSetRecord(
  uuid: 'set-a',
  exerciseUuid: 'exercise-a',
  position: 0,
  kind: WorkoutSetKind.working,
  status: WorkoutSetStatus.planned,
);

WorkoutSetRecord completed({
  int grams = 101250,
  LoadUnit inputUnit = LoadUnit.kg,
}) => WorkoutSetRecord(
  uuid: 'set-a',
  exerciseUuid: 'exercise-a',
  position: 0,
  kind: WorkoutSetKind.working,
  status: WorkoutSetStatus.completed,
  reps: 8,
  loadGrams: grams,
  inputUnit: inputUnit,
  rpe: 8,
  completedAtUtc: DateTime.utc(2026, 10, 24, 8),
);

void main() {
  late WorkoutSetRecord current;
  late List<(WorkoutSetRecord, int?)> writes;
  late StateSetter redraw;

  Future<void> render(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) {
                redraw = setState;
                return SetEditorTile(
                  key: ValueKey(current.uuid),
                  record: current,
                  enabled: true,
                  onSave: (value, rest) => writes.add((value, rest)),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    current = planned;
    writes = [];
  });

  testWidgets('uncommitted fields survive unrelated parent rebuild', (
    tester,
  ) async {
    await render(tester);
    await tester.enterText(find.byKey(const ValueKey('reps-set-a')), '9');
    await tester.enterText(find.byKey(const ValueKey('weight-set-a')), '75.75');
    // Mimic an independent set saving: parent rerenders, but this saved
    // record has not changed. Its unsaved draft must not be reset.
    redraw(
      () => current = const WorkoutSetRecord(
        uuid: 'set-a',
        exerciseUuid: 'exercise-a',
        position: 0,
        kind: WorkoutSetKind.working,
        status: WorkoutSetStatus.planned,
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('reps-set-a')))
          .controller!
          .text,
      '9',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('weight-set-a')))
          .controller!
          .text,
      '75.75',
    );

    // An actual persisted change for THIS row must update its editor.
    redraw(() => current = completed());
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('reps-set-a')))
          .controller!
          .text,
      '8',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('weight-set-a')))
          .controller!
          .text,
      '101.25',
    );
  });

  testWidgets('updating saved 101.25 kg does not silently round grams', (
    tester,
  ) async {
    current = completed();
    await render(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('weight-set-a')))
          .controller!
          .text,
      '101.25',
    );
    await tester.tap(find.text('Update set'));
    await tester.pump();
    expect(writes, hasLength(1));
    expect(writes.single.$1.loadGrams, 101250);
  });

  testWidgets('completed set cannot be skipped without confirmation', (
    tester,
  ) async {
    current = completed();
    await render(tester);
    final skip = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Skip'),
    );
    expect(skip.onPressed, isNull);
    expect(writes, isEmpty);
    redraw(() => current = planned);
    await tester.pump();
    await tester.tap(find.text('Skip'));
    expect(writes, hasLength(1));
    expect(writes.single.$1.status, WorkoutSetStatus.skipped);
  });

  testWidgets('updating completed set does not restart rest countdown', (
    tester,
  ) async {
    current = completed();
    await render(tester);
    await tester.tap(find.text('Update set'));
    expect(writes.single.$2, isNull);
    writes.clear();
    redraw(() => current = planned);
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('reps-set-a')), '8');
    await tester.tap(find.text('Save set'));
    expect(writes, hasLength(1));
    expect(writes.single.$2, 90);
  });
  testWidgets('225 lb displays cleanly and round-trips the saved grams', (
    tester,
  ) async {
    current = completed(grams: 102058, inputUnit: LoadUnit.lb);
    await render(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('weight-set-a')))
          .controller!
          .text,
      '225.0',
    );
    await tester.tap(find.text('Update set'));
    await tester.pump();
    expect(writes, hasLength(1));
    expect(writes.single.$1.inputUnit, LoadUnit.lb);
    expect(writes.single.$1.loadGrams, 102058);
  });
}
