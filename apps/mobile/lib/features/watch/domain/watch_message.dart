import 'contract_reader.dart';
import 'workout_event_v2.dart';

export 'contract_reader.dart' show WatchContractException;

const _types = {
  'account_binding',
  'account_cleared',
  'plans_snapshot',
  'health_snapshot',
  'workout_event',
  'session_state',
  'session_command',
  'completed_workout',
  'ack',
};

const _commands = {
  'log_set',
  'correct_set',
  'skip_set',
  'start_rest',
  'clear_rest',
  'pause',
  'resume',
  'finish',
  'discard',
};

const _setValueKeys = {'reps', 'duration_seconds', 'load_grams', 'rpe'};

/// A phone and watch message (`contracts/watch_link/v1`). Nested lists and
/// objects are validated strictly and kept as plain JSON; typed access can be
/// added where a later stage needs it.
sealed class WatchMessage {
  const WatchMessage({
    required this.messageId,
    required this.sentAtUtc,
    required this.accountKey,
  });

  final String messageId;
  final String sentAtUtc;
  final String accountKey;

  String get type;
  Map<String, Object?> get bodyJson;

  Map<String, Object?> toJson() => {
    'schema_version': 1,
    'message_id': messageId,
    'type': type,
    'sent_at_utc': sentAtUtc,
    'account_key': accountKey,
    'body': bodyJson,
  };

