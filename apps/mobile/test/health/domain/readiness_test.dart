import 'package:beyondrep/features/health/domain/health_types.dart';
import 'package:beyondrep/features/health/domain/readiness.dart';
import 'package:beyondrep/features/health/domain/sleep_nights.dart';
import 'package:beyondrep/features/health/domain/sleep_score.dart';
import 'package:beyondrep/features/health/domain/training_load.dart';
import 'package:flutter_test/flutter_test.dart';

final today = DateTime(2026, 3, 10);

DateTime daysAgo(int n) => DateTime(today.year, today.month, today.day - n);

SleepNight nightOn(DateTime date, {required int asleep, int deep = 0}) {
  return SleepNight(
    date: date,
    start: date.subtract(const Duration(hours: 8)),
    end: date,
    source: 'test',
    segments: const [],
    asleep: Duration(minutes: asleep),
    deep: Duration(minutes: deep),
    light: Duration(minutes: asleep - deep),
    rem: Duration.zero,
    awake: Duration.zero,
    inBed: null,
  );
}

List<SleepNight> weekOf(int asleep, {int count = 7}) => [
  for (var i = 1; i <= count; i++) nightOn(daysAgo(i), asleep: asleep),
];

SleepScore scoreOf(int v) => SleepScore(value: v, contributors: const {});

/// [values] are the values for days 1..n before today (index 0 = yesterday).
List<DayValue> series(List<double> values, {double? todayValue}) => [
  for (var i = 0; i < values.length; i++)
    (day: daysAgo(i + 1), value: values[i]),
  if (todayValue != null) (day: today, value: todayValue),
];

List<double> alternating(int n, double mean, double dev) => [
  for (var i = 0; i < n; i++) i.isEven ? mean + dev : mean - dev,
];

ReadinessResult score({
  SleepNight? lastNight,
  SleepScore? sleepScore,
  List<SleepNight>? prior,
  List<DayValue> hrv = const [],
  List<DayValue> rhr = const [],
  List<LoadSession> load = const [],
}) => scoreReadiness(
  today: today,
  lastNight: lastNight,
  sleepScore: sleepScore,
  priorNights: prior ?? weekOf(450),
  hrvDaily: hrv,
  restingHrDaily: rhr,
  loadSessions: load,
);

Readiness ready(ReadinessResult r) => (r as ReadinessReady).readiness;

List<LoadSession> loadFor(double r) => [
  (
    start: DateTime(today.year, today.month, today.day - 20, 9),
    minutes: 100 * (4 / r - 1),
    intensity: 1.0,
  ),
  (
    start: DateTime(today.year, today.month, today.day - 3, 9),
    minutes: 100.0,
    intensity: 1.0,
  ),
];

