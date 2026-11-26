import 'contract_reader.dart';

export 'contract_reader.dart' show WatchContractException;

const _eventKeys = {
  'schema_version',
  'event_id',
  'workout_id',
  'session_id',
  'origin_device_id',
  'sequence',
  'type',
  'occurred_at_utc',
  'recorded_at_utc',
  'time_zone',
  'payload',
};

const _setKeys = {'set_id', 'exercise_id', 'position', 'kind', 'input_unit'};
const _setOptionalKeys = {'reps', 'duration_seconds', 'load_grams', 'rpe'};

/// The values of one logged set (`set_logged` and `set_corrected`).
class SetValues {
  const SetValues({
    required this.setId,
    required this.exerciseId,
    required this.position,
    required this.kind,
    required this.inputUnit,
    this.reps,
    this.durationSeconds,
    this.loadGrams,
    this.rpe,
  });

  final String setId;
  final String exerciseId;
  final int position;
  final String kind;
  final String inputUnit;
  final int? reps;
  final int? durationSeconds;
  final int? loadGrams;
  final num? rpe;

  /// Reads the shared set fields from [o], which already passed key checks.
  static SetValues read(StrictObject o, {bool requireRepsOrSeconds = true}) {
    final values = SetValues(
      setId: o.uuid('set_id'),
      exerciseId: o.string('exercise_id', max: 128),
      position: o.integer('position'),
      kind: o.oneOf('kind', {'working', 'warmup'}),
      inputUnit: o.oneOf('input_unit', {'kg', 'lb'}),
      reps: o.optionalInteger('reps'),
      durationSeconds: o.optionalInteger('duration_seconds', min: 1),
      loadGrams: o.optionalInteger('load_grams'),
      rpe: o.optionalRpe('rpe'),
    );
    if (requireRepsOrSeconds &&
        values.reps == null &&
        values.durationSeconds == null) {
      throw const WatchContractException('missing_field');
    }
    return values;
  }

  Map<String, Object?> toJson() => {
    'set_id': setId,
    'exercise_id': exerciseId,
    'position': position,
    'kind': kind,
    'input_unit': inputUnit,
    'reps': ?reps,
    'duration_seconds': ?durationSeconds,
    'load_grams': ?loadGrams,
    'rpe': ?rpe,
  };

  static const keys = {..._setKeys};
  static const optionalKeys = {..._setOptionalKeys};
}

sealed class WorkoutEventV2 {
  const WorkoutEventV2({
    required this.eventId,
    required this.workoutId,
    required this.sessionId,
    required this.originDeviceId,
    required this.sequence,
    required this.occurredAtUtc,
    required this.recordedAtUtc,
    required this.timeZone,
  });

  final String eventId;
  final String workoutId;
  final String sessionId;
  final String originDeviceId;
  final int sequence;
  final String occurredAtUtc;
  final String recordedAtUtc;
  final String timeZone;

  String get type;
  Map<String, Object?> get payloadJson;

  Map<String, Object?> toJson() => {
    'schema_version': 2,
    'event_id': eventId,
    'workout_id': workoutId,
    'session_id': sessionId,
    'origin_device_id': originDeviceId,
    'sequence': sequence,
    'type': type,
    'occurred_at_utc': occurredAtUtc,
    'recorded_at_utc': recordedAtUtc,
    'time_zone': timeZone,
    'payload': payloadJson,
  };

