import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beyondrep/features/progress/muscle_map.dart';
import 'package:beyondrep/features/progress/muscle_recovery.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';

final _now = DateTime.utc(2026, 11, 24, 12);

WorkoutSessionRecord _workout(
  String id,
  Duration ago,
  Map<String, WorkoutSetStatus> muscles, {
  WorkoutStatus status = WorkoutStatus.completed,
  WorkoutSetKind kind = WorkoutSetKind.working,
}) {
  final at = _now.subtract(ago);
  final groups = muscles.keys.toList();
  return WorkoutSessionRecord(
    uuid: id,
    name: id,
    status: status,
    startedAtUtc: at.subtract(const Duration(minutes: 40)),
    completedAtUtc: status == WorkoutStatus.completed ? at : null,
    originalOffsetMinutes: 0,
    revision: 1,
    exercises: [
      for (var i = 0; i < groups.length; i++)
        WorkoutExerciseRecord(
          uuid: '$id-e$i',
          sessionUuid: id,
          nameSnapshot: 'Exercise $i',
          muscleSnapshot: groups[i],
          position: i,
        ),
    ],
    sets: [
      for (var i = 0; i < groups.length; i++)
        WorkoutSetRecord(
          uuid: '$id-s$i',
          exerciseUuid: '$id-e$i',
          position: 0,
          kind: kind,
          status: muscles[groups[i]]!,
          reps: muscles[groups[i]] == WorkoutSetStatus.completed ? 8 : null,
          completedAtUtc: muscles[groups[i]] == WorkoutSetStatus.completed
              ? at
              : null,
        ),
    ],
  );
}

void main() {
  test('clamps loads and treats missing muscles as recovered', () {
    const recovery = MuscleRecovery({Muscle.abs: 4});
    expect(recovery.loadOf(Muscle.abs), 1);
    expect(recovery.loadOf(Muscle.calves), 0);
  });

  group('fromWorkouts', () {
    test('maps catalog muscle groups and fades over three days', () {
      final recovery = MuscleRecovery.fromWorkouts([
        _workout('legs', const Duration(hours: 18), {
          'Legs': WorkoutSetStatus.completed,
        }),
        _workout('chest', const Duration(hours: 54), {
          ' chest ': WorkoutSetStatus.completed,
        }),
      ], _now);
      for (final m in [
        Muscle.quads,
        Muscle.hamstrings,
        Muscle.glutes,
        Muscle.calves,
      ]) {
        expect(recovery.loadOf(m), closeTo(.75, .001));
      }
      expect(recovery.loadOf(Muscle.chest), closeTo(.25, .001));
      expect(recovery.loadOf(Muscle.lats), 0);
      // The card names what was logged, not individual muscles.
      expect(recovery.groups.keys, unorderedEquals(['Legs', 'Chest']));
      expect(recovery.groups['Legs'], closeTo(.75, .001));
    });

    test('keeps the freshest load when a muscle was trained twice', () {
      final recovery = MuscleRecovery.fromWorkouts([
        _workout('old', const Duration(hours: 60), {
          'Back': WorkoutSetStatus.completed,
        }),
        _workout('new', const Duration(hours: 6), {
          'Back': WorkoutSetStatus.completed,
        }),
      ], _now);
      expect(recovery.loadOf(Muscle.lats), closeTo(1 - 6 / 72, .001));
    });

    test('ignores old, unfinished, skipped, warm-up and unknown work', () {
      final recovery = MuscleRecovery.fromWorkouts([
        _workout('old', const Duration(hours: 73), {
          'Arms': WorkoutSetStatus.completed,
        }),
        _workout('paused', const Duration(hours: 1), {
          'Core': WorkoutSetStatus.completed,
        }, status: WorkoutStatus.paused),
        _workout('skipped', const Duration(hours: 1), {
          'Shoulders': WorkoutSetStatus.skipped,
        }),
        _workout('warmup', const Duration(hours: 1), {
          'Chest': WorkoutSetStatus.completed,
        }, kind: WorkoutSetKind.warmup),
        _workout('custom', const Duration(hours: 1), {
          'Full body': WorkoutSetStatus.completed,
        }),
      ], _now);
      expect(recovery.load, isEmpty);
      expect(recovery.groups, isEmpty);
    });

    test('accepts a custom group named after a drawn muscle', () {
      final recovery = MuscleRecovery.fromWorkouts([
        _workout('g', Duration.zero, {'Glutes': WorkoutSetStatus.completed}),
      ], _now);
      expect(recovery.load, {Muscle.glutes: 1.0});
      expect(recovery.groups, {'Glutes': 1.0});
    });
  });

  testWidgets('card draws front and back figures from workouts', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: MuscleRecoveryCard())),
      ),
    );
    expect(find.text('Muscle Recovery'), findsOneWidget);
    expect(find.text('Sample data'), findsNothing);
    expect(find.byType(MuscleMap), findsNWidgets(2));
    expect(find.textContaining('last 3 days'), findsOneWidget);
  });

  testWidgets('names recently trained muscles for screen readers', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          muscleRecoveryProvider.overrideWithValue(
            const MuscleRecovery(
              {Muscle.quads: 1, Muscle.calves: 1},
              groups: {'Legs': 1},
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: MuscleRecoveryCard())),
      ),
    );
    expect(
      find.bySemanticsLabel(RegExp('Recently trained: Legs')),
      findsOneWidget,
    );
  });

  testWidgets('figures are labelled front and back', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: MuscleRecoveryCard())),
      ),
    );
    expect(find.text('FRONT'), findsOneWidget);
    expect(find.text('BACK'), findsOneWidget);
  });

  testWidgets('lists the recently trained muscle groups', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          muscleRecoveryProvider.overrideWithValue(
            const MuscleRecovery(
              {Muscle.lats: 1, Muscle.chest: .8, Muscle.abs: .2},
              groups: {'Core': .2, 'Back': 1, 'Chest': .8},
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: MuscleRecoveryCard())),
      ),
    );
    // Most recently trained first; anything inside the window is listed.
    expect(find.text('Back · Chest · Core'), findsOneWidget);
    expect(find.textContaining('Lats'), findsNothing);
  });

  testWidgets('says so when nothing was trained recently', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          muscleRecoveryProvider.overrideWithValue(const MuscleRecovery({})),
        ],
        child: const MaterialApp(home: Scaffold(body: MuscleRecoveryCard())),
      ),
    );
    expect(find.text('No muscle group trained recently'), findsOneWidget);
  });
}
