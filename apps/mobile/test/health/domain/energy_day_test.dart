import 'package:beyondrep/features/health/domain/energy_day.dart';
import 'package:beyondrep/features/health/domain/health_types.dart';
import 'package:beyondrep/features/health/domain/sleep_nights.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime t(int h, [int m = 0, int d = 27]) => DateTime(2026, 11, d, h, m);

SleepNight night(DateTime end) => SleepNight(
  date: DateTime(end.year, end.month, end.day),
  start: end.subtract(const Duration(hours: 7)),
  end: end,
  source: 'watch',
  segments: const [],
  asleep: const Duration(hours: 7),
  deep: Duration.zero,
  light: Duration.zero,
  rem: Duration.zero,
  awake: Duration.zero,
  inBed: null,
);

SleepSegment seg(
  DateTime from,
  DateTime to, {
  SleepStage stage = SleepStage.light,
  String source = 'watch',
}) => (from: from, to: to, stage: stage, source: source, sourceKey: source);

HealthSample bucket(DateTime from, double value) => (
  from: from,
  to: from.add(const Duration(hours: 1)),
  value: value,
  source: 'w',
);

/// [days] usual days before 27 Nov, 20 kcal in every hour 0..23.
List<HealthSample> usualDays(int days, {int? skipHour, int skipOnDays = 0}) => [
  for (var i = 1; i <= days; i++)
    for (var h = 0; h < 24; h++)
      if (!(h == skipHour && i <= skipOnDays)) bucket(t(h, 0, 27 - i), 20),
];

