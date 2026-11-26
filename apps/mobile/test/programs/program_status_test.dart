import 'package:flutter_test/flutter_test.dart';

import 'package:beyondrep/features/programs/domain/program_models.dart';
import 'package:beyondrep/features/programs/domain/program_schedule.dart';
import 'package:beyondrep/features/programs/domain/program_status.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';

// 2026-11-23 is a Monday.
TrainingProgramRecord program({
  int firstDayWeekday = 1,
  String? activated,
  // Plan per day index; null is a rest day.
  List<String?> plans = const ['a', null, 'b', null, 'c', null, null],
}) => TrainingProgramRecord(
  uuid: 'prog',
  name: 'P',
  description: '',
  sourceId: 'prog.x',
  sourceRelease: 4,
  firstDayWeekday: firstDayWeekday,
  isActive: true,
  activatedLocalDate: activated,
  updatedAtMs: 0,
  days: [
    for (var i = 0; i < 7; i++)
      ProgramDayRecord(uuid: 'd$i', dayIndex: i, planUuid: plans[i]),
  ],
);

WorkoutSessionRecord session(
  String? programUuid,
  String? date, {
  WorkoutStatus status = WorkoutStatus.completed,
}) => WorkoutSessionRecord(
  uuid: 's-$programUuid-$date-${status.name}',
  name: 'S',
  status: status,
  startedAtUtc: DateTime.utc(2026, 11, 23),
  originalOffsetMinutes: 0,
  revision: 1,
  programUuid: programUuid,
  programDayLocalDate: date,
);

const all = {'a', 'b', 'c'};

List<ProgramDayStatus> statuses(
  TrainingProgramRecord p,
  DateTime today, {
  List<WorkoutSessionRecord> sessions = const [],
  Set<String> available = all,
}) => [
  for (final row in programWeekStatus(
    program: p,
    localToday: today,
    sessions: sessions,
    availablePlanUuids: available,
  ))
    row.status,
];

