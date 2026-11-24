import 'package:beyondrep/features/health/domain/health_types.dart';
import 'package:beyondrep/features/health/domain/series_stats.dart';
import 'package:flutter_test/flutter_test.dart';

DayValue _d(int day, double value) =>
    (day: DateTime(2026, 11, day), value: value);

void main() {
  group('normalBand', () {
    test('is the mean plus and minus one standard deviation', () {
      final band = normalBand([
        for (var i = 0; i < 30; i++) i.isEven ? 53 : 57,
      ]);
      expect(band!.low, closeTo(53, 1e-9));
      expect(band.high, closeTo(57, 1e-9));
    });

    test('needs 7 values', () {
      expect(normalBand([50, 51, 52, 53, 54, 55]), isNull);
      expect(normalBand([50, 51, 52, 53, 54, 55, 56]), isNotNull);
    });
  });

  group('rollingMean', () {
    test('averages the values present in the trailing window', () {
      expect(rollingMean([2, null, 4, 6], 2), [2, 2, 4, 5]);
    });

    test('is null where the window has no value', () {
      expect(rollingMean([null, null, 3], 2), [null, null, 3]);
    });
  });

  group('weeklyChange', () {
    test('is the least-squares slope per day times 7', () {
      final points = [_d(1, 80), _d(3, 79.8), _d(5, 79.6), _d(8, 79.3)];
      expect(weeklyChange(points), closeTo(-0.7, 1e-9));
    });

    test('needs 4 points with data', () {
      expect(weeklyChange([_d(1, 80), _d(2, 79), _d(3, 78)]), isNull);
    });

    test('counts calendar days across a DST change', () {
      // 29 Mar 2026 is 23 h long in the EU; local midnights stay one day.
      final points = [
        (day: DateTime(2026, 3, 28), value: 70.0),
        (day: DateTime(2026, 3, 29), value: 71.0),
        (day: DateTime(2026, 3, 30), value: 72.0),
        (day: DateTime(2026, 3, 31), value: 73.0),
      ];
      expect(weeklyChange(points), closeTo(7, 1e-9));
    });
  });

  group('earlierReading', () {
    test('is the latest reading at least the given days before the last', () {
      final daily = [_d(1, 43), _d(5, 43.3), _d(20, 43.8), _d(24, 44.1)];
      expect(earlierReading(daily, 19), _d(5, 43.3));
    });

    test('is null when nothing is old enough', () {
      expect(earlierReading([_d(20, 43.8), _d(24, 44.1)], 30), isNull);
    });
  });
}
