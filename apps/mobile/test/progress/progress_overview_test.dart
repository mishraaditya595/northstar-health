import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/features/progress/domain/progress_overview.dart';
import 'package:northstar_health/features/progress/domain/workout_history_models.dart';
import 'package:northstar_health/features/workouts/domain/workout_models.dart';

/// A finished session ending [finished] (UTC, offset 0), lasting [minutes],
/// with [loaded] completed working sets of 5 reps × 100 kg.
WorkoutSessionRecord session(
  String id,
  DateTime finished, {
  int minutes = 30,
  int loaded = 1,
}) => WorkoutSessionRecord(
  uuid: id,
  name: id,
  status: WorkoutStatus.completed,
  startedAtUtc: finished.subtract(Duration(minutes: minutes)),
  completedAtUtc: finished,
  originalOffsetMinutes: 0,
  revision: 3,
  exercises: [
    WorkoutExerciseRecord(
      uuid: 'ex-$id',
      sessionUuid: id,
      definitionUuid: 'bench',
      nameSnapshot: 'Bench',
      position: 0,
    ),
  ],
  sets: [
    for (var i = 0; i < loaded; i++)
      WorkoutSetRecord(
        uuid: '$id-$i',
        exerciseUuid: 'ex-$id',
        position: i,
        kind: WorkoutSetKind.working,
        status: WorkoutSetStatus.completed,
        reps: 5,
        loadGrams: 100000,
      ),
  ],
);

WorkoutHistorySnapshot snap(List<WorkoutSessionRecord> s) =>
    WorkoutHistorySnapshot(sessions: s);

void main() {
  // Saturday 24 Oct 2026. Weeks run Sunday to Saturday: this week is 18-24 Oct.
  final today = DateTime.utc(2026, 10, 24);

  group('weekOverview', () {
    test('sums this week and compares with the week before', () {
      final overview = weekOverview(
        snap([
          session('a', DateTime.utc(2026, 10, 19, 18), loaded: 2), // 1000
          session('b', DateTime.utc(2026, 10, 22, 18), minutes: 45), // 500
          session('c', DateTime.utc(2026, 10, 14, 18)), // last week: 500
        ]),
        today,
      );
      expect(overview.volumeGramReps, 1500000);
      expect(overview.previousVolumeGramReps, 500000);
      expect(overview.volumeChangePercent, 200);
      expect(overview.workoutTime, const Duration(minutes: 75));
      expect(overview.previousWorkoutTime, const Duration(minutes: 30));
      expect(overview.sessions, 2);
    });

    test('a week with no loaded sets has no volume, never zero', () {
      final overview = weekOverview(
        snap([session('a', DateTime.utc(2026, 10, 20, 18), loaded: 0)]),
        today,
      );
      expect(overview.volumeGramReps, isNull);
      expect(overview.volumeChangePercent, isNull);
      expect(overview.sessions, 1);
      expect(overview.workoutTime, const Duration(minutes: 30));
    });

    test('no trend without a previous week to compare', () {
      final overview = weekOverview(
        snap([session('a', DateTime.utc(2026, 10, 20, 18))]),
        today,
      );
      expect(overview.volumeGramReps, 500000);
      expect(overview.volumeChangePercent, isNull);
    });

    test('the original local day decides the week, not the device zone', () {
      // 00:30 UTC on Sunday 25 Oct is still Saturday 24 Oct at -05:00.
      final late = session('late', DateTime.utc(2026, 10, 25, 0, 30));
      final shifted = WorkoutSessionRecord(
        uuid: late.uuid,
        name: late.name,
        status: late.status,
        startedAtUtc: late.startedAtUtc,
        completedAtUtc: late.completedAtUtc,
        originalOffsetMinutes: -300,
        revision: late.revision,
        exercises: late.exercises,
        sets: late.sets,
      );
      expect(weekOverview(snap([shifted]), today).sessions, 1);
    });
  });

  group('monthConsistency', () {
    test('marks trained days of the month and counts all sessions', () {
      final consistency = monthConsistency(
        snap([
          session('a', DateTime.utc(2026, 10, 3, 9)),
          session('b', DateTime.utc(2026, 10, 3, 18)), // same day
          session('c', DateTime.utc(2026, 10, 20, 9)),
          session('d', DateTime.utc(2026, 9, 28, 9)), // other month
        ]),
        today,
        DateTime.utc(2026, 10),
      );
      expect(consistency.trainedDays, {3, 20});
      expect(consistency.totalSessions, 4);
      expect(consistency.month, DateTime.utc(2026, 10));
    });

    test('week streak counts back through consecutive trained weeks', () {
      final streak = monthConsistency(
        snap([
          session('this', DateTime.utc(2026, 10, 20, 9)),
          session('last', DateTime.utc(2026, 10, 13, 9)),
          session('older', DateTime.utc(2026, 10, 6, 9)),
          session('gap', DateTime.utc(2026, 9, 15, 9)),
        ]),
        today,
        DateTime.utc(2026, 10),
      );
      expect(streak.weekStreak, 3);
    });

    test('an empty current week does not break the streak yet', () {
      final streak = monthConsistency(
        snap([
          session('last', DateTime.utc(2026, 10, 14, 9)),
          session('older', DateTime.utc(2026, 10, 7, 9)),
        ]),
        today,
        DateTime.utc(2026, 10),
      );
      expect(streak.weekStreak, 2);
    });

    test('no workouts means no streak', () {
      final streak = monthConsistency(snap([]), today, DateTime.utc(2026, 10));
      expect(streak.weekStreak, 0);
      expect(streak.totalSessions, 0);
      expect(streak.trainedDays, isEmpty);
    });
  });

  group('duration formats', () {
    test('short form for tiles', () {
      expect(formatDurationShort(Duration.zero), '0m');
      expect(formatDurationShort(const Duration(seconds: 59)), '0m');
      expect(formatDurationShort(const Duration(minutes: 26)), '26m');
      expect(formatDurationShort(const Duration(minutes: 60)), '1h');
      expect(formatDurationShort(const Duration(minutes: 75)), '1h 15m');
    });

    test('clock form for summaries', () {
      expect(
        formatDurationClock(const Duration(minutes: 26, seconds: 44)),
        '00:26:44',
      );
      expect(
        formatDurationClock(const Duration(hours: 2, seconds: 5)),
        '02:00:05',
      );
    });
  });
}
