import 'package:objectbox/objectbox.dart';

/// Internal ObjectBox numeric IDs differ from portable, indexed UUIDs.
/// Never regenerate the committed model UIDs on subsequent migrations.
@Entity()
class ExerciseDefinitionEntity {
  @Id()
  int id = 0;
  @Unique()
  String uuid;
  String name;
  String muscleGroup;
  String equipment;
  String movementCategory;
  String inputMode;
  bool isBuiltIn;
  int catalogVersion;
  int createdAtMs;
  int updatedAtMs;
  int? archivedAtMs;

  ExerciseDefinitionEntity({
    this.id = 0,
    required this.uuid,
    required this.name,
    this.muscleGroup = '',
    this.equipment = '',
    this.movementCategory = '',
    this.inputMode = 'reps_load',
    this.isBuiltIn = false,
    this.catalogVersion = 1,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.archivedAtMs,
  });
}

@Entity()
class WorkoutPlanEntity {
  @Id()
  int id = 0;
  @Unique()
  String uuid;
  String name;
  String description;
  int createdAtMs;
  int updatedAtMs;
  int? archivedAtMs;

  WorkoutPlanEntity({
    this.id = 0,
    required this.uuid,
    required this.name,
    this.description = '',
    required this.createdAtMs,
    required this.updatedAtMs,
    this.archivedAtMs,
  });
}

@Entity()
class PlanExerciseEntity {
  @Id()
  int id = 0;
  @Unique()
  String uuid;
  @Index()
  String planUuid;
  String exerciseUuid;
  int position;
  int targetSets;
  int? targetRepsMin;
  int? targetRepsMax;
  int? restSeconds;
  String notes;

  PlanExerciseEntity({
    this.id = 0,
    required this.uuid,
    required this.planUuid,
    required this.exerciseUuid,
    required this.position,
    this.targetSets = 3,
    this.targetRepsMin,
    this.targetRepsMax,
    this.restSeconds,
    this.notes = '',
  });
}

@Entity()
class WorkoutSessionEntity {
  @Id()
  int id = 0;
  @Unique()
  String uuid;
  String name;
  String? planUuid;
  @Index()
  String status;
  String origin;
  int revision;
  int startedAtMs;
  int? completedAtMs;
  int originalOffsetMinutes;
  int updatedAtMs;
  int? deletedAtMs;

  WorkoutSessionEntity({
    this.id = 0,
    required this.uuid,
    required this.name,
    this.planUuid,
    this.status = 'inProgress',
    this.origin = 'northstar_phone',
    this.revision = 1,
    required this.startedAtMs,
    this.completedAtMs,
    required this.originalOffsetMinutes,
    required this.updatedAtMs,
    this.deletedAtMs,
  });
}

@Entity()
class WorkoutExerciseEntity {
  @Id()
  int id = 0;
  @Unique()
  String uuid;
  @Index()
  String sessionUuid;
  String? definitionUuid;
  String nameSnapshot;
  String muscleSnapshot;
  String equipmentSnapshot;
  int position;

  WorkoutExerciseEntity({
    this.id = 0,
    required this.uuid,
    required this.sessionUuid,
    this.definitionUuid,
    required this.nameSnapshot,
    this.muscleSnapshot = '',
    this.equipmentSnapshot = '',
    required this.position,
  });
}

@Entity()
class WorkoutSetEntity {
  @Id()
  int id = 0;
  @Unique()
  String uuid;
  @Index()
  String exerciseUuid;
  int position;
  String kind;
  String status;
  int? reps;
  int? loadGrams;
  String inputUnit;
  double? rpe;
  int? completedAtMs;
  int updatedAtMs;

  WorkoutSetEntity({
    this.id = 0,
    required this.uuid,
    required this.exerciseUuid,
    required this.position,
    this.kind = 'working',
    this.status = 'planned',
    this.reps,
    this.loadGrams,
    this.inputUnit = 'kg',
    this.rpe,
    this.completedAtMs,
    required this.updatedAtMs,
  });
}

@Entity()
class WorkoutSessionStateEntity {
  @Id()
  int id = 0;
  @Unique()
  String sessionUuid;
  String? selectedExerciseUuid;
  String? selectedSetUuid;
  String restState;
  int? restDeadlineUtcMs;
  int? restRemainingMsWhenPaused;
  int checkpointRevision;
  int savedAtMs;

  WorkoutSessionStateEntity({
    this.id = 0,
    required this.sessionUuid,
    this.selectedExerciseUuid,
    this.selectedSetUuid,
    this.restState = 'idle',
    this.restDeadlineUtcMs,
    this.restRemainingMsWhenPaused,
    this.checkpointRevision = 1,
    required this.savedAtMs,
  });
}

@Entity()
class WorkoutSyncOutboxEntity {
  @Id()
  int id = 0;

  /// Stable identity for one immutable locally committed snapshot.
  @Unique()
  String operationUuid;

  @Index()
  String sessionUuid;
  int localRevision;
  String action;
  String payloadJson;
  @Index()
  String state;
  int createdAtMs;
  int? attemptedAtMs;
  int attempts;
  int? serverRevision;
  int? serverChangeSeq;
  String? errorCode;

  WorkoutSyncOutboxEntity({
    this.id = 0,
    required this.operationUuid,
    required this.sessionUuid,
    required this.localRevision,
    required this.action,
    required this.payloadJson,
    this.state = 'pending',
    required this.createdAtMs,
    this.attemptedAtMs,
    this.attempts = 0,
    this.serverRevision,
    this.serverChangeSeq,
    this.errorCode,
  });
}

/// One durable cursor per verified Supabase owner and account-partitioned
/// ObjectBox Store. Persisted in the same transaction as imported data.
@Entity()
class WorkoutRestoreCursorEntity {
  @Id()
  int id = 0;
  @Unique()
  String ownerAccountId;
  String? cursorEpoch;
  int nextCursor;
  String? blockedCode;
  int? blockedAtMs;

  WorkoutRestoreCursorEntity({
    this.id = 0,
    required this.ownerAccountId,
    this.cursorEpoch,
    this.nextCursor = 0,
    this.blockedCode,
    this.blockedAtMs,
  });
}

/// Per-workout remote identity/revision, including tombstones for unseen IDs.
/// Do not confuse the server CAS revision with WorkoutSessionEntity.revision.
@Entity()
class WorkoutRemoteStateEntity {
  @Id()
  int id = 0;
  @Unique()
  String workoutUuid;
  String ownerAccountId;
  int serverRevision;
  int serverChangeSeq;
  String cursorEpoch;
  int localRevisionAtImport;
  bool deleted;

  WorkoutRemoteStateEntity({
    this.id = 0,
    required this.workoutUuid,
    required this.ownerAccountId,
    required this.serverRevision,
    required this.serverChangeSeq,
    required this.cursorEpoch,
    required this.localRevisionAtImport,
    this.deleted = false,
  });
}
