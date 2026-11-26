import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beyondrep/features/progress/muscle_map.dart';
import 'package:beyondrep/features/progress/domain/workout_history_models.dart';
import 'package:beyondrep/features/progress/muscle_recovery.dart';
import 'package:beyondrep/features/progress/workout_history_state.dart';
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
    // Ten hard sets of ten saturate a group, so loads equal the fade.
    sets: [
      for (var i = 0; i < groups.length; i++)
        for (var n = 0; n < 10; n++)
          WorkoutSetRecord(
            uuid: '$id-s$i-$n',
            exerciseUuid: '$id-e$i',
            position: n,
            kind: kind,
            status: muscles[groups[i]]!,
            reps: muscles[groups[i]] == WorkoutSetStatus.completed ? 10 : null,
            rpe: muscles[groups[i]] == WorkoutSetStatus.completed ? 8 : null,
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
    test('maps catalog muscle groups and fades over its window', () {
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

    test('adds up a muscle trained twice, capped at 1', () {
      final recovery = MuscleRecovery.fromWorkouts([
        _workout('old', const Duration(hours: 60), {
          'Back': WorkoutSetStatus.completed,
        }),
        _workout('new', const Duration(hours: 6), {
          'Back': WorkoutSetStatus.completed,
        }),
      ], _now);
      expect(recovery.loadOf(Muscle.lats), 1);
    });

    test('ignores old, unfinished, skipped and warm-up work', () {
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
      ], _now);
      expect(recovery.load, isEmpty);
      expect(recovery.groups, isEmpty);
    });

    test('names a custom group it cannot draw instead of saying none', () {
      final recovery = MuscleRecovery.fromWorkouts([
        _workout('custom', const Duration(hours: 1), {
          'Full body': WorkoutSetStatus.completed,
          '  ': WorkoutSetStatus.completed,
        }),
      ], _now);
      expect(recovery.load, isEmpty);
      expect(recovery.groups.keys, ['Full body']);
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
    expect(find.textContaining('48 to 72 hours'), findsOneWidget);
  });

  testWidgets('after an RDL day the hamstrings are worked and quads are not', (
    tester,
  ) async {
    final at = _now;
    final rdl = WorkoutSessionRecord(
      uuid: 'rdl',
      name: 'RDL',
      status: WorkoutStatus.completed,
      startedAtUtc: at.subtract(const Duration(minutes: 40)),
      completedAtUtc: at,
      originalOffsetMinutes: 0,
      revision: 1,
      exercises: const [
        WorkoutExerciseRecord(
          uuid: 'e',
          sessionUuid: 'rdl',
          nameSnapshot: 'Romanian deadlift',
          muscleSnapshot: 'Legs',
          position: 0,
          primaryMusclesSnapshot: ['hamstrings', 'glutes'],
          secondaryMusclesSnapshot: ['lowerBack'],
        ),
      ],
      sets: [
        for (var i = 0; i < 10; i++)
          WorkoutSetRecord(
            uuid: 's$i',
            exerciseUuid: 'e',
            position: i,
            kind: WorkoutSetKind.working,
            status: WorkoutSetStatus.completed,
            reps: 10,
            rpe: 8,
            completedAtUtc: at,
          ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          completedWorkoutHistoryProvider.overrideWith(
            (ref) async => WorkoutHistorySnapshot(sessions: [rdl]),
          ),
          progressNowProvider.overrideWithValue(_now),
        ],
        child: const MaterialApp(home: Scaffold(body: MuscleRecoveryCard())),
      ),
    );
    await tester.pumpAndSettle();

    for (final map in tester.widgetList<MuscleMap>(find.byType(MuscleMap))) {
      expect(map.recovery.loadOf(Muscle.hamstrings), closeTo(1, .001));
      expect(map.recovery.loadOf(Muscle.glutes), closeTo(1, .001));
      expect(map.recovery.loadOf(Muscle.lowerBack), closeTo(.5, .001));
      expect(map.recovery.loadOf(Muscle.quads), 0);
    }
    expect(find.text('Hamstrings · Glutes · Lower back'), findsOneWidget);
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

  testWidgets('a group below the recovered threshold is not listed', (
    tester,
  ) async {
    Future<void> pump(double load) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          muscleRecoveryProvider.overrideWithValue(
            MuscleRecovery({Muscle.chest: load}, groups: {'Chest': load}),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: MuscleRecoveryCard())),
      ),
    );
    await pump(0.09);
    expect(find.text('No muscle group trained recently'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Recently trained: none')),
      findsOneWidget,
    );
    await pump(0.11);
    expect(find.text('Chest'), findsOneWidget);
  });

  testWidgets('card legend wraps on a phone instead of overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: MuscleRecoveryCard())),
      ),
    );
    expect(find.text('Recently trained'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card legend fills the card width on a phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: MuscleRecoveryCard())),
      ),
    );
    // The legend fills the card's width, so centring is relative to the card.
    final wrap = find.ancestor(
      of: find.text('Recovered'),
      matching: find.byType(Wrap),
    );
    expect(tester.getRect(wrap).center.dx, closeTo(195, 1));
    expect(tester.getSize(wrap).width, greaterThan(300));
  });
}