  static WatchMessage fromJson(Map<String, Object?> json) {
    final o = StrictObject(
      json,
      required: {
        'schema_version',
        'message_id',
        'type',
        'sent_at_utc',
        'account_key',
        'body',
      },
    );
    final version = o.map['schema_version'];
    if (version is! num) throw const WatchContractException('invalid_value');
    if (version != 1) throw const WatchContractException('unsupported_version');
    final type = o.map['type'];
    if (type is! String || !_types.contains(type)) {
      throw const WatchContractException('unknown_type');
    }
    final id = o.uuid('message_id');
    final sent = o.dateTime('sent_at_utc');
    final key = o.accountKey();
    final raw = o.map['body'];

    StrictObject body(Set<String> req, [Set<String> opt = const {}]) =>
        StrictObject(raw, required: req, optional: opt);

    switch (type) {
      case 'account_binding':
        final b = body({'unit'});
        return AccountBinding(
          messageId: id,
          sentAtUtc: sent,
          accountKey: key,
          unit: b.oneOf('unit', {'kg', 'lb'}),
        );
      case 'account_cleared':
        final b = body({'wipe_unsent'});
        return AccountCleared(
          messageId: id,
          sentAtUtc: sent,
          accountKey: key,
          wipeUnsent: b.boolean('wipe_unsent'),
        );
      case 'plans_snapshot':
        final b = body(
          {'generated_at_utc', 'plans', 'recent_exercises'},
          {'today'},
        );
        for (final plan in b.list('plans', max: 100)) {
          _plan(plan);
        }
        for (final e in b.list('recent_exercises', max: 30)) {
          final r = StrictObject(e, required: {'exercise_id', 'name', 'kind'});
          r.string('exercise_id', max: 128);
          r.string('name', max: 120);
          r.oneOf('kind', {'reps', 'duration'});
        }
        if (b.has('today')) {
          final t = b.object(
            'today',
            required: {'plan_id', 'program_id', 'local_date', 'label'},
          );
          t.string('plan_id', max: 128);
          t.string('program_id', max: 128);
          t.localDate('local_date');
          t.string('label', max: 120);
        }
        return PlansSnapshot(
          messageId: id,
          sentAtUtc: sent,
          accountKey: key,
          generatedAtUtc: b.dateTime('generated_at_utc'),
          plans: deepCopyJson(b.map['plans'])! as List<Object?>,
          today: b.has('today') ? b.copyOfObject('today') : null,
          recentExercises:
              deepCopyJson(b.map['recent_exercises'])! as List<Object?>,
        );
      case 'health_snapshot':
        final b = body(
          {'local_date', 'as_of_utc'},
          {
            'readiness',
            'sleep',
            'resting_hr_bpm',
            'hrv_ms',
            'hrv_kind',
            'steps',
            'active_energy_kcal',
          },
        );
        if (b.has('readiness')) {
          final r = b.object(
            'readiness',
            required: {'score', 'band', 'headline', 'reason'},
          );
          r.integer('score', max: 100);
          r.oneOf('band', {'good', 'fair', 'low'});
          r.string('headline', max: 60);
          r.string('reason', max: 140);
        }
        if (b.has('sleep')) {
          final s = b.object(
            'sleep',
            required: const {},
            optional: {
              'score',
              'asleep_minutes',
              'deep_minutes',
              'rem_minutes',
            },
          );
          s.optionalInteger('score', max: 100);
          s.optionalInteger('asleep_minutes');
          s.optionalInteger('deep_minutes');
          s.optionalInteger('rem_minutes');
        }
        return HealthSnapshot(
          messageId: id,
          sentAtUtc: sent,
          accountKey: key,
          localDate: b.localDate('local_date'),
          asOfUtc: b.dateTime('as_of_utc'),
          readiness: b.has('readiness') ? b.copyOfObject('readiness') : null,
          sleep: b.has('sleep') ? b.copyOfObject('sleep') : null,
          restingHrBpm: b.optionalInteger('resting_hr_bpm'),
          hrvMs: b.optionalInteger('hrv_ms'),
          hrvKind: b.has('hrv_kind')
              ? b.oneOf('hrv_kind', {'sdnn', 'rmssd'})
              : null,
          steps: b.optionalInteger('steps'),
          activeEnergyKcal: b.optionalInteger('active_energy_kcal'),
        );
      case 'workout_event':
        final b = body({'event'});
        final event = b.map['event'];
        if (event is! Map) throw const WatchContractException('invalid_value');
        return WorkoutEventMessage(
          messageId: id,
          sentAtUtc: sent,
          accountKey: key,
          event: WorkoutEventV2.fromJson(Map<String, Object?>.from(event)),
        );
      case 'session_state':
        final b = body(
          {
            'session_id',
            'owner',
            'status',
            'name',
            'started_at_utc',
            'last_sequence',
            'exercises',
          },
          {'current_set_id', 'rest_deadline_utc'},
        );
        for (final e in b.list('exercises', max: 120)) {
          final x = StrictObject(
            e,
            required: {'exercise_id', 'name', 'kind', 'sets'},
          );
          x.string('exercise_id', max: 128);
          x.string('name', max: 120);
          x.oneOf('kind', {'reps', 'duration'});
          for (final s in x.list('sets', max: 300)) {
            final set = StrictObject(
              s,
              required: {'set_id', 'position', 'kind', 'status'},
              optional: {'input_unit', ..._setValueKeys},
            );
            set.uuid('set_id');
            set.integer('position');
            set.oneOf('kind', {'working', 'warmup'});
            set.oneOf('status', {'planned', 'completed', 'skipped'});
            if (set.has('input_unit')) set.oneOf('input_unit', {'kg', 'lb'});
            _setValues(set);
          }
        }
        return SessionState(
          messageId: id,
          sentAtUtc: sent,
          accountKey: key,
          sessionId: b.uuid('session_id'),
          owner: b.oneOf('owner', {'watch', 'phone'}),
          status: b.oneOf('status', {'active', 'paused'}),
          name: b.string('name', max: 120),
          startedAtUtc: b.dateTime('started_at_utc'),
          lastSequence: b.integer('last_sequence'),
          currentSetId: b.has('current_set_id')
              ? b.uuid('current_set_id')
              : null,
          restDeadlineUtc: b.has('rest_deadline_utc')
              ? b.dateTime('rest_deadline_utc')
              : null,
          exercises: deepCopyJson(b.map['exercises'])! as List<Object?>,
        );
      case 'session_command':
        final b = body(
          {'session_id', 'command_id', 'command'},
          {'set', 'rest_seconds'},
        );
        if (b.has('set')) {
          final s = b.object(
            'set',
            required: SetValues.keys,
            optional: SetValues.optionalKeys,
          );
          SetValues.read(s, requireRepsOrSeconds: false);
        }
        return SessionCommand(
          messageId: id,
          sentAtUtc: sent,
          accountKey: key,
          sessionId: b.uuid('session_id'),
          commandId: b.uuid('command_id'),
          command: b.oneOf('command', _commands),
          set: b.has('set') ? b.copyOfObject('set') : null,
          restSeconds: b.optionalInteger('rest_seconds', min: 1, max: 3600),
        );
      case 'completed_workout':
        final b = body(
          {'workout', 'last_sequence'},
          {'healthkit_workout_uuid'},
        );
        final workout = b.map['workout'];
        if (workout is! Map) {
          throw const WatchContractException('invalid_value');
        }
        if (workout['origin'] != 'beyondrep_watch') {
          throw const WatchContractException('invalid_value');
        }
        return CompletedWorkout(
          messageId: id,
          sentAtUtc: sent,
          accountKey: key,
          workout: b.copyOfObject('workout'),
          lastSequence: b.integer('last_sequence'),
          healthkitWorkoutUuid: b.has('healthkit_workout_uuid')
              ? b.uuid('healthkit_workout_uuid')
              : null,
        );
      default:
        final b = body({'acked_message_id', 'result'}, {'reason'});
        return Ack(
          messageId: id,
          sentAtUtc: sent,
          accountKey: key,
          ackedMessageId: b.uuid('acked_message_id'),
          result: b.oneOf('result', {'stored', 'duplicate', 'rejected'}),
          reason: b.has('reason')
              ? b.oneOf('reason', {
                  'wrong_account',
                  'invalid',
                  'unsupported_version',
                })
              : null,
        );
    }
  }
}

