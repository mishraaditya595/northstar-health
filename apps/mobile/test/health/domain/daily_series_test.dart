import 'package:beyondrep/features/health/domain/daily_series.dart';
import 'package:beyondrep/features/health/domain/health_types.dart';
import 'package:flutter_test/flutter_test.dart';

HealthSample s(DateTime to, double v, {DateTime? from}) =>
    (from: from ?? to, to: to, value: v, source: 'synthetic');

void main() {
  final d23 = DateTime(2026, 11, 23);
  final d24 = DateTime(2026, 11, 24);

  test('reduceDaily latest keeps the newest sample per day', () {
    final out = reduceDaily([
      s(DateTime(2026, 11, 24, 20), 3),
      s(DateTime(2026, 11, 23, 8), 1),
      s(DateTime(2026, 11, 23, 9), 2),
      s(DateTime(2026, 11, 24, 7), 9),
    ], DailyReduction.latest);
    expect(out, [(day: d23, value: 2.0), (day: d24, value: 3.0)]);
  });

  test('reduceDaily mean averages', () {
    final out = reduceDaily([
      s(DateTime(2026, 11, 23, 8), 1),
      s(DateTime(2026, 11, 23, 9), 4),
    ], DailyReduction.mean);
    expect(out, [(day: d23, value: 2.5)]);
  });

  test('reduceDaily sum adds', () {
    final out = reduceDaily([
      s(DateTime(2026, 11, 23, 8), 1),
      s(DateTime(2026, 11, 23, 9), 4),
    ], DailyReduction.sum);
    expect(out, [(day: d23, value: 5.0)]);
  });

  test('hourlyToDaily in Asia/Calcutta', () {
    final hourly = [
      for (final day in [23, 24])
        for (var h = 0; h < 24; h++)
          s(
            DateTime(2026, 11, day, h + 1),
            100,
            from: DateTime(2026, 11, day, h),
          ),
    ];
    expect(hourlyToDaily(hourly), [
      (day: d23, value: 2400.0),
      (day: d24, value: 2400.0),
    ]);
  });

  test('hourlyToDaily across a 25 h DST day', () {
    final day = DateTime(2026, 10, 25);
    final hourly = [
      for (var i = 0; i < 25; i++)
        s(
          DateTime(2026, 10, 25, 1),
          10,
          from: DateTime(2026, 10, 25, i < 24 ? i : 1, i < 24 ? 0 : 30),
        ),
    ];
    expect(hourlyToDaily(hourly), [(day: day, value: 250.0)]);
  });

  test('hourlyToDaily across a 23 h DST day', () {
    final day = DateTime(2026, 3, 29);
    final hourly = [
      for (var i = 0; i < 23; i++)
        s(DateTime(2026, 3, 29, 1), 10, from: DateTime(2026, 3, 29, i)),
    ];
    expect(hourlyToDaily(hourly), [(day: day, value: 230.0)]);
  });

  group('summarizePeriod', () {
    final last = DateTime(2026, 11, 24);
    List<DayValue> series(int count, {int skipEvery = 0}) => [
      for (var i = count - 1; i >= 0; i--)
        if (skipEvery == 0 || i % skipEvery != 0)
          (day: DateTime(last.year, last.month, last.day - i), value: 10.0),
    ];

    test('averages the current window and compares the previous', () {
      final r = summarizePeriod(series(14), lastDay: last, days: 7);
      expect(r.average, 10);
      expect(r.daysWithData, 7);
      expect(r.previousAverage, 10);
    });

    test('average is null with no data', () {
      final r = summarizePeriod(const [], lastDay: last, days: 7);
      expect(r.average, isNull);
      expect(r.daysWithData, 0);
      expect(r.previousAverage, isNull);
    });

    test('hides previous when outside readable window', () {
      final data = series(30);
      final readable = DateTime(last.year, last.month, last.day - 39);
      final hidden = summarizePeriod(
        data,
        lastDay: last,
        days: 30,
        readableFrom: readable,
      );
      expect(hidden.previousAverage, isNull);
      final shown = summarizePeriod(
        data +
            [
              for (var i = 30; i < 60; i++)
                (
                  day: DateTime(last.year, last.month, last.day - i),
                  value: 20.0,
                ),
            ],
        lastDay: last,
        days: 30,
      );
      expect(shown.previousAverage, 20);
    });

    test('shows previous with exactly days ~/ 2 days of data', () {
      final data = [
        ...series(7),
        (day: DateTime(2026, 11, 11), value: 5.0),
        (day: DateTime(2026, 11, 12), value: 5.0),
        (day: DateTime(2026, 11, 13), value: 5.0),
      ];
      final r = summarizePeriod(data, lastDay: last, days: 7);
      expect(r.previousAverage, 5);
    });

    test('hides previous when previous window is sparse', () {
      final data = [
        ...series(7),
        (day: DateTime(2026, 11, 11), value: 5.0),
        (day: DateTime(2026, 11, 12), value: 5.0),
      ];
      final r = summarizePeriod(data, lastDay: last, days: 7);
      expect(r.average, 10);
      expect(r.previousAverage, isNull);
    });
  });
}