void main() {
  group('wakingDayOf', () {
    test('night ended 06:31 today, now 15:00 -> day 27 Nov, wake 06:31', () {
      final w = wakingDayOf([night(t(6, 31))], t(15));
      expect(w!.day, DateTime(2026, 11, 27));
      expect(w.wake, t(6, 31));
    });
    test('at 00:40 on 28 Nov the waking day is still 27 Nov', () {
      final w = wakingDayOf([night(t(6, 30))], t(0, 40, 28));
      expect(w!.day, DateTime(2026, 11, 27));
    });
    test(
      'exactly 20 hours after waking is still the waking day; 20h 1m is null',
      () {
        final n = [night(t(6))];
        expect(wakingDayOf(n, t(2, 0, 28)), isNotNull);
        expect(wakingDayOf(n, t(2, 1, 28)), isNull);
      },
    );
    test('no nights -> null', () {
      expect(wakingDayOf([], t(15)), isNull);
    });
    test('a night ending after now is skipped and the earlier one is used', () {
      final w = wakingDayOf([night(t(6, 30, 26)), night(t(16))], t(15, 0, 26));
      expect(w!.day, DateTime(2026, 11, 26));
    });
  });

  group('napsIn', () {
    final wake = t(7);
    final now = t(17);
    List<Nap> naps(List<SleepSegment> s) => napsIn(s, wake: wake, now: now);

    test('a 14:00-14:40 light segment is one 40-minute nap', () {
      final n = naps([seg(t(14), t(14, 40))]);
      expect(n, hasLength(1));
      expect(n.single.minutes, 40);
      expect(n.single.start, t(14));
      expect(n.single.end, t(14, 40));
    });
    test('asleep 07:30-07:50 from a second source is no nap', () {
      expect(naps([seg(t(7, 30), t(7, 50), source: 'phone')]), isEmpty);
    });
    test('a 5-minute doze is no nap', () {
      expect(naps([seg(t(14), t(14, 5))]), isEmpty);
    });
    test('a 4-hour sleep 12:00-16:00 is no nap', () {
      expect(naps([seg(t(12), t(16))]), isEmpty);
    });
    test('watch 14:00-14:30 and phone 14:10-14:40 are one 40-minute nap', () {
      final n = naps([
        seg(t(14), t(14, 30)),
        seg(t(14, 10), t(14, 40), source: 'phone'),
      ]);
      expect(n, hasLength(1));
      expect(n.single.minutes, 40);
    });
    test('14:00-14:20 and 14:35-14:55 join into one nap of 40 minutes', () {
      final n = naps([seg(t(14), t(14, 20)), seg(t(14, 35), t(14, 55))]);
      expect(n, hasLength(1));
      expect(n.single.minutes, 40);
      expect(n.single.start, t(14));
      expect(n.single.end, t(14, 55));
    });
    test('14:00-14:20 and 15:00-15:20 are two naps', () {
      final n = naps([seg(t(15), t(15, 20)), seg(t(14), t(14, 20))]);
      expect(n, hasLength(2));
      expect(n.first.start, t(14));
      expect(n.last.start, t(15));
    });
    test('awake and inBed segments are ignored', () {
      expect(
        naps([
          seg(t(14), t(14, 40), stage: SleepStage.awake),
          seg(t(15), t(15, 40), stage: SleepStage.inBed),
        ]),
        isEmpty,
      );
    });
    // Watch night ends at the 07:00 wake; the ring logs the same night in
    // 10-minute light segments with a short gap, running on past 08:00 (more than an hour after waking).
    List<SleepSegment> runOnSegments() => [
      for (var m = 60; m <= 540; m += 10)
        seg(
          t(0).add(Duration(minutes: m)),
          t(0).add(Duration(minutes: m + 8)),
          source: 'ring',
        ),
    ];
    test('a night another source logs past waking is no nap', () {
      expect(naps(runOnSegments()), isEmpty);
    });
    test('a run-on night plus a real afternoon nap gives only that nap', () {
      final n = naps([...runOnSegments(), seg(t(14), t(14, 40))]);
      expect(n, hasLength(1));
      expect(n.single.start, t(14));
      expect(n.single.minutes, 40);
    });
    test('a segment ending after now is ignored', () {
      expect(naps([seg(t(16, 30), t(17, 30))]), isEmpty);
    });
  });

  group('loadSessionEnd', () {
    test('adds minutes with seconds precision', () {
      expect(
        loadSessionEnd((start: t(9), minutes: 30.5, intensity: 0.8)),
        DateTime(2026, 11, 27, 9, 30, 30),
      );
    });
  });

  group('activeExcessKcal', () {
    final day = (day: DateTime(2026, 11, 27), wake: t(7));
    final now = t(15);

    test('two hours at 84 kcal give 128', () {
      final v = activeExcessKcal(
        [...usualDays(7), bucket(t(8), 84), bucket(t(9), 84)],
        day: day,
        now: now,
      );
      expect(v, 128);
    });
    test('an hour below usual adds nothing, never negative', () {
      final v = activeExcessKcal(
        [...usualDays(7), bucket(t(8), 5), bucket(t(9), 30)],
        day: day,
        now: now,
      );
      expect(v, 10);
    });
    test('the 09:00 bucket is skipped when a workout ran 09:00-10:00', () {
      final v = activeExcessKcal(
        [...usualDays(7), bucket(t(9), 100), bucket(t(10), 50)],
        day: day,
        now: now,
        workouts: [(start: t(9), minutes: 60, intensity: 0.8)],
      );
      expect(v, 30);
    });
    test('null with 6 usual days, value with 7', () {
      final today = [bucket(t(8), 40)];
      expect(
        activeExcessKcal([...usualDays(6), ...today], day: day, now: now),
        isNull,
      );
      expect(
        activeExcessKcal([...usualDays(7), ...today], day: day, now: now),
        20,
      );
    });
    test('a day whose buckets are all 0 is not a usual day', () {
      // 6 days with data, plus 27-7 with a 0 kcal bucket in every hour.
      final hourly = [
        ...usualDays(6),
        for (var h = 0; h < 24; h++) bucket(t(h, 0, 20), 0),
        bucket(t(8), 40),
      ];
      expect(activeExcessKcal(hourly, day: day, now: now), isNull);
    });
    test('an empty day in between is not a usual day (no zeros)', () {
      // 6 days with data (27-1..27-6), 27-7 empty, 27-8 with data: 7 usual
      // days, so the usual 08:00 is 140 / 7 = 20 and the excess is 40 - 20.
      final hourly = [
        ...usualDays(6),
        for (var h = 0; h < 24; h++) bucket(t(h, 0, 19), 20),
        bucket(t(8), 40),
      ];
      expect(activeExcessKcal(hourly, day: day, now: now), 20);
    });
    test('the 05:00-06:00 bucket before waking is ignored', () {
      final v = activeExcessKcal(
        [...usualDays(7), bucket(t(5), 500), bucket(t(6), 500)],
        day: day,
        now: now,
      );
      expect(v, 0);
    });
    test('usual for an hour counts 0 on a usual day without that hour', () {
      final hourly = [
        ...usualDays(7, skipHour: 10, skipOnDays: 4),
        bucket(t(10), 80),
      ];
      final v = activeExcessKcal(hourly, day: day, now: now);
      // usual at 10:00 = 60 / 7
      expect(v, closeTo(80 - 60 / 7, 1e-9));
    });
  });

  group('awakeDipPoints', () {
    test('curve', () {
      expect(awakeDipPoints(const Duration(hours: 7)), 0);
      expect(awakeDipPoints(const Duration(hours: 8)), 0);
      expect(awakeDipPoints(const Duration(hours: 10)), 1.0);
      expect(awakeDipPoints(const Duration(hours: 13)), 2.5);
      expect(awakeDipPoints(const Duration(hours: 18)), 5.0);
      expect(awakeDipPoints(const Duration(hours: 20)), 5.0);
    });
  });
}
