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
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('reps-set-a')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      '9',
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('weight-set-a')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      '75.75',
    );

    // An actual persisted change for THIS row must update its editor.
    redraw(() => current = completed());
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('reps-set-a')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      '8',
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('weight-set-a')),
              matching: find.byType(TextField),
            ),
          )
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
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('weight-set-a')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      '101.25',
    );
    await tester.tap(find.byTooltip('Update set 1'));
    await tester.pump();
    expect(writes, hasLength(1));
    expect(writes.single.$1.loadGrams, 101250);
  });

  testWidgets('completed set cannot be skipped without confirmation', (
    tester,
  ) async {
    current = completed();
    await render(tester);
    await tester.tap(find.byTooltip('Set 1 options'));
    await tester.pumpAndSettle();
    expect(find.text('Skip set'), findsNothing);
    expect(writes, isEmpty);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    redraw(() => current = planned);
    await tester.pump();
    await tester.tap(find.byTooltip('Set 1 options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip set'));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    expect(writes.single.$1.status, WorkoutSetStatus.skipped);
  });

  testWidgets('updating completed set does not restart rest countdown', (
    tester,
  ) async {
    current = completed();
    await render(tester);
    await tester.tap(find.byTooltip('Update set 1'));
    expect(writes.single.$2, isNull);
    writes.clear();
    redraw(() => current = planned);
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('reps-set-a')), '8');
    await tester.tap(find.byTooltip('Save set 1'));
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
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('weight-set-a')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      '225.0',
    );
    await tester.tap(find.byTooltip('Update set 1'));
    await tester.pump();
    expect(writes, hasLength(1));
    expect(writes.single.$1.inputUnit, LoadUnit.lb);
    expect(writes.single.$1.loadGrams, 102058);
  });

  group('set options and remove', () {
    Future<void> pumpTile(
      WidgetTester tester, {
      Future<bool> Function()? onRemove,
      bool enabled = true,
      WorkoutSetRecord? previous,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SetEditorTile(
                record: planned,
                enabled: enabled,
                previous: previous,
                onSave: (_, _) {},
                onRemove: onRemove,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('remove lives in the options sheet and calls back once', (
      tester,
    ) async {
      var removed = 0;
      await pumpTile(
        tester,
        onRemove: () async {
          removed++;
          return true;
        },
      );
      await tester.tap(find.byTooltip('Set 1 options'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Remove set'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove set'));
      await tester.pumpAndSettle();
      expect(removed, 1);
    });

    testWidgets('no remove option without a handler', (tester) async {
      await pumpTile(tester);
      await tester.tap(find.byTooltip('Set 1 options'));
      await tester.pumpAndSettle();
      expect(find.text('Remove set'), findsNothing);
    });

    testWidgets('options are unavailable while the workout is paused', (
      tester,
    ) async {
      await pumpTile(tester, onRemove: () async => true, enabled: false);
      await tester.tap(find.byTooltip('Set 1 options'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Remove set'), findsNothing);
    });

    testWidgets('previous values are only copied when tapped', (tester) async {
      final previous = completed(grams: 60000);
      await pumpTile(tester, previous: previous);
      TextField field(String key) => tester.widget<TextField>(
        find.descendant(
          of: find.byKey(ValueKey('$key-set-a')),
          matching: find.byType(TextField),
        ),
      );
      expect(field('reps').controller!.text, isEmpty);
      expect(field('weight').controller!.text, isEmpty);
      await tester.tap(find.byTooltip('Use previous 60kg × 8'));
      await tester.pump();
      expect(field('reps').controller!.text, '8');
      expect(field('weight').controller!.text, '60.0');
    });

    testWidgets('row lays out badge, load, reps and check on one line', (
      tester,
    ) async {
      await pumpTile(tester);
      final tile = tester.getRect(find.byType(SetEditorTile));
      final badge = tester.getRect(find.byTooltip('Set 1 options'));
      final check = tester.getRect(find.byTooltip('Save set 1'));
      expect(badge.left, lessThan(tile.left + 20));
      expect(check.right, greaterThan(tile.right - 20));
      expect((badge.center.dy - check.center.dy).abs(), lessThan(2));
    });

    testWidgets('swiping the row left removes the set', (tester) async {
      var removed = 0;
      await pumpTile(
        tester,
        onRemove: () async {
          removed++;
          return false; // the page re-renders the list; the row never lingers
        },
      );
      await tester.drag(find.byType(SetEditorTile), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(removed, 1);
    });

    testWidgets('a short swipe does nothing', (tester) async {
      var removed = 0;
      await pumpTile(
        tester,
        onRemove: () async {
          removed++;
          return false;
        },
      );
      await tester.drag(find.byType(SetEditorTile), const Offset(-40, 0));
      await tester.pumpAndSettle();
      expect(removed, 0);
    });

    testWidgets('no swipe while paused or without a handler', (tester) async {
      var removed = 0;
      await pumpTile(
        tester,
        enabled: false,
        onRemove: () async {
          removed++;
          return false;
        },
      );
      await tester.drag(find.byType(SetEditorTile), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(removed, 0);
      await pumpTile(tester);
      await tester.drag(find.byType(SetEditorTile), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.byType(SetEditorTile), findsOneWidget);
    });
  });
}