  static WorkoutEventV2 fromJson(Map<String, Object?> json) {
    final o = StrictObject(json, required: _eventKeys);
    final version = o.map['schema_version'];
    if (version is! num) throw const WatchContractException('invalid_value');
    if (version != 2) throw const WatchContractException('unsupported_version');
    final type = o.map['type'];
    if (type is! String || !_types.contains(type)) {
      throw const WatchContractException('unknown_type');
    }
    final eventId = o.uuid('event_id');
    final workoutId = o.uuid('workout_id');
    final sessionId = o.uuid('session_id');
    final device = o.string('origin_device_id', max: 128);
    final sequence = o.integer('sequence');
    final occurred = o.dateTime('occurred_at_utc');
    final recorded = o.dateTime('recorded_at_utc');
    final zone = o.string('time_zone', max: 100);
    final p = o.map['payload'];

    SetValues setValues(StrictObject s) => SetValues.read(s);
    StrictObject payload(Set<String> req, [Set<String> opt = const {}]) =>
        StrictObject(p, required: req, optional: opt);

    switch (type) {
      case 'workout_started':
        final s = payload(
          {'activity_type', 'name', 'owner', 'account_key'},
          {'plan_id', 'program_day'},
        );
        final day = s.has('program_day')
            ? s.object('program_day', required: {'program_id', 'local_date'})
            : null;
        return WorkoutStarted(
          eventId: eventId,
          workoutId: workoutId,
          sessionId: sessionId,
          originDeviceId: device,
          sequence: sequence,
          occurredAtUtc: occurred,
          recordedAtUtc: recorded,
          timeZone: zone,
          activityType: s.string('activity_type', max: 80),
          name: s.string('name', max: 120),
          owner: s.oneOf('owner', {'watch', 'phone'}),
          accountKey: s.accountKey(),
          planId: s.optionalString('plan_id', max: 128),
          programId: day?.string('program_id', max: 128),
          programLocalDate: day?.localDate('local_date'),
        );
      case 'exercise_added':
        final s = payload({'exercise_id', 'name', 'kind', 'position'});
        return ExerciseAdded(
          eventId: eventId,
          workoutId: workoutId,
          sessionId: sessionId,
          originDeviceId: device,
          sequence: sequence,
          occurredAtUtc: occurred,
          recordedAtUtc: recorded,
          timeZone: zone,
          exerciseId: s.string('exercise_id', max: 128),
          name: s.string('name', max: 120),
          kind: s.oneOf('kind', {'reps', 'duration'}),
          position: s.integer('position'),
        );
      case 'set_logged':
        final s = payload(SetValues.keys, SetValues.optionalKeys);
        return SetLogged(
          eventId: eventId,
          workoutId: workoutId,
          sessionId: sessionId,
          originDeviceId: device,
          sequence: sequence,
          occurredAtUtc: occurred,
          recordedAtUtc: recorded,
          timeZone: zone,
          set: setValues(s),
        );
      case 'set_corrected':
        final s = payload({
          ...SetValues.keys,
          'supersedes_event_id',
        }, SetValues.optionalKeys);
        return SetCorrected(
          eventId: eventId,
          workoutId: workoutId,
          sessionId: sessionId,
          originDeviceId: device,
          sequence: sequence,
          occurredAtUtc: occurred,
          recordedAtUtc: recorded,
          timeZone: zone,
          set: setValues(s),
          supersedesEventId: s.uuid('supersedes_event_id'),
        );
      case 'set_skipped':
        final s = payload({'set_id'});
        return SetSkipped(
          eventId: eventId,
          workoutId: workoutId,
          sessionId: sessionId,
          originDeviceId: device,
          sequence: sequence,
          occurredAtUtc: occurred,
          recordedAtUtc: recorded,
          timeZone: zone,
          setId: s.uuid('set_id'),
        );
      case 'rest_started':
        final s = payload({'seconds', 'deadline_utc'});
        return RestStarted(
          eventId: eventId,
          workoutId: workoutId,
          sessionId: sessionId,
          originDeviceId: device,
          sequence: sequence,
          occurredAtUtc: occurred,
          recordedAtUtc: recorded,
          timeZone: zone,
          seconds: s.integer('seconds', min: 1, max: 3600),
          deadlineUtc: s.dateTime('deadline_utc'),
        );
      case 'platform_workout_exported':
        final s = payload({'platform', 'external_record_id'});
        return PlatformWorkoutExported(
          eventId: eventId,
          workoutId: workoutId,
          sessionId: sessionId,
          originDeviceId: device,
          sequence: sequence,
          occurredAtUtc: occurred,
          recordedAtUtc: recorded,
          timeZone: zone,
          platform: s.oneOf('platform', {'healthkit', 'health_connect'}),
          externalRecordId: s.string('external_record_id', max: 256),
        );
      default:
        payload(const {});
        return switch (type) {
          'rest_cleared' => RestCleared(
            eventId: eventId,
            workoutId: workoutId,
            sessionId: sessionId,
            originDeviceId: device,
            sequence: sequence,
            occurredAtUtc: occurred,
            recordedAtUtc: recorded,
            timeZone: zone,
          ),
          'workout_paused' => WorkoutPaused(
            eventId: eventId,
            workoutId: workoutId,
            sessionId: sessionId,
            originDeviceId: device,
            sequence: sequence,
            occurredAtUtc: occurred,
            recordedAtUtc: recorded,
            timeZone: zone,
          ),
          'workout_resumed' => WorkoutResumed(
            eventId: eventId,
            workoutId: workoutId,
            sessionId: sessionId,
            originDeviceId: device,
            sequence: sequence,
            occurredAtUtc: occurred,
            recordedAtUtc: recorded,
            timeZone: zone,
          ),
          'workout_completed' => WorkoutCompleted(
            eventId: eventId,
            workoutId: workoutId,
            sessionId: sessionId,
            originDeviceId: device,
            sequence: sequence,
            occurredAtUtc: occurred,
            recordedAtUtc: recorded,
            timeZone: zone,
          ),
          _ => WorkoutAbandoned(
            eventId: eventId,
            workoutId: workoutId,
            sessionId: sessionId,
            originDeviceId: device,
            sequence: sequence,
            occurredAtUtc: occurred,
            recordedAtUtc: recorded,
            timeZone: zone,
          ),
        };
    }
  }
}