void _setValues(StrictObject s) {
  s.optionalInteger('reps');
  s.optionalInteger('duration_seconds', min: 1);
  s.optionalInteger('load_grams');
  s.optionalRpe('rpe');
}

void _plan(Object? raw) {
  final p = StrictObject(raw, required: {'plan_id', 'name', 'exercises'});
  p.string('plan_id', max: 128);
  p.string('name', max: 120);
  for (final e in p.list('exercises', max: 40)) {
    final x = StrictObject(
      e,
      required: {'exercise_id', 'name', 'kind', 'sets'},
      optional: {'muscle'},
    );
    x.string('exercise_id', max: 128);
    x.string('name', max: 120);
    x.oneOf('kind', {'reps', 'duration'});
    x.optionalString('muscle', max: 60);
    for (final s in x.list('sets', max: 30)) {
      final set = StrictObject(
        s,
        required: {'position', 'kind'},
        optional: {
          'target_reps',
          'target_seconds',
          'target_load_grams',
          'rest_seconds',
        },
      );
      set.integer('position');
      set.oneOf('kind', {'working', 'warmup'});
      set.optionalInteger('target_reps');
      set.optionalInteger('target_seconds', min: 1);
      set.optionalInteger('target_load_grams');
      set.optionalInteger('rest_seconds', max: 3600);
    }
  }
}

final class AccountBinding extends WatchMessage {
  const AccountBinding({
    required super.messageId,
    required super.sentAtUtc,
    required super.accountKey,
    required this.unit,
  });

  final String unit;

  @override
  String get type => 'account_binding';

  @override
  Map<String, Object?> get bodyJson => {'unit': unit};
}

final class AccountCleared extends WatchMessage {
  const AccountCleared({
    required super.messageId,
    required super.sentAtUtc,
    required super.accountKey,
    required this.wipeUnsent,
  });

  final bool wipeUnsent;

  @override
  String get type => 'account_cleared';

  @override
  Map<String, Object?> get bodyJson => {'wipe_unsent': wipeUnsent};
}

final class PlansSnapshot extends WatchMessage {
  const PlansSnapshot({
    required super.messageId,
    required super.sentAtUtc,
    required super.accountKey,
    required this.generatedAtUtc,
    required this.plans,
    required this.recentExercises,
    this.today,
  });

  final String generatedAtUtc;
  final List<Object?> plans;
  final Map<String, Object?>? today;
  final List<Object?> recentExercises;

  @override
  String get type => 'plans_snapshot';

  @override
  Map<String, Object?> get bodyJson => {
    'generated_at_utc': generatedAtUtc,
    'plans': plans,
    'today': ?today,
    'recent_exercises': recentExercises,
  };
}

