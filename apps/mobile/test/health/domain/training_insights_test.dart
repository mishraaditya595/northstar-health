import 'package:beyondrep/features/health/domain/health_types.dart';
import 'package:beyondrep/features/health/domain/sleep_nights.dart';
import 'package:beyondrep/features/health/domain/training_insights.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime d(int day, [int month = 3]) => DateTime(2026, month, day);

SleepNight night(DateTime date, int asleepMinutes) => SleepNight(
  date: date,
  start: date.subtract(const Duration(hours: 8)),
  end: date,
  source: 'test',
  segments: const [],
  asleep: Duration(minutes: asleepMinutes),
  deep: Duration.zero,
  light: Duration(minutes: asleepMinutes),
  rem: Duration.zero,
  awake: Duration.zero,
  inBed: null,
);

TrainingDay train(DateTime day, [int sets = 10]) =>
    (day: day, workingSets: sets);

DayValue rhr(DateTime day, double v) => (day: day, value: v);

void main() {
  group('sleepAfterTraining', () {
    // Training on days 1,3,5,7 -> nights 2,4,6,8 follow training.
    final training = [
      for (final x in [1, 3, 5, 7]) train(d(x)),
    ];

    test('+40 min after training', () {
      final r = sleepAfterTraining([
        for (final x in [2, 4, 6, 8]) night(d(x), 460),
        for (final x in [10, 11, 12, 13, 14]) night(d(x), 420),
      ], training)!;
      expect(r.difference, const Duration(minutes: 40));
      expect(r.trainingNights, 4);
      expect(r.otherNightsCount, 5);
      expect(r.afterTraining, const Duration(minutes: 460));
    });

    test('fewer than 3 after-training nights is null', () {
      final nights = [
        night(d(2), 480),
        night(d(4), 480),
        for (final x in [10, 11, 12, 13]) night(d(x), 420),
      ];
      expect(sleepAfterTraining(nights, training), isNull);
    });

    test('15 minute difference is null', () {
      final nights = [
        for (final x in [2, 4, 6, 8]) night(d(x), 435),
        for (final x in [10, 11, 12]) night(d(x), 420),
      ];
      expect(sleepAfterTraining(nights, training), isNull);
    });

    test('night after a no-workout day counts as other', () {
      final nights = [
        for (final x in [2, 4, 6]) night(d(x), 480),
        for (final x in [3, 5, 9]) night(d(x), 400),
      ];
      final r = sleepAfterTraining(nights, training)!;
      expect(r.trainingNights, 3);
      expect(r.otherNightsCount, 3);
      expect(r.difference, const Duration(minutes: 80));
    });

    test('pairs correctly across a DST change', () {
      // US spring forward 2026-03-08.
      final train7 = [train(d(7)), train(d(8)), train(d(9))];
      final nights = [
        night(d(8), 480),
        night(d(9), 480),
        night(d(10), 480),
        night(d(12), 400),
        night(d(13), 400),
        night(d(14), 400),
      ];
      final r = sleepAfterTraining(nights, train7)!;
      expect(r.trainingNights, 3);
      expect(r.otherNightsCount, 3);
    });
  });

  group('restingHrAfterHardSessions', () {
    // 9 training days 1..9; sets 20,19,18 on days 1,2,3 (hard), rest lower.
    final training = [
      train(d(1), 20),
      train(d(2), 19),
      train(d(3), 18),
      for (final x in [4, 5, 6, 7, 8, 9]) train(d(x), 10),
    ];
    List<DayValue> series({double hard = 58, double other = 55}) => [
      rhr(d(2), hard),
      rhr(d(3), hard),
      rhr(d(4), hard),
      for (final x in [5, 6, 7, 8, 9, 10]) rhr(d(x), other),
    ];

    test('+3 bpm after hard days', () {
      final r = restingHrAfterHardSessions(series(), training)!;
      expect(r.hardDays, 3);
      expect(r.otherDaysCount, 6);
      expect(r.difference, closeTo(3, 1e-9));
    });

    test('fewer than 3 training days is null', () {
      expect(
        restingHrAfterHardSessions(series(), training.take(2).toList()),
        isNull,
      );
    });

    test('1.5 bpm is null', () {
      expect(restingHrAfterHardSessions(series(hard: 56.5), training), isNull);
    });

    test('hard day without next-morning value is dropped', () {
      final s = series()..removeAt(0);
      expect(restingHrAfterHardSessions(s, training), isNull);
    });

    test('ties at the cut are included', () {
      final tied = [
        train(d(1), 20),
        train(d(2), 20),
        train(d(3), 20),
        train(d(4), 20),
        for (final x in [5, 6, 7, 8]) train(d(x), 5),
      ];
      // n=8 -> k=3, threshold 20, four hard days.
      final s = [
        for (final x in [2, 3, 4, 5]) rhr(d(x), 60),
        for (final x in [6, 7, 8, 9]) rhr(d(x), 55),
      ];
      final r = restingHrAfterHardSessions(s, tied)!;
      expect(r.hardDays, 4);
      expect(r.difference, closeTo(5, 1e-9));
    });
  });
}