const _types = {
  'workout_started',
  'exercise_added',
  'set_logged',
  'set_corrected',
  'set_skipped',
  'rest_started',
  'rest_cleared',
  'workout_paused',
  'workout_resumed',
  'workout_completed',
  'workout_abandoned',
  'platform_workout_exported',
};

final class WorkoutStarted extends WorkoutEventV2 {
  const WorkoutStarted({
    required super.eventId,
    required super.workoutId,
    required super.sessionId,
    required super.originDeviceId,
    required super.sequence,
    required super.occurredAtUtc,
    required super.recordedAtUtc,
    required super.timeZone,
    required this.activityType,
    required this.name,
    required this.owner,
    required this.accountKey,
    this.planId,
    this.programId,
    this.programLocalDate,
  });

  final String activityType;
  final String name;
  final String owner;
  final String accountKey;
  final String? planId;
  final String? programId;
  final String? programLocalDate;

  @override
  String get type => 'workout_started';

  @override
  Map<String, Object?> get payloadJson => {
    'activity_type': activityType,
    'name': name,
    'owner': owner,
    'account_key': accountKey,
    'plan_id': ?planId,
    if (programId != null)
      'program_day': {'program_id': programId, 'local_date': programLocalDate},
  };
}

final class ExerciseAdded extends WorkoutEventV2 {
  const ExerciseAdded({
    required super.eventId,
    required super.workoutId,
    required super.sessionId,
    required super.originDeviceId,
    required super.sequence,
    required super.occurredAtUtc,
    required super.recordedAtUtc,
    required super.timeZone,
    required this.exerciseId,
    required this.name,
    required this.kind,
    required this.position,
  });

  final String exerciseId;
  final String name;
  final String kind;
  final int position;

  @override
  String get type => 'exercise_added';

  @override
  Map<String, Object?> get payloadJson => {
    'exercise_id': exerciseId,
    'name': name,
    'kind': kind,
    'position': position,
  };
}

final class SetLogged extends WorkoutEventV2 {
  const SetLogged({
    required super.eventId,
    required super.workoutId,
    required super.sessionId,
    required super.originDeviceId,
    required super.sequence,
    required super.occurredAtUtc,
    required super.recordedAtUtc,
    required super.timeZone,
    required this.set,
  });

  final SetValues set;

  @override
  String get type => 'set_logged';

  @override
  Map<String, Object?> get payloadJson => set.toJson();
}

final class SetCorrected extends WorkoutEventV2 {
  const SetCorrected({
    required super.eventId,
    required super.workoutId,
    required super.sessionId,
    required super.originDeviceId,
    required super.sequence,
    required super.occurredAtUtc,
    required super.recordedAtUtc,
    required super.timeZone,
    required this.set,
    required this.supersedesEventId,
  });

