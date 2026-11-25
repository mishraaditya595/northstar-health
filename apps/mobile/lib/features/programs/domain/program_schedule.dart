import 'program_models.dart';

/// Program day (0 to 6) for [localDate]: `(isoWeekday - firstDayWeekday) mod 7`.
int programDayIndex(DateTime localDate, int firstDayWeekday) =>
    (localDate.weekday - firstDayWeekday) % 7;

/// `yyyy-MM-dd` for the local calendar date.
String localDateKey(DateTime localDate) {
  final y = localDate.year.toString().padLeft(4, '0');
  final m = localDate.month.toString().padLeft(2, '0');
  final d = localDate.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

ProgramDayRecord dayFor(TrainingProgramRecord program, DateTime localDate) {
  final index = programDayIndex(localDate, program.firstDayWeekday);
  return program.days.firstWhere((day) => day.dayIndex == index);
}

/// The seven days in program order, each with the ISO weekday it falls on.
List<({int weekday, ProgramDayRecord day})> calendarWeek(
  TrainingProgramRecord program,
) {
  final days = [...program.days]
    ..sort((a, b) => a.dayIndex.compareTo(b.dayIndex));
  return [
    for (final day in days)
      (weekday: (program.firstDayWeekday - 1 + day.dayIndex) % 7 + 1, day: day),
  ];
}
