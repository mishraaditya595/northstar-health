import 'package:beyondrep/features/health/domain/outside_workouts.dart';
import 'package:beyondrep/features/health/domain/training_load.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:flutter_test/flutter_test.dart';

final today = DateTime(2026, 3, 10);

DateTime daysAgo(int n, [int hour = 9]) =>
    DateTime(today.year, today.month, today.day - n, hour);

LoadSession load(int daysBack, double minutes, [double intensity = 1]) =>
    (start: daysAgo(daysBack), minutes: minutes, intensity: intensity);

/// Earliest session 20 days back, one 100-load session 3 days back, and the
/// older one sized so the 7-day against 28-day ratio is [r].
List<LoadSession> forRatio(double r) => [
  load(20, 100 * (4 / r - 1)),
  load(3, 100),
];

WorkoutSetRecord set(
  String id, {
  double? rpe,
  WorkoutSetKind kind = WorkoutSetKind.working,
  WorkoutSetStatus status = WorkoutSetStatus.completed,
}) => WorkoutSetRecord(
  uuid: id,
  exerciseUuid: 'e',
  position: 0,
  kind: kind,
  status: status,
  reps: 5,
  rpe: rpe,
  completedAtUtc: DateTime.utc(2026, 3, 1),
);

WorkoutSessionRecord session(List<WorkoutSetRecord> sets) =>
    WorkoutSessionRecord(
      uuid: 's',
      name: 'S',
      status: WorkoutStatus.completed,
      startedAtUtc: DateTime.utc(2026, 3, 1, 10),
      completedAtUtc: DateTime.utc(2026, 3, 1, 11),
      originalOffsetMinutes: 0,
      revision: 1,
      sets: sets,
    );

void main() {
  group('trainingLoadOf score curve', () {
    for (final (r, score) in [
      (0.8, 90.0),
      (1.05, 80.0),
      (1.3, 70.0),
      (1.55, 50.0),
      (1.8, 30.0),
      (2.5, 30.0),
      (0.4, 90.0),
    ]) {
      test('r $r -> $score', () {
        final result = trainingLoadOf(forRatio(r), today)!;
        expect(result.ratio, closeTo(r, 1e-9));
        expect(result.score, closeTo(score, 1e-9));
      });
    }
  });

  test('null with 13 days of history, value with 14', () {
    expect(trainingLoadOf([load(13, 60), load(3, 60)], today), isNull);
    expect(trainingLoadOf([load(14, 60), load(3, 60)], today), isNotNull);
  });

  test('null when the 28-day load is zero', () {
    expect(trainingLoadOf(const [], today), isNull);
    expect(trainingLoadOf([load(20, 0), load(3, 0)], today), isNull);
  });

  test('sessions older than 28 days do not count as history', () {
    expect(trainingLoadOf([load(40, 60), load(3, 60)], today), isNull);
  });

  test("today's sessions are ignored", () {
    final base = forRatio(1.0);
    final withToday = [...base, load(0, 500)];
    expect(
      trainingLoadOf(withToday, today)!.ratio,
      trainingLoadOf(base, today)!.ratio,
    );
  });

  group('loadSessions', () {
    test('BeyondRep intensity is mean rated RPE / 10 (8 and 9 -> 0.85)', () {
      final l = loadSessions([
        session([set('a', rpe: 8), set('b', rpe: 9), set('c')]),
      ], const WorkoutMerge());
      expect(l.single.intensity, closeTo(0.85, 1e-9));
      expect(l.single.minutes, 60);
    });

    test('0.8 with none rated; warm-up and incomplete sets are ignored', () {
      final l = loadSessions([
        session([
          set('a'),
          set('w', rpe: 3, kind: WorkoutSetKind.warmup),
          set('p', rpe: 3, status: WorkoutSetStatus.planned),
        ]),
      ], const WorkoutMerge());
      expect(l.single.intensity, 0.8);
    });

    test('outside standalone uses 0.7; merged outside are not counted', () {
      final merged = OutsideWorkout(
        id: 'm',
        kind: OutsideWorkoutKind.strength,
        start: DateTime.utc(2026, 3, 1, 10),
        end: DateTime.utc(2026, 3, 1, 11),
        source: 'x',
      );
      final alone = OutsideWorkout(
        id: 'a',
        kind: OutsideWorkoutKind.running,
        start: DateTime.utc(2026, 3, 2, 10),
        end: DateTime.utc(2026, 3, 2, 10, 30),
        source: 'x',
      );
      final l = loadSessions(
        [session(const [])],
        WorkoutMerge(
          mergedIntoSession: {
            's': [merged],
          },
          standalone: [alone],
        ),
      );
      expect(l, hasLength(2));
      final outside = l.firstWhere((s) => s.intensity == 0.7);
      expect(outside.minutes, 30);
    });
  });
}