  final SetValues set;
  final String supersedesEventId;

  @override
  String get type => 'set_corrected';

  @override
  Map<String, Object?> get payloadJson => {
    ...set.toJson(),
    'supersedes_event_id': supersedesEventId,
  };
}

final class SetSkipped extends WorkoutEventV2 {
  const SetSkipped({
    required super.eventId,
    required super.workoutId,
    required super.sessionId,
    required super.originDeviceId,
    required super.sequence,
    required super.occurredAtUtc,
    required super.recordedAtUtc,
    required super.timeZone,
    required this.setId,
  });

  final String setId;

  @override
  String get type => 'set_skipped';

  @override
  Map<String, Object?> get payloadJson => {'set_id': setId};
}

final class RestStarted extends WorkoutEventV2 {
  const RestStarted({
    required super.eventId,
    required super.workoutId,
    required super.sessionId,
    required super.originDeviceId,
    required super.sequence,
    required super.occurredAtUtc,
    required super.recordedAtUtc,
    required super.timeZone,
    required this.seconds,
    required this.deadlineUtc,
  });

  final int seconds;
  final String deadlineUtc;

  @override
  String get type => 'rest_started';

  @override
  Map<String, Object?> get payloadJson => {
    'seconds': seconds,
    'deadline_utc': deadlineUtc,
  };
}

final class PlatformWorkoutExported extends WorkoutEventV2 {
  const PlatformWorkoutExported({
    required super.eventId,
    required super.workoutId,
    required super.sessionId,
    required super.originDeviceId,
    required super.sequence,
    required super.occurredAtUtc,
    required super.recordedAtUtc,
    required super.timeZone,
    required this.platform,
    required this.externalRecordId,
  });

  final String platform;
  final String externalRecordId;

  @override
  String get type => 'platform_workout_exported';

  @override
  Map<String, Object?> get payloadJson => {
    'platform': platform,
    'external_record_id': externalRecordId,
  };
}

final class RestCleared extends WorkoutEventV2 {
  const RestCleared({
    required super.eventId,
    required super.workoutId,
    required super.sessionId,
    required super.originDeviceId,
    required super.sequence,
    required super.occurredAtUtc,
    required super.recordedAtUtc,
    required super.timeZone,
  });

  @override
  String get type => 'rest_cleared';

  @override
  Map<String, Object?> get payloadJson => const {};
}

final class WorkoutPaused extends WorkoutEventV2 {
  const WorkoutPaused({
    required super.eventId,
    required super.workoutId,
    required super.sessionId,
    required super.originDeviceId,
    required super.sequence,
    required super.occurredAtUtc,
    required super.recordedAtUtc,
    required super.timeZone,
  });

  @override
  String get type => 'workout_paused';

  @override
  Map<String, Object?> get payloadJson => const {};
}

final class WorkoutResumed extends WorkoutEventV2 {
  const WorkoutResumed({
    required super.eventId,
    required super.workoutId,
    required super.sessionId,
    required super.originDeviceId,
    required super.sequence,
    required super.occurredAtUtc,
    required super.recordedAtUtc,
    required super.timeZone,
  });

  @override
  String get type => 'workout_resumed';

  @override
  Map<String, Object?> get payloadJson => const {};
}

final class WorkoutCompleted extends WorkoutEventV2 {
  const WorkoutCompleted({
    required super.eventId,
    required super.workoutId,
    required super.sessionId,
    required super.originDeviceId,
    required super.sequence,
    required super.occurredAtUtc,
    required super.recordedAtUtc,
    required super.timeZone,
  });

  @override
  String get type => 'workout_completed';

  @override
  Map<String, Object?> get payloadJson => const {};
}

final class WorkoutAbandoned extends WorkoutEventV2 {
  const WorkoutAbandoned({
    required super.eventId,
    required super.workoutId,
    required super.sessionId,
    required super.originDeviceId,
    required super.sequence,
    required super.occurredAtUtc,
    required super.recordedAtUtc,
    required super.timeZone,
  });

  @override
  String get type => 'workout_abandoned';

  @override
  Map<String, Object?> get payloadJson => const {};
}
