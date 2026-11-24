import 'package:beyondrep/features/health/data/sleep_merge.dart';
import 'package:flutter_test/flutter_test.dart';

({DateTime from, DateTime to}) _seg(DateTime from, DateTime to) =>
    (from: from, to: to);

void main() {
  test('merges overlapping segments into one span', () {
    final minutes = mergedSleepMinutes([
      _seg(DateTime.utc(2026, 11, 23, 23), DateTime.utc(2026, 11, 24, 3)),
      _seg(DateTime.utc(2026, 11, 24, 2), DateTime.utc(2026, 11, 24, 6, 30)),
    ]);
    expect(minutes, 450);
  });

  test('counts identical duplicate segments once', () {
    final a = _seg(
      DateTime.utc(2026, 11, 23, 23),
      DateTime.utc(2026, 11, 24, 3),
    );
    expect(mergedSleepMinutes([a, a]), 240);
  });

  test('empty input is zero', () {
    expect(mergedSleepMinutes(const []), 0);
  });

  test('sums separate segments and merges adjacent ones', () {
    final minutes = mergedSleepMinutes([
      _seg(DateTime.utc(2026, 11, 24, 4), DateTime.utc(2026, 11, 24, 5)),
      _seg(DateTime.utc(2026, 11, 24, 1), DateTime.utc(2026, 11, 24, 2)),
      _seg(DateTime.utc(2026, 11, 24, 2), DateTime.utc(2026, 11, 24, 3)),
    ]);
    expect(minutes, 180);
  });

  test(
    'segment crossing midnight on a DST-change date uses real elapsed time',
    () {
      // 2026-03-29 is the EU spring-forward date; UTC instants keep the
      // arithmetic independent of the test machine's zone.
      final minutes = mergedSleepMinutes([
        _seg(
          DateTime.utc(2026, 3, 28, 22, 30),
          DateTime.utc(2026, 3, 29, 5, 15),
        ),
      ]);
      expect(minutes, 405);
    },
  );
}
