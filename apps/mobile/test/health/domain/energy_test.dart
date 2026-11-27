import 'package:beyondrep/features/health/domain/energy.dart';
import 'package:beyondrep/features/health/domain/health_types.dart';
import 'package:beyondrep/features/health/domain/readiness.dart';
import 'package:beyondrep/features/health/domain/training_load.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime t(int h, [int m = 0, int d = 27]) => DateTime(2026, 11, d, h, m);

SleepSegment seg(DateTime from, DateTime to) => (
  from: from,
  to: to,
  stage: SleepStage.light,
  source: 'watch',
  sourceKey: 'watch',
);

HealthSample bucket(DateTime from, double value) => (
  from: from,
  to: from.add(const Duration(hours: 1)),
  value: value,
  source: 'w',
);

LoadSession session(DateTime start, double minutes, double intensity) =>
    (start: start, minutes: minutes, intensity: intensity);

final wakingDay = (day: DateTime(2026, 11, 27), wake: t(7));

Readiness startOf(int value) =>
    Readiness(value: value, band: readinessBandOf(value), parts: const []);

/// 20 kcal every hour on 17-26 Nov (usualDays days), plus today's buckets.
List<HealthSample> hourly({int usualDays = 10}) => [
  for (var i = 1; i <= usualDays; i++)
    for (var h = 0; h < 24; h++) bucket(t(h, 0, 27 - i), 20),
  bucket(t(7), 200),
  bucket(t(8), 200),
  for (var h = 9; h <= 13; h++) bucket(t(h), 84),
  for (var h = 14; h <= 16; h++) bucket(t(h), 20),
];

Energy run({
  Readiness? start,
  required DateTime now,
  List<LoadSession> sessions = const [],
  List<HealthSample> active = const [],
  List<SleepSegment> sleep = const [],
}) => energyNow(
  start: start ?? startOf(78),
  day: wakingDay,
  now: now,
  sessions: sessions,
  hourlyActiveEnergy: active,
  sleepSegments: sleep,
);

List<(EnergyItemKind, int)> kp(Energy e) => [
  for (final i in e.items) (i.kind, i.points),
];

WorkoutSessionRecord record(WorkoutStatus status, DateTime? completed) =>
    WorkoutSessionRecord(
      uuid: 'u',
      name: 'n',
      status: status,
      startedAtUtc: DateTime.utc(2026, 1, 1),
      originalOffsetMinutes: 0,
      revision: 1,
      completedAtUtc: completed,
    );

void main() {
  group('apportion', () {
    test('largest remainder, ties to the earlier index', () {
      expect(apportion([-9.6, -8.4, -1.5, 3.0]), [-10, -8, -2, 3]);
      expect(apportion([0.4, 0.4, 0.4]), [1, 0, 0]);
      expect(apportion([]), <int>[]);
    });
  });

  group('energyNow', () {
    test('a full day lists every change', () {
      final e = run(
        now: t(17),
        sessions: [session(t(7, 10), 60, 0.75)],
        active: hourly(),
        sleep: [seg(t(14), t(14, 15))],
      );
      expect(kp(e), [
        (EnergyItemKind.workout, -9),
        (EnergyItemKind.activeDay, -8),
        (EnergyItemKind.awake, -1),
        (EnergyItemKind.nap, 3),
      ]);
      expect(e.items[0].at, t(7, 10));
      expect(e.items[2].awakeHours, 10);
      expect(e.value, 63);
      expect(e.band, ReadinessBand.fair);
      expect(e.start, 78);
    });

    test('nothing since waking: no items and value equals start', () {
      final e = run(now: t(9));
      expect(e.items, isEmpty);
      expect(e.value, 78);
    });

    test('a workout that ended before waking or yesterday is not counted', () {
      final e = run(
        now: t(9),
        sessions: [session(t(5, 30), 60, 0.8), session(t(20, 0, 26), 60, 0.8)],
      );
      expect(e.items, isEmpty);
    });

    test('energy never goes below 0', () {
      final e = run(
        start: startOf(10),
        now: t(10),
        sessions: [session(t(7, 30), 120, 0.9)],
      );
      expect(e.value, 0);
      expect(kp(e), [(EnergyItemKind.workout, -22)]);
    });

    test('naps cap at 10 in total', () {
      final e = run(
        start: startOf(80),
        now: t(17),
        sessions: [session(t(7, 30), 100, 1.0)],
        sleep: [seg(t(14), t(14, 40)), seg(t(16), t(16, 30))],
      );
      expect(e.items.map((i) => i.points), [-20, -1, 6, 4]);
      expect(e.items[2].capped, isTrue);
      expect(e.items[3].capped, isTrue);
      expect(e.value, 69);
    });

    test('a nap never lifts energy above the start', () {
      final e = run(
        start: startOf(70),
        now: t(17),
        sleep: [seg(t(13), t(13, 30))],
      );
      expect(kp(e), [(EnergyItemKind.awake, -1), (EnergyItemKind.nap, 1)]);
      expect(e.items[1].capped, isTrue);
      expect(e.value, 70);
    });

    test('no active item with under 7 usual days', () {
      final e = run(
        now: t(17),
        sessions: [session(t(7, 10), 60, 0.75)],
        active: hourly(usualDays: 6),
        sleep: [seg(t(14), t(14, 15))],
      );
      expect(e.items.any((i) => i.kind == EnergyItemKind.activeDay), isFalse);
    });
  });

  group('energyLearningOf', () {
    test('cases', () {
      var l = energyLearningOf(completedSessions: 8, baselineDays: 5);
      expect((l.workoutsNeeded, l.daysNeeded, l.show), (12, 9, true));
      l = energyLearningOf(completedSessions: 20, baselineDays: 14);
      expect(l.show, isFalse);
      l = energyLearningOf(completedSessions: null, baselineDays: 9);
      expect((l.workoutsNeeded, l.daysNeeded, l.show), (null, 5, true));
      l = energyLearningOf(completedSessions: 19, baselineDays: 30);
      expect((l.workoutsNeeded, l.daysNeeded, l.show), (1, null, true));
      l = energyLearningOf(completedSessions: 25, baselineDays: null);
      expect(l.show, isFalse);
    });
  });

  group('completedSessionsWithin', () {
    test('counts the last 90 days', () {
      final now = t(12);
      final n = completedSessionsWithin([
        record(WorkoutStatus.completed, now.subtract(const Duration(days: 89))),
        record(WorkoutStatus.completed, now.subtract(const Duration(days: 91))),
        record(WorkoutStatus.inProgress, now.subtract(const Duration(days: 1))),
      ], now);
      expect(n, 1);
    });
  });
}
