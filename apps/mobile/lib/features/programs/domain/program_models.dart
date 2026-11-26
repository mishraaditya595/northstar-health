/// One of the seven days of a program. A null [planUuid] is a rest day.
class ProgramDayRecord {
  const ProgramDayRecord({
    required this.uuid,
    required this.dayIndex,
    this.planUuid,
  });

  final String uuid;
  final int dayIndex;
  final String? planUuid;
}

/// A program the user added. Local only, never synced.
class TrainingProgramRecord {
  const TrainingProgramRecord({
    required this.uuid,
    required this.name,
    required this.description,
    required this.sourceId,
    required this.sourceRelease,
    required this.firstDayWeekday,
    required this.isActive,
    required this.updatedAtMs,
    required this.days,
    this.activatedLocalDate,
    this.archivedAtMs,
  });

  final String uuid;
  final String name;
  final String description;
  final String sourceId;
  final int sourceRelease;

  /// ISO weekday of day 1, Monday = 1.
  final int firstDayWeekday;
  final bool isActive;

  /// `yyyy-MM-dd`, set each time the program becomes active.
  final String? activatedLocalDate;
  final int updatedAtMs;
  final int? archivedAtMs;

  /// Seven days ordered by `dayIndex`.
  final List<ProgramDayRecord> days;
}
