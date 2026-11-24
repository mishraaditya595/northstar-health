import 'package:beyondrep/features/health/domain/sleep_nights.dart';
import 'package:beyondrep/features/health/domain/sleep_score.dart';
import 'package:flutter_test/flutter_test.dart';

SleepNight night({
  required DateTime start,
  required int asleep,
  required int deep,
  required int rem,
  int? inBed,
}) {
  final light = asleep - deep - rem;
  return SleepNight(
    date: DateTime(start.year, start.month, start.day + 1),
    start: start,
    end: start.add(Duration(minutes: inBed ?? asleep)),
    source: 'test',
    segments: const [],
    asleep: Duration(minutes: asleep),
    deep: Duration(minutes: deep),
    light: Duration(minutes: light),
    rem: Duration(minutes: rem),
    awake: Duration.zero,
    inBed: inBed == null ? null : Duration(minutes: inBed),
  );
}

List<SleepNight> prior(int n, {int hour = 23, int minute = 0}) => [
  for (var i = 1; i <= n; i++)
    night(
      start: DateTime(2026, 3, 10 - i, hour, minute),
      asleep: 450,
      deep: 90,
      rem: 99,
    ),
];

void main() {
  test('perfect night scores 100', () {
    // 450 asleep, deep 20% = 90, rem 22% = 99, efficiency 0.95 => inBed 474.
    final n = night(
      start: DateTime(2026, 3, 10, 23, 0),
      asleep: 450,
      deep: 90,
      rem: 99,
      inBed: 474,
    );
    final s = scoreSleep(
      n,
      priorNights: prior(7),
      sleepAvgHr: 50,
      restingHr: 54,
    )!;
    expect(s.value, 100);
    expect(s.contributors.length, 6);
    for (final c in s.contributors.values) {
      expect(c.score, 1.0);
      expect(c.rating, ContributorRating.good);
    }
  });

  test('no stages returns null', () {
    final n = night(
      start: DateTime(2026, 3, 10, 23),
      asleep: 450,
      deep: 0,
      rem: 0,
    );
    expect(scoreSleep(n), isNull);
  });

  test('6h12m night from the mockup', () {
    final n = night(
      start: DateTime(2026, 3, 10, 23, 48),
      asleep: 372,
      deep: 63,
      rem: 93,
      inBed: 403,
    );
    final s = scoreSleep(
      n,
      priorNights: prior(7),
      sleepAvgHr: 51,
      restingHr: 54,
    )!;
    expect(s.value, 85);
    expect(
      s.contributors[SleepContributor.duration]!.rating,
      ContributorRating.fair,
    );
    expect(
      s.contributors[SleepContributor.timing]!.rating,
      ContributorRating.good,
    );
    expect(s.contributors[SleepContributor.timing]!.score, closeTo(0.8, 1e-9));
  });

  test('missing HR and <5 prior nights rescales', () {
    final n = night(
      start: DateTime(2026, 3, 10, 23),
      asleep: 450,
      deep: 90,
      rem: 99,
      inBed: 474,
    );
    final s = scoreSleep(n, priorNights: prior(4))!;
    expect(s.contributors.keys.toSet(), {
      SleepContributor.duration,
      SleepContributor.deep,
      SleepContributor.rem,
      SleepContributor.efficiency,
    });
    expect(s.value, 100);
  });

  test('midnight wrap', () {
    final n = night(
      start: DateTime(2026, 3, 11, 0, 10),
      asleep: 450,
      deep: 90,
      rem: 99,
    );
    final s = scoreSleep(n, priorNights: prior(7, hour: 23, minute: 50))!;
    expect(s.contributors[SleepContributor.timing]!.score, 1.0);
  });
}