void main() {
  const rest = ProgramDayStatus.rest;
  const done = ProgramDayStatus.done;
  const today = ProgramDayStatus.today;
  const missed = ProgramDayStatus.missed;
  const upcoming = ProgramDayStatus.upcoming;

  group('programWeekStart', () {
    test('is the most recent firstDayWeekday on or before today', () {
      for (final today in [DateTime(2026, 11, 25), DateTime(2026, 11, 29)]) {
        for (var first = 1; first <= 7; first++) {
          final start = programWeekStart(today, first);
          expect(start.weekday, first);
          expect(start.isAfter(today), isFalse);
          expect(today.difference(start).inDays, lessThan(7));
        }
      }
    });

    test('is today when today is the first day, across a month end', () {
      expect(programWeekStart(DateTime(2026, 12, 1), 2), DateTime(2026, 12, 1));
      expect(programWeekStart(DateTime(2026, 12, 2), 2), DateTime(2026, 12, 1));
      expect(
        programWeekStart(DateTime(2026, 12, 1), 3),
        DateTime(2026, 11, 25),
      );
    });

    test('ignores the time of day', () {
      expect(
        programWeekStart(DateTime(2026, 11, 25, 23, 59), 1),
        DateTime(2026, 11, 23),
      );
    });
  });

  group('programWeekStatus', () {
    test('Wednesday of a Monday week: past days missed, later upcoming', () {
      expect(statuses(program(), DateTime(2026, 11, 25)), [
        missed, // Mon a
        rest,
        today, // Wed b
        rest,
        upcoming, // Fri c
        rest,
        rest,
      ]);
    });

    test('every first weekday against two dates keeps the week aligned', () {
      for (final date in [DateTime(2026, 11, 25), DateTime(2026, 11, 29)]) {
        for (var first = 1; first <= 7; first++) {
          final rows = programWeekStatus(
            program: program(firstDayWeekday: first),
            localToday: date,
            sessions: const [],
            availablePlanUuids: all,
          );
          expect(rows, hasLength(7));
          expect(rows.first.date.weekday, first);
          expect([for (final r in rows) r.dayIndex], [0, 1, 2, 3, 4, 5, 6]);
          // Exactly one row is today, and every row before it is in the past.
          final todayRows = rows
              .where((r) => r.date == DateTime(date.year, date.month, date.day))
              .toList();
          expect(todayRows, hasLength(1));
          for (final r in rows) {
            if (r.status == missed) {
              expect(r.date.isBefore(todayRows.single.date), isTrue);
            }
            if (r.status == upcoming) {
              expect(r.date.isAfter(todayRows.single.date), isTrue);
            }
          }
        }
      }
    });

    test('activated mid-week: earlier days are upcoming, not missed', () {
      expect(
        statuses(
          program(activated: '2026-11-24'), // Tuesday
          DateTime(2026, 11, 26),
        ),
        [upcoming, rest, missed, rest, upcoming, rest, rest],
      );
    });

    test('activated today: nothing is missed', () {
      final s = statuses(
        program(activated: '2026-11-25'),
        DateTime(2026, 11, 25),
      );
      expect(s.contains(missed), isFalse);
      expect(s[0], upcoming);
      expect(s[2], today);
    });

    test('a matching finished session marks the day done', () {
      final s = statuses(
        program(),
        DateTime(2026, 11, 25),
        sessions: [session('prog', '2026-11-23')],
      );
      expect(s[0], done);
      expect(s[2], today);
    });

    test('today done stays done and is not today', () {
      final s = statuses(
        program(),
        DateTime(2026, 11, 25),
        sessions: [session('prog', '2026-11-25')],
      );
      expect(s[2], done);
    });

    test('no program, another program or a plain session is not done', () {
      for (final other in [
        session(null, null),
        session(null, '2026-11-23'),
        session('other', '2026-11-23'),
        session('prog', null),
        session('prog', '2026-11-24'), // a rest day date
      ]) {
        final s = statuses(
          program(),
          DateTime(2026, 11, 25),
          sessions: [other],
        );
        expect(s[0], missed, reason: other.uuid);
      }
    });

    test('discarded and in-progress sessions are not done', () {
      for (final status in [
        WorkoutStatus.discarded,
        WorkoutStatus.inProgress,
        WorkoutStatus.paused,
        WorkoutStatus.unknown,
      ]) {
        final s = statuses(
          program(),
          DateTime(2026, 11, 25),
          sessions: [session('prog', '2026-11-23', status: status)],
        );
        expect(s[0], missed, reason: status.name);
      }
    });

    test('a session dated yesterday marks yesterday done', () {
      final s = statuses(
        program(plans: const ['a', 'b', null, null, null, null, null]),
        DateTime(2026, 11, 24),
        sessions: [session('prog', '2026-11-23')],
      );
      expect(s[0], done);
      expect(s[1], today);
    });

    test('a rest day is never missed', () {
      final s = statuses(program(), DateTime(2026, 11, 29));
      expect(s[1], rest);
      expect(s[3], rest);
      expect(s[5], rest);
    });

    test('a missing or archived plan is unavailable, never missed', () {
      final s = statuses(
        program(),
        DateTime(2026, 11, 25),
        available: {'b', 'c'},
      );
      expect(s[0], ProgramDayStatus.unavailable);
      expect(s[2], today);
    });

    test('a done day stays done even if its plan is gone now', () {
      final s = statuses(
        program(),
        DateTime(2026, 11, 25),
        sessions: [session('prog', '2026-11-23')],
        available: {'b', 'c'},
      );
      expect(s[0], done);
    });

    test('a new week clears the misses', () {
      final s = statuses(program(), DateTime(2026, 11, 30)); // next Monday
      expect(s.contains(missed), isFalse);
      expect(s[0], today);
    });

    test('sessions from the previous week do not count for this week', () {
      final s = statuses(
        program(),
        DateTime(2026, 11, 30),
        sessions: [session('prog', '2026-11-23')],
      );
      expect(s[0], today);
    });

    test('a week that starts on Sunday crosses the month boundary', () {
      // Sunday 2026-11-29 first; today Tuesday 2026-12-01.
      final rows = programWeekStatus(
        program: program(
          firstDayWeekday: 7,
          plans: ['a', 'b', 'c', null, null, null, null],
        ),
        localToday: DateTime(2026, 12, 1),
        sessions: const [],
        availablePlanUuids: all,
      );
      expect(rows.first.date, DateTime(2026, 11, 29));
      expect(rows.last.date, DateTime(2026, 12, 5));
      expect([for (final r in rows) r.status].take(3), [missed, missed, today]);
    });
  });

  group('latestMissed', () {
    test('is the most recent missed day', () {
      final m = latestMissed(
        program: program(),
        localToday: DateTime(2026, 11, 29),
        sessions: const [],
        availablePlanUuids: all,
      );
      expect(m!.date, DateTime(2026, 11, 27)); // Friday c
      expect(m.day.planUuid, 'c');
    });

    test('skips done days and returns null with nothing missed', () {
      final m = latestMissed(
        program: program(),
        localToday: DateTime(2026, 11, 29),
        sessions: [session('prog', '2026-11-27')],
        availablePlanUuids: all,
      );
      expect(m!.day.planUuid, 'b');
      expect(
        latestMissed(
          program: program(),
          localToday: DateTime(2026, 11, 23),
          sessions: const [],
          availablePlanUuids: all,
        ),
        isNull,
      );
    });
  });

  group('nextTraining', () {
    test('skips rest days', () {
      final n = nextTraining(
        program: program(),
        localToday: DateTime(2026, 11, 25),
        availablePlanUuids: all,
      );
      expect(n!.date, DateTime(2026, 11, 27));
      expect(n.day.planUuid, 'c');
    });

    test('wraps into next week', () {
      final n = nextTraining(
        program: program(),
        localToday: DateTime(2026, 11, 27),
        availablePlanUuids: all,
      );
      expect(n!.date, DateTime(2026, 11, 30));
      expect(n.day.planUuid, 'a');
    });

    test('a single training day finds itself next week', () {
      final n = nextTraining(
        program: program(
          plans: const ['a', null, null, null, null, null, null],
        ),
        localToday: DateTime(2026, 11, 23),
        availablePlanUuids: all,
      );
      expect(n!.date, DateTime(2026, 11, 30));
    });

    test('is null when no day has an available plan', () {
      expect(
        nextTraining(
          program: program(),
          localToday: DateTime(2026, 11, 25),
          availablePlanUuids: const {},
        ),
        isNull,
      );
    });
  });
}