void main() {
  group('baselineOf', () {
    test('excludes today and days older than 30', () {
      final daily = [
        (day: today, value: 1000.0),
        for (var i = 1; i <= 30; i++) (day: daysAgo(i), value: 50.0),
        (day: daysAgo(31), value: 2000.0),
      ];
      final b = baselineOf(daily, today, sdFloor: hrvSdFloor)!;
      expect(b.days, 30);
      expect(b.mean, 50);
    });

    test('null at 13 days, non-null at 14', () {
      List<DayValue> n(int c) => [
        for (var i = 1; i <= c; i++) (day: daysAgo(i), value: 45.0),
      ];
      expect(baselineOf(n(13), today, sdFloor: hrvSdFloor), isNull);
      expect(baselineOf(n(14), today, sdFloor: hrvSdFloor), isNotNull);
    });

    test('applies the floor', () {
      final b = baselineOf(
        series(List.filled(20, 45.0)),
        today,
        sdFloor: hrvSdFloor,
      )!;
      expect(b.sd, closeTo(2.25, 1e-9));
      final r = baselineOf(
        series(List.filled(20, 60.0)),
        today,
        sdFloor: rhrSdFloor,
      )!;
      expect(r.sd, 1.5);
    });

    test('ignores NaN, infinite and non-positive values', () {
      final daily = [
        for (var i = 1; i <= 13; i++) (day: daysAgo(i), value: 45.0),
        (day: daysAgo(14), value: double.nan),
        (day: daysAgo(15), value: 0.0),
        (day: daysAgo(16), value: double.infinity),
        (day: daysAgo(17), value: -3.0),
      ];
      expect(baselineOf(daily, today, sdFloor: hrvSdFloor), isNull);
      final b = baselineOf(
        [...daily, (day: daysAgo(18), value: 45.0)],
        today,
        sdFloor: hrvSdFloor,
      )!;
      expect(b.days, 14);
      expect(b.mean, 45);
    });

    test('keeps one value per calendar day across a DST change', () {
      // 29 Mar 2026 is 23 h long in the EU; the window counts local days.
      final dst = DateTime(2026, 3, 30);
      DateTime before(int n) => DateTime(2026, 3, 30 - n);
      final daily = [
        for (var i = 1; i <= 30; i++) (day: before(i), value: 50.0),
        (day: before(31), value: 2000.0),
        (day: dst, value: 1000.0),
      ];
      final b = baselineOf(daily, dst, sdFloor: hrvSdFloor)!;
      expect(b.days, 30);
      expect(b.mean, 50);
    });
  });

  test('a NaN or zero measure today is not a measure', () {
    final r = score(
      lastNight: nightOn(today, asleep: 450),
      hrv: series(alternating(20, 40, 2), todayValue: double.nan),
      rhr: series(alternating(20, 58, 1), todayValue: 0),
    );
    expect(r, isA<ReadinessNotReady>());
    expect((r as ReadinessNotReady).noHrvOrRhrToday, true);
  });

  test('a zero or NaN measure gives no part beside a valid one', () {
    final r = ready(
      score(
        lastNight: nightOn(today, asleep: 450),
        hrv: series(alternating(20, 40, 2), todayValue: 40),
        rhr: series(alternating(20, 58, 1), todayValue: 0),
      ),
    );
    expect(
      r.parts.map((p) => p.input),
      isNot(contains(ReadinessInput.restingHr)),
    );
    expect(r.parts.map((p) => p.input), contains(ReadinessInput.hrv));
  });

  test('normal day scores Good', () {
    final r = score(
      lastNight: nightOn(today, asleep: 450),
      sleepScore: scoreOf(85),
      hrv: series(alternating(20, 50, 5), todayValue: 50),
      rhr: series(alternating(20, 60, 2), todayValue: 60),
    );
    final v = ready(r);
    expect(v.value, 77);
    expect(v.band, ReadinessBand.good);
  });

  test('mockup low day', () {
    // sd of alternating 50 +/- 5 is exactly 5 (population), 60 +/- 2 is 2;
    // the RHR floor 1.5 does not apply.
    final v = ready(
      score(
        lastNight: nightOn(today, asleep: 340),
        prior: weekOf(425),
        hrv: series(alternating(20, 50, 5), todayValue: 40),
        rhr: series(alternating(20, 60, 2), todayValue: 64),
      ),
    );
    expect(v.value, 48);
    expect(v.band, ReadinessBand.low);
  });

  test('tiny variance does not read as low', () {
    final v = ready(
      score(
        lastNight: nightOn(today, asleep: 450),
        sleepScore: scoreOf(85),
        hrv: series(List.filled(20, 45.0), todayValue: 43),
      ),
    );
    expect(v.band, isNot(ReadinessBand.low));
  });

  test('HRV only today, no resting HR', () {
    final v = ready(
      score(
        lastNight: nightOn(today, asleep: 450),
        sleepScore: scoreOf(80),
        hrv: series(alternating(20, 50, 5), todayValue: 50),
      ),
    );
    expect(v.parts.map((p) => p.input), [
      ReadinessInput.hrv,
      ReadinessInput.sleep,
      ReadinessInput.sleepDebt,
    ]);
    expect(v.parts.fold(0.0, (a, p) => a + p.weight), closeTo(1, 1e-9));
  });

  test('sleep debt drops out with fewer than 3 prior nights', () {
    final v = ready(
      score(
        lastNight: nightOn(today, asleep: 450),
        sleepScore: scoreOf(80),
        prior: weekOf(450, count: 2),
        hrv: series(alternating(20, 50, 5), todayValue: 50),
      ),
    );
    expect(v.parts.map((p) => p.input), [
      ReadinessInput.hrv,
      ReadinessInput.sleep,
    ]);
    expect(v.parts.fold(0.0, (a, p) => a + p.weight), closeTo(1, 1e-9));
  });

  test('HRV today with 9 baseline days, no RHR is not ready', () {
    final r = score(
      lastNight: nightOn(today, asleep: 450),
      hrv: series(List.filled(9, 50.0), todayValue: 50),
    );
    expect(r, isA<ReadinessNotReady>());
    expect((r as ReadinessNotReady).daysUntilBaseline, 5);
  });

  test('HRV without baseline drops out while RHR is ready', () {
    final v = ready(
      score(
        lastNight: nightOn(today, asleep: 450),
        sleepScore: scoreOf(80),
        hrv: series(List.filled(9, 50.0), todayValue: 50),
        rhr: series(alternating(20, 60, 2), todayValue: 60),
      ),
    );
    expect(v.parts.map((p) => p.input), isNot(contains(ReadinessInput.hrv)));
    expect(v.parts.map((p) => p.input), contains(ReadinessInput.restingHr));
  });

  test('no sleep last night is not ready even with HRV', () {
    final r = score(
      hrv: series(alternating(20, 50, 5), todayValue: 50),
    ) as ReadinessNotReady;
    expect(r.noSleep, isTrue);
  });

  test('last night is an older date', () {
    final r = score(
      lastNight: nightOn(daysAgo(1), asleep: 450),
      hrv: series(alternating(20, 50, 5), todayValue: 50),
    ) as ReadinessNotReady;
    expect(r.noSleep, isTrue);
  });

  test('no HRV or RHR today', () {
    final r = score(
      lastNight: nightOn(today, asleep: 450),
      hrv: series(alternating(20, 50, 5)),
      rhr: series(alternating(20, 60, 2)),
    ) as ReadinessNotReady;
    expect(r.noHrvOrRhrToday, isTrue);
    expect(r.noSleep, isFalse);
  });

  test('names every missing input', () {
    final r = score() as ReadinessNotReady;
    expect(r.noSleep, isTrue);
    expect(r.noHrvOrRhrToday, isTrue);
    expect(r.daysUntilBaseline, isNull);
  });

  test('no sleep and baseline building names both', () {
    final r = score(
      hrv: series(List.filled(9, 50.0), todayValue: 50),
    ) as ReadinessNotReady;
    expect(r.noSleep, isTrue);
    expect(r.noHrvOrRhrToday, isFalse);
    expect(r.daysUntilBaseline, 5);
  });

  test('daysUntilBaseline uses the larger count', () {
    final r = score(
      lastNight: nightOn(today, asleep: 450),
      hrv: series(List.filled(9, 50.0), todayValue: 50),
      rhr: series(List.filled(12, 60.0), todayValue: 60),
    ) as ReadinessNotReady;
    expect(r.daysUntilBaseline, 2);
  });

  test('zero-minute week skips sleep debt without throwing', () {
    final v = ready(
      score(
        lastNight: nightOn(today, asleep: 450),
        sleepScore: scoreOf(80),
        prior: weekOf(0),
        hrv: series(alternating(20, 50, 5), todayValue: 50),
      ),
    );
    expect(
      v.parts.map((p) => p.input),
      isNot(contains(ReadinessInput.sleepDebt)),
    );
  });

  group('band edges', () {
    for (final (value, band) in [
      (70, ReadinessBand.good),
      (69, ReadinessBand.fair),
      (50, ReadinessBand.fair),
      (49, ReadinessBand.low),
    ]) {
      test('$value is $band', () {
        expect(readinessBandOf(value), band);
      });
    }
  });

  group('training load', () {
    ReadinessResult withLoad(List<LoadSession> load) => score(
      lastNight: nightOn(today, asleep: 450),
      hrv: series(alternating(20, 40, 2), todayValue: 40),
      rhr: series(alternating(20, 58, 1), todayValue: 58),
      load: load,
    );

    test('no load sessions gives exactly the stage 1 score', () {
      final plain = ready(withLoad(const []));
      expect(
        plain.parts.map((p) => p.input),
        isNot(contains(ReadinessInput.trainingLoad)),
      );
      expect(plain.loadRatio, isNull);
      final same = ready(
        withLoad([(start: daysAgo(3), minutes: 60.0, intensity: 1.0)]),
      );
      expect(same.value, plain.value);
    });

    test('weights are HRV .40, RHR .25, sleep .25, debt .10, load .15 '
        'rescaled', () {
      final r = ready(withLoad(loadFor(1.0)));
      double w(ReadinessInput i) =>
          r.parts.firstWhere((p) => p.input == i).weight;
      expect(w(ReadinessInput.hrv), closeTo(0.40 / 1.15, 1e-9));
      expect(w(ReadinessInput.restingHr), closeTo(0.25 / 1.15, 1e-9));
      expect(w(ReadinessInput.sleep), closeTo(0.25 / 1.15, 1e-9));
      expect(w(ReadinessInput.sleepDebt), closeTo(0.10 / 1.15, 1e-9));
      expect(w(ReadinessInput.trainingLoad), closeTo(0.15 / 1.15, 1e-9));
      expect(r.parts.fold(0.0, (a, p) => a + p.weight), closeTo(1, 1e-9));
      expect(r.loadRatio, closeTo(1.0, 1e-9));
    });
  });
}
