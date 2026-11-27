import 'package:objectbox/objectbox.dart';

/// One imported Apple Watch workout. Local dedup for the phone's inbox and the
/// platform record reference used to hide the watch's own HealthKit workout.
/// Never backed up and never part of a cloud payload (ADR-0012).
@Entity()
class WatchWorkoutReceiptEntity {
  @Id()
  int id = 0;

  /// Lowercase BeyondRep workout UUID.
  @Unique()
  String workoutUuid;

  /// Lowercase `message_id` of the delivery that stored the workout.
  @Unique()
  String messageId;

  /// Lowercase HKWorkout UUID from `healthkit_workout_uuid`, when sent.
  String? platformWorkoutUuid;

  int receivedAtMs;

  WatchWorkoutReceiptEntity({
    this.id = 0,
    required this.workoutUuid,
    required this.messageId,
    this.platformWorkoutUuid,
    required this.receivedAtMs,
  });
}