final class HealthSnapshot extends WatchMessage {
  const HealthSnapshot({
    required super.messageId,
    required super.sentAtUtc,
    required super.accountKey,
    required this.localDate,
    required this.asOfUtc,
    this.readiness,
    this.sleep,
    this.restingHrBpm,
    this.hrvMs,
    this.hrvKind,
    this.steps,
    this.activeEnergyKcal,
  });

  final String localDate;
  final String asOfUtc;
  final Map<String, Object?>? readiness;
  final Map<String, Object?>? sleep;
  final int? restingHrBpm;
  final int? hrvMs;
  final String? hrvKind;
  final int? steps;
  final int? activeEnergyKcal;

  @override
  String get type => 'health_snapshot';

  @override
  Map<String, Object?> get bodyJson => {
    'local_date': localDate,
    'as_of_utc': asOfUtc,
    'readiness': ?readiness,
    'sleep': ?sleep,
    'resting_hr_bpm': ?restingHrBpm,
    'hrv_ms': ?hrvMs,
    'hrv_kind': ?hrvKind,
    'steps': ?steps,
    'active_energy_kcal': ?activeEnergyKcal,
  };
}

final class WorkoutEventMessage extends WatchMessage {
  const WorkoutEventMessage({
    required super.messageId,
    required super.sentAtUtc,
    required super.accountKey,
    required this.event,
  });

  final WorkoutEventV2 event;

  @override
  String get type => 'workout_event';

  @override
  Map<String, Object?> get bodyJson => {'event': event.toJson()};
}

final class SessionState extends WatchMessage {
  const SessionState({
    required super.messageId,
    required super.sentAtUtc,
    required super.accountKey,
    required this.sessionId,
    required this.owner,
    required this.status,
    required this.name,
    required this.startedAtUtc,
    required this.lastSequence,
    required this.exercises,
    this.currentSetId,
    this.restDeadlineUtc,
  });

  final String sessionId;
  final String owner;
  final String status;
  final String name;
  final String startedAtUtc;
  final int lastSequence;
  final String? currentSetId;
  final String? restDeadlineUtc;
  final List<Object?> exercises;

  @override
  String get type => 'session_state';

  @override
  Map<String, Object?> get bodyJson => {
    'session_id': sessionId,
    'owner': owner,
    'status': status,
    'name': name,
    'started_at_utc': startedAtUtc,
    'last_sequence': lastSequence,
    'current_set_id': ?currentSetId,
    'rest_deadline_utc': ?restDeadlineUtc,
    'exercises': exercises,
  };
}

final class SessionCommand extends WatchMessage {
  const SessionCommand({
    required super.messageId,
    required super.sentAtUtc,
    required super.accountKey,
    required this.sessionId,
    required this.commandId,
    required this.command,
    this.set,
    this.restSeconds,
  });

  final String sessionId;
  final String commandId;
  final String command;
  final Map<String, Object?>? set;
  final int? restSeconds;

  @override
  String get type => 'session_command';

  @override
  Map<String, Object?> get bodyJson => {
    'session_id': sessionId,
    'command_id': commandId,
    'command': command,
    'set': ?set,
    'rest_seconds': ?restSeconds,
  };
}

final class CompletedWorkout extends WatchMessage {
  const CompletedWorkout({
    required super.messageId,
    required super.sentAtUtc,
    required super.accountKey,
    required this.workout,
    required this.lastSequence,
    this.healthkitWorkoutUuid,
  });

  /// The cloud workout payload with origin `beyondrep_watch`. Full payload
  /// validation reuses the cloud workout validator in stage 4.
  final Map<String, Object?> workout;
  final int lastSequence;
  final String? healthkitWorkoutUuid;

  @override
  String get type => 'completed_workout';

  @override
  Map<String, Object?> get bodyJson => {
    'workout': workout,
    'last_sequence': lastSequence,
    'healthkit_workout_uuid': ?healthkitWorkoutUuid,
  };
}

final class Ack extends WatchMessage {
  const Ack({
    required super.messageId,
    required super.sentAtUtc,
    required super.accountKey,
    required this.ackedMessageId,
    required this.result,
    this.reason,
  });

  final String ackedMessageId;
  final String result;
  final String? reason;

  @override
  String get type => 'ack';

  @override
  Map<String, Object?> get bodyJson => {
    'acked_message_id': ackedMessageId,
    'result': result,
    'reason': ?reason,
  };
}
