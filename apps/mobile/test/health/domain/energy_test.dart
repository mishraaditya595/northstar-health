import 'package:beyondrep/features/health/domain/energy.dart';
import 'package:beyondrep/features/health/domain/energy_tuning.dart';
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
  EnergyTuning tuning = EnergyTuning.generic,
}) => energyNow(
  start: start ?? startOf(78),
  day: wakingDay,
  now: now,
  sessions: sessions,
  hourlyActiveEnergy: active,
  sleepSegments: sleep,
  tuning: tuning,
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

  group('energyNow with a tuning', () {
    const strong = EnergyTuning(
      usualHours: {},
      drainMultiplier: 1.4,
      calibrated: true,
    );

    test('the multiplier scales a workout drain', () {
      final plain = run(now: t(9), sessions: [session(t(7, 30), 60, 1.0)]);
      final tuned = run(
        now: t(9),
        sessions: [session(t(7, 30), 60, 1.0)],
        tuning: strong,
      );
      expect(kp(plain), [(EnergyItemKind.workout, -12)]);
      expect(kp(tuned), [(EnergyItemKind.workout, -17)]);
      expect(plain.tuned, isFalse);
      expect(tuned.tuned, isTrue);
    });

    test('the active drain is capped after multiplying', () {
      // 3 hours at 160 kcal above the usual: 480 kcal = 12 points, 16.8 tuned.
      final active = [
        for (var i = 1; i <= 10; i++)
          for (var h = 0; h < 24; h++) bucket(t(h, 0, 27 - i), 20),
        for (var h = 7; h <= 9; h++) bucket(t(h), 180),
      ];
      expect(kp(run(now: t(10), active: active)), [
        (EnergyItemKind.activeDay, -12),
      ]);
      expect(kp(run(now: t(10), active: active, tuning: strong)), [
        (EnergyItemKind.activeDay, -15),
      ]);
    });

    test('a multiplier alone is not shown as tuned when not calibrated', () {
      const open = EnergyTuning(
        usualHours: {},
        drainMultiplier: 1.4,
        calibrated: false,
      );
      expect(run(now: t(9), tuning: open).tuned, isFalse);
    });

    test('no awake dip in a usual hour, the dip applies in another', () {
      const night = EnergyTuning(
        usualHours: {22, 23},
        drainMultiplier: 1.0,
        calibrated: false,
      );
      final wake = DateTime(2026, 11, 27, 7);
      final late = energyNow(
        start: startOf(78),
        day: (day: DateTime(2026, 11, 27), wake: wake),
        now: DateTime(2026, 11, 27, 23, 30),
        sessions: const [],
        hourlyActiveEnergy: const [],
        sleepSegments: const [],
        tuning: night,
      );
      expect(late.items, isEmpty);
      expect(late.awakeWaived, isTrue);
      final afternoon = run(now: t(23, 30), tuning: night);
      expect(afternoon.awakeWaived, isTrue);
      final other = energyNow(
        start: startOf(78),
        day: (day: DateTime(2026, 11, 27), wake: DateTime(2026, 11, 26, 23)),
        now: t(15),
        sessions: const [],
        hourlyActiveEnergy: const [],
        sleepSegments: const [],
        tuning: night,
      );
      expect(kp(other), [(EnergyItemKind.awake, -4)]);
      expect(other.awakeWaived, isFalse);
    });

    test('the awake dip fades in over the first hour of usual hours', () {
      const night = EnergyTuning(
        usualHours: {22, 23},
        drainMultiplier: 1.0,
        calibrated: false,
      );
      Energy at(DateTime now) => energyNow(
        start: startOf(78),
        day: (day: DateTime(2026, 11, 27), wake: DateTime(2026, 11, 27, 6)),
        now: now,
        sessions: const [],
        hourlyActiveEnergy: const [],
        sleepSegments: const [],
        tuning: night,
      );
      // About 16 h awake: a 4 point dip outside usual hours.
      final before = at(DateTime(2026, 11, 27, 21, 59));
      expect(kp(before), [(EnergyItemKind.awake, -4)]);
      expect(before.awakeWaiver, 0);
      // Half way into the first usual hour, half of the dip is waived.
      final half = at(DateTime(2026, 11, 27, 22, 30));
      expect(half.awakeWaiver, closeTo(0.5, 1e-9));
      expect(kp(half), [(EnergyItemKind.awake, -2)]);
      expect(half.awakeWaived, isTrue);
      // A full hour in, none of it applies.
      final full = at(DateTime(2026, 11, 27, 23));
      expect(full.awakeWaiver, closeTo(1, 1e-9));
      expect(full.items, isEmpty);
      // It fades back out over the hour after the last usual hour.
      final after = at(DateTime(2026, 11, 28, 0, 15));
      expect(after.awakeWaiver, closeTo(0.75, 1e-9));
    });

    test(
      'usualHourShare counts the minutes of the last hour in usual hours',
      () {
        expect(usualHourShare(const {}, DateTime(2026, 11, 27, 22, 30)), 0);
        expect(
          usualHourShare(const {22}, DateTime(2026, 11, 27, 22, 15)),
          closeTo(0.25, 1e-9),
        );
        expect(
          usualHourShare(const {21}, DateTime(2026, 11, 27, 22, 15)),
          closeTo(0.75, 1e-9),
        );
        expect(
          usualHourShare(const {23}, DateTime(2026, 11, 28, 0, 30)),
          closeTo(0.5, 1e-9),
        );
      },
    );
  });
}
