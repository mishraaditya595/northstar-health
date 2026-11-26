import '../../workouts/domain/workout_models.dart';
import 'program_models.dart';
import 'program_schedule.dart';

/// Where one day of the current program week stands. Computed, never stored.
enum ProgramDayStatus { rest, unavailable, done, today, missed, upcoming }

typedef ProgramWeekRow = ({
  DateTime date,
  int dayIndex,
  ProgramDayRecord day,
  ProgramDayStatus status,
});

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// The most recent date on or before [localToday] whose ISO weekday is
/// [firstDayWeekday], at local midnight.
DateTime programWeekStart(DateTime localToday, int firstDayWeekday) {
  final today = _dateOnly(localToday);
  final back = (today.weekday - firstDayWeekday) % 7;
  return DateTime(today.year, today.month, today.day - back);
}

/// The seven days of the current program week with their status.
///
/// A day is `done` when a completed session carries this program's UUID and
/// that day's date (sessions from My Plans, templates or Quick workout never
/// do). Missed days run from the later of the week start and the activation
/// date up to yesterday. Done wins over unavailable, so a finished day stays
/// done if its plan is archived later. Pass only non-deleted sessions.
List<ProgramWeekRow> programWeekStatus({
  required TrainingProgramRecord program,
  required DateTime localToday,
  required Iterable<WorkoutSessionRecord> sessions,
  required Set<String> availablePlanUuids,
}) {
  final today = _dateOnly(localToday);
  final start = programWeekStart(today, program.firstDayWeekday);
  final doneKeys = <String>{
    for (final s in sessions)
      if (s.status == WorkoutStatus.completed &&
          s.programUuid == program.uuid &&
          s.programDayLocalDate != null)
        s.programDayLocalDate!,
  };
  final activated = program.activatedLocalDate;
  final days = [...program.days]
    ..sort((a, b) => a.dayIndex.compareTo(b.dayIndex));
  return [
    for (final day in days)
      () {
        final date = DateTime(
          start.year,
          start.month,
          start.day + day.dayIndex,
        );
        final key = localDateKey(date);
        final ProgramDayStatus status;
        if (day.planUuid == null) {
          status = ProgramDayStatus.rest;
        } else if (doneKeys.contains(key)) {
          status = ProgramDayStatus.done;
        } else if (!availablePlanUuids.contains(day.planUuid)) {
          status = ProgramDayStatus.unavailable;
        } else if (date == today) {
          status = ProgramDayStatus.today;
        } else if (date.isBefore(today) &&
            (activated == null || key.compareTo(activated) >= 0)) {
          status = ProgramDayStatus.missed;
        } else {
          status = ProgramDayStatus.upcoming;
        }
        return (date: date, dayIndex: day.dayIndex, day: day, status: status);
      }(),
  ];
}

/// The most recent missed day of the current week, or null.
({DateTime date, ProgramDayRecord day})? latestMissed({
  required TrainingProgramRecord program,
  required DateTime localToday,
  required Iterable<WorkoutSessionRecord> sessions,
  required Set<String> availablePlanUuids,
}) {
  final missed = programWeekStatus(
    program: program,
    localToday: localToday,
    sessions: sessions,
    availablePlanUuids: availablePlanUuids,
  ).where((row) => row.status == ProgramDayStatus.missed);
  if (missed.isEmpty) return null;
  final last = missed.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
  return (date: last.date, day: last.day);
}

/// The next day after today with an available plan, looking up to seven days
/// ahead (so it can wrap into next week), or null.
({DateTime date, ProgramDayRecord day})? nextTraining({
  required TrainingProgramRecord program,
  required DateTime localToday,
  required Set<String> availablePlanUuids,
}) {
  final today = _dateOnly(localToday);
  for (var i = 1; i <= 7; i++) {
    final date = DateTime(today.year, today.month, today.day + i);
    final day = dayFor(program, date);
    if (day.planUuid != null && availablePlanUuids.contains(day.planUuid)) {
      return (date: date, day: day);
    }
  }
  return null;
}
