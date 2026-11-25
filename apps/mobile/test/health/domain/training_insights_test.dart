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
    // Training on days 1,3,5,7,9 -> nights 2,4,6,8,10 follow training.
    final training = [
      for (final x in [1, 3, 5, 7, 9]) train(d(x)),
    ];
    final others = [12, 13, 14, 15, 16];

    test('+40 min after training', () {
      final r = sleepAfterTraining([
        for (final x in [2, 4, 6, 8, 10]) night(d(x), 460),
        for (final x in others) night(d(x), 420),
      ], training)!;
      expect(r.difference, const Duration(minutes: 40));
      expect(r.trainingNights, 5);
      expect(r.otherNightsCount, 5);
      expect(r.afterTraining, const Duration(minutes: 460));
    });

    test('fewer than 5 after-training nights is null', () {
      final nights = [
        for (final x in [2, 4, 6, 8]) night(d(x), 480),
        for (final x in others) night(d(x), 420),
      ];
      expect(sleepAfterTraining(nights, training), isNull);
    });

    test('fewer than 5 other nights is null', () {
      final nights = [
        for (final x in [2, 4, 6, 8, 10]) night(d(x), 480),
        for (final x in others.take(4)) night(d(x), 420),
      ];
      expect(sleepAfterTraining(nights, training), isNull);
    });

    test('25 minute difference is null', () {
      final nights = [
        for (final x in [2, 4, 6, 8, 10]) night(d(x), 445),
        for (final x in others) night(d(x), 420),
      ];
      expect(sleepAfterTraining(nights, training), isNull);
    });

    test('exactly 30 minute difference is kept', () {
      final nights = [
        for (final x in [2, 4, 6, 8, 10]) night(d(x), 450),
        for (final x in others) night(d(x), 420),
      ];
      expect(sleepAfterTraining(nights, training), isNotNull);
    });

    test('night after a no-workout day counts as other', () {
      final nights = [
        for (final x in [2, 4, 6, 8, 10]) night(d(x), 480),
        for (final x in [3, 5, 12, 13, 14]) night(d(x), 400),
      ];
      final r = sleepAfterTraining(nights, training)!;
      expect(r.trainingNights, 5);
      expect(r.otherNightsCount, 5);
      expect(r.difference, const Duration(minutes: 80));
    });

    test('pairs correctly across a DST change', () {
      // US spring forward 2026-03-08.
      final train7 = [
        for (final x in [7, 8, 9, 10, 11]) train(d(x)),
      ];
      final nights = [
        for (final x in [8, 9, 10, 11, 12]) night(d(x), 480),
        for (final x in [14, 15, 16, 17, 18]) night(d(x), 400),
      ];
      final r = sleepAfterTraining(nights, train7)!;
      expect(r.trainingNights, 5);
      expect(r.otherNightsCount, 5);
    });
  });

  group('restingHrAfterHardSessions', () {
    // 13 training days 1..13; sets 20..16 on days 1..5 (hard), rest lower.
    final training = [
      for (final x in [1, 2, 3, 4, 5]) train(d(x), 21 - x),
      for (final x in [6, 7, 8, 9, 10, 11, 12, 13]) train(d(x), 10),
    ];
    List<DayValue> series({double hard = 58, double other = 55}) => [
      for (final x in [2, 3, 4, 5, 6]) rhr(d(x), hard),
      for (final x in [7, 8, 9, 10, 11, 12, 13, 14]) rhr(d(x), other),
    ];

    test('+4 bpm after hard days', () {
      final r = restingHrAfterHardSessions(series(hard: 59), training)!;
      expect(r.hardDays, 5);
      expect(r.otherDaysCount, 8);
      expect(r.difference, closeTo(4, 1e-9));
    });

    test('fewer than 3 training days is null', () {
      expect(
        restingHrAfterHardSessions(series(), training.take(2).toList()),
        isNull,
      );
    });

    test('2.5 bpm is null', () {
      expect(restingHrAfterHardSessions(series(hard: 57.5), training), isNull);
    });

    test('fewer than 5 other days is null', () {
      final s = series()..removeRange(9, 13);
      expect(restingHrAfterHardSessions(s, training), isNull);
    });

    test('hard day without next-morning value is dropped', () {
      final s = series()..removeAt(0);
      expect(restingHrAfterHardSessions(s, training), isNull);
    });

    test('exactly 3.0 bpm is kept', () {
      expect(restingHrAfterHardSessions(series(), training), isNotNull);
    });

    test('5 hard mornings remain when a sixth has no value', () {
      final six = [
        for (final x in [1, 2, 3, 4, 5, 6]) train(d(x), 20),
        for (final x in [7, 8, 9, 10, 11, 12, 13, 14]) train(d(x), 5),
      ];
      // n=14 -> k=5, threshold 20, six hard days; the morning of day 7 has
      // no value.
      final s = [
        for (final x in [2, 3, 4, 5, 6]) rhr(d(x), 60),
        for (final x in [8, 9, 10, 11, 12, 13]) rhr(d(x), 55),
      ];
      final r = restingHrAfterHardSessions(s, six)!;
      expect(r.hardDays, 5);
    });

    test('ties at the cut are included', () {
      final tied = [
        for (final x in [1, 2, 3, 4, 5, 6]) train(d(x), 20),
        for (final x in [7, 8, 9, 10, 11, 12, 13, 14]) train(d(x), 5),
      ];
      // n=14 -> k=5, threshold 20, six hard days.
      final s = [
        for (final x in [2, 3, 4, 5, 6, 7]) rhr(d(x), 60),
        for (final x in [8, 9, 10, 11, 12, 13, 14, 15]) rhr(d(x), 55),
      ];
      final r = restingHrAfterHardSessions(s, tied)!;
      expect(r.hardDays, 6);
      expect(r.difference, closeTo(5, 1e-9));
    });
  });
}
