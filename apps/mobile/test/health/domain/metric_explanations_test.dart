import 'dart:math';

import 'package:beyondrep/features/health/domain/health_types.dart';
import 'package:beyondrep/features/health/domain/metric_explanations.dart';
import 'package:flutter_test/flutter_test.dart';

final today = DateTime(2026, 3, 10);

DateTime daysAgo(int n) => DateTime(today.year, today.month, today.day - n);

List<DayValue> series(int count, {double start = 50}) => [
  for (var i = 0; i < count; i++)
    (day: daysAgo(count - i), value: start + i.toDouble()),
];

void main() {
  test('every MetricKey has non-empty copy on both platforms', () {
    for (final platform in HealthPlatformKind.values) {
      for (final key in MetricKey.values) {
        final e = explanationFor(key, platform);
        expect(e.title, isNotEmpty, reason: '$key title');
        expect(e.summary, isNotEmpty, reason: '$key summary');
        expect(e.what, isNotEmpty, reason: '$key what');
        expect(e.tells, isNotEmpty, reason: '$key tells');
        expect(e.inBeyondRep, isNotEmpty, reason: '$key inBeyondRep');
      }
    }
  });

  test('lightSleep title is Core sleep on Apple Health, Light on Android', () {
    expect(
      explanationFor(
        MetricKey.lightSleep,
        HealthPlatformKind.appleHealth,
      ).title,
      'Core sleep',
    );
    expect(
      explanationFor(
        MetricKey.lightSleep,
        HealthPlatformKind.healthConnect,
      ).title,
      'Light sleep',
    );
  });

  test('no copy diagnoses or sends the user to a doctor', () {
    final banned = [
      'diagnos',
      'disease',
      'normal range',
      'should see a doctor',
    ];
    for (final platform in HealthPlatformKind.values) {
      for (final key in MetricKey.values) {
        final e = explanationFor(key, platform);
        final all =
            '${e.title} ${e.summary} ${e.what} ${e.tells} '
                    '${e.inBeyondRep}'
                .toLowerCase();
        for (final word in banned) {
          expect(all.contains(word), isFalse, reason: '$key says $word');
        }
      }
    }
  });

  test('the readiness key explains energy', () {
    final e = explanationFor(
      MetricKey.readiness,
      HealthPlatformKind.appleHealth,
    );
    expect(e.title, 'Energy');
    expect(e.summary, 'How much energy you have to train right now');
    expect(e.what, contains('your recent training load'));
    expect(e.tells, endsWith('the score can move more.'));
    expect(e.inBeyondRep, contains('Apple Watch'));
  });

  test('training load and other-app workouts copy', () {
    final load = explanationFor(
      MetricKey.trainingLoad,
      HealthPlatformKind.appleHealth,
    );
    expect(load.title, 'Training load');
    expect(load.summary, "How much you've trained lately compared with usual");
    expect(load.inBeyondRep, contains('14 days of workout history'));
    for (final (platform, name) in [
      (HealthPlatformKind.appleHealth, 'Apple Health'),
      (HealthPlatformKind.healthConnect, 'Health Connect'),
    ]) {
      final w = explanationFor(MetricKey.otherAppWorkouts, platform);
      expect(w.title, 'Workouts from other apps');
      expect(w.summary, 'Workouts other apps saved to $name');
      expect(w.what, contains('saved to $name, such as runs'));
      expect(w.what, isNot(contains('<platform>')));
      expect(w.tells, isNot(contains('<platform>')));
      expect(w.inBeyondRep, isNot(contains('<platform>')));
    }
  });

  test('hrv what mentions both Apple and Android', () {
    final what = explanationFor(
      MetricKey.hrv,
      HealthPlatformKind.appleHealth,
    ).what;
    expect(what, contains('Apple'));
    expect(what, contains('Android'));
  });

  test('usualFrom returns null with 13 days and a range with 14', () {
    expect(usualFrom(series(13), today), isNull);
    final usual = usualFrom(
      series(14),
      today,
      reading: (day: today, value: 58),
    )!;
    const mean = 56.5;
    final sd = sqrt((14 * 14 - 1) / 12);
    expect(usual.low, closeTo(mean - sd, 1e-9));
    expect(usual.high, closeTo(mean + sd, 1e-9));
    expect(usual.today, 58);
    expect(usual.dailyAverage, isFalse);
  });

  test('usualFrom keeps the range but drops a reading from another day', () {
    final usual = usualFrom(
      series(14),
      today,
      reading: (day: today.subtract(const Duration(days: 2)), value: 58),
    )!;
    expect(usual.today, isNull);
    expect(usual.low, lessThan(usual.high));
  });

  test("usualFrom ignores today's own value in the baseline", () {
    final base = series(14);
    final withToday = [...base, (day: today, value: 500.0)];
    final a = usualFrom(base, today)!;
    final b = usualFrom(withToday, today)!;
    expect(b.low, closeTo(a.low, 1e-9));
    expect(b.high, closeTo(a.high, 1e-9));
  });

  test('dailyAverageFrom gives the mean and dailyAverage true', () {
    final avg = dailyAverageFrom(series(14), today)!;
    expect(avg.low, closeTo(56.5, 1e-9));
    expect(avg.high, closeTo(56.5, 1e-9));
    expect(avg.dailyAverage, isTrue);
    expect(avg.today, isNull);
    expect(dailyAverageFrom(series(13), today), isNull);
  });
}
