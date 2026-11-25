import '../../catalog/domain/catalog_models.dart';
import '../../workouts/domain/workout_library_models.dart';
import 'program_models.dart';

/// Local-only program storage. Programs never reach the cloud backup.
abstract interface class ProgramRepository {
  /// Imports [program] in one transaction: materializes exercises, creates
  /// one plan per distinct template, the program and its seven days, and
  /// optionally makes it active. [requestUuid] becomes the program UUID, and a
  /// repeated request returns the existing program. Any failure leaves
  /// nothing behind.
  TrainingProgramRecord importProgram({
    required String requestUuid,
    required CatalogProgram program,
    required Map<String, List<TemplateRowInput>> templateRows,
    required Map<String, String> templateNames,
    required int release,
    required int firstDayWeekday,
    required bool makeActive,
    required DateTime localToday,
  });

  /// Activating deactivates every other program in the same transaction.
  void setActive(String programUuid, bool active, DateTime localToday);

  void setFirstWeekday(String programUuid, int weekday);

  /// A null [planUuid] makes the day a rest day. The plan must belong to the
  /// program, otherwise [ArgumentError].
  void setDayPlan(String programUuid, int dayIndex, String? planUuid);

  /// The program's non-archived plans (the ones [setDayPlan] accepts), in
  /// import order, whether or not a day uses them.
  List<WorkoutPlanRecord> programPlans(String programUuid);

  /// Archives the program and its plans and deactivates it. Sessions are
  /// never touched.
  void archiveProgram(String programUuid, int nowMs);

  TrainingProgramRecord? getProgram(String programUuid);

  /// Non-archived programs, most recently updated first.
  List<TrainingProgramRecord> listPrograms();

  /// The same list as a stream that re-emits after every change.
  Stream<List<TrainingProgramRecord>> watchPrograms();

  TrainingProgramRecord? activeProgram();
}
