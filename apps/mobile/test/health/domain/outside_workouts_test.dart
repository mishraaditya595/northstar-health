import 'package:beyondrep/features/health/domain/outside_workouts.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime t(int h, int m) => DateTime.utc(2026, 3, 10, h, m);

WorkoutSessionRecord session(
  String uuid,
  DateTime start,
  DateTime? end, {
  WorkoutStatus status = WorkoutStatus.completed,
}) => WorkoutSessionRecord(
  uuid: uuid,
  name: 'Session',
  status: status,
  startedAtUtc: start,
  originalOffsetMinutes: 0,
  revision: 1,
  completedAtUtc: end,
);

OutsideWorkout outside(
  String id,
  DateTime start,
  DateTime end, {
  double? kcal,
  String source = 'Apple Watch',
}) => OutsideWorkout(
  id: id,
  kind: OutsideWorkoutKind.strength,
  start: start,
  end: end,
  activeKcal: kcal,
  source: source,
);

void main() {
  test('names', () {
    expect(
      outsideWorkoutName(OutsideWorkoutKind.strength),
      'Strength training',
    );
    expect(outsideWorkoutName(OutsideWorkoutKind.hiit), 'HIIT');
    expect(outsideWorkoutName(OutsideWorkoutKind.other), 'Workout');
  });

  test('outside workout 10:00-10:30 merges into session 10:05-10:50 '
      '(25 of 30 min overlap)', () {
    final m = mergeWorkouts(
      [session('s', t(10, 5), t(10, 50))],
      [outside('o', t(10, 0), t(10, 30))],
    );
    expect(m.mergedIntoSession['s']!.single.id, 'o');
    expect(m.standalone, isEmpty);
  });

  test('exactly 50% of the shorter merges; 49% does not', () {
    final s = session('s', t(10, 0), t(11, 0));
    final yes = mergeWorkouts([s], [outside('o', t(10, 30), t(11, 30))]);
    expect(yes.mergedIntoSession['s'], hasLength(1));
    final no = mergeWorkouts([s], [outside('o', t(10, 31), t(11, 31))]);
    expect(no.mergedIntoSession, isEmpty);
    expect(no.standalone, hasLength(1));
  });

  test('a 2-hour outside workout spanning two sessions merges only into '
      'the larger overlap', () {
    final m = mergeWorkouts(
      [session('a', t(10, 0), t(10, 40)), session('b', t(11, 0), t(12, 0))],
      [outside('o', t(10, 0), t(12, 0))],
    );
    expect(m.mergedIntoSession.keys, ['b']);
    expect(m.standalone, isEmpty);
  });

  test('on a tie it merges into the earlier session', () {
    final m = mergeWorkouts(
      [session('b', t(11, 0), t(12, 0)), session('a', t(10, 0), t(11, 0))],
      [outside('o', t(10, 0), t(12, 0))],
    );
    expect(m.mergedIntoSession.keys, ['a']);
  });

  test('two outside workouts both merge into one session and mergedSummary '
      'sums kcal 131 + 40 = 171 and keeps the first source', () {
    final m = mergeWorkouts(
      [session('s', t(10, 0), t(11, 0))],
      [
        outside('o1', t(10, 0), t(10, 30), kcal: 131, source: 'Apple Watch'),
        outside('o2', t(10, 30), t(11, 0), kcal: 40, source: 'Other'),
      ],
    );
    final summary = mergedSummary(m.mergedIntoSession['s']!)!;
    expect(summary.kcal, 171);
    expect(summary.source, 'Apple Watch');
  });

  test(
    'mergedSummary kcal is null when every merged workout has null kcal',
    () {
      final summary = mergedSummary([outside('o', t(10, 0), t(10, 30))])!;
      expect(summary.kcal, isNull);
      expect(mergedSummary(const []), isNull);
    },
  );

  test('in-progress and discarded sessions never absorb outside workouts', () {
    final m = mergeWorkouts(
      [
        session('p', t(10, 0), null, status: WorkoutStatus.inProgress),
        session('d', t(10, 0), t(11, 0), status: WorkoutStatus.discarded),
      ],
      [outside('o', t(10, 0), t(10, 30))],
    );
    expect(m.mergedIntoSession, isEmpty);
    expect(m.standalone, hasLength(1));
  });

  test('standalone is newest first', () {
    final m = mergeWorkouts(const [], [
      outside('old', t(8, 0), t(8, 30)),
      outside('new', t(12, 0), t(12, 30)),
    ]);
    expect(m.standalone.map((w) => w.id), ['new', 'old']);
  });

  group('duplicate outside workouts', () {
    test('two overlapping runs from different sources show as one, keeping '
        'the one with kcal', () {
      final m = mergeWorkouts(const [], [
        outside('fit', t(10, 0), t(10, 30), source: 'Fit'),
        outside('samsung', t(10, 1), t(10, 31), kcal: 200, source: 'Samsung'),
      ]);
      expect(m.standalone.map((w) => w.id), ['samsung']);
    });

    test('then the longer duration, then the earlier start', () {
      final longer = mergeWorkouts(const [], [
        outside('short', t(10, 0), t(10, 20)),
        outside('long', t(10, 0), t(10, 30)),
      ]);
      expect(longer.standalone.map((w) => w.id), ['long']);
      final earlier = mergeWorkouts(const [], [
        outside('late', t(10, 5), t(10, 35)),
        outside('early', t(10, 0), t(10, 30)),
      ]);
      expect(earlier.standalone.map((w) => w.id), ['early']);
    });

    test('exactly 50% of the shorter is a duplicate; 49% is not', () {
      expect(
        mergeWorkouts(const [], [
          outside('a', t(10, 0), t(11, 0)),
          outside('b', t(10, 30), t(11, 30)),
        ]).standalone,
        hasLength(1),
      );
      expect(
        mergeWorkouts(const [], [
          outside('a', t(10, 0), t(11, 0)),
          outside('b', t(10, 31), t(11, 31)),
        ]).standalone,
        hasLength(2),
      );
    });

    test('back-to-back workouts both stay', () {
      final m = mergeWorkouts(const [], [
        outside('a', t(10, 0), t(10, 30)),
        outside('b', t(10, 30), t(11, 0)),
      ]);
      expect(m.standalone, hasLength(2));
    });

    test('duplicates collapse before merging into a session', () {
      final m = mergeWorkouts(
        [session('s', t(10, 0), t(11, 0))],
        [
          outside('a', t(10, 0), t(10, 30), kcal: 100),
          outside('b', t(10, 2), t(10, 32), kcal: 120, source: 'Other'),
        ],
      );
      expect(m.mergedIntoSession['s'], hasLength(1));
      expect(mergedSummary(m.mergedIntoSession['s']!)!.kcal, 100);
    });
  });
}
