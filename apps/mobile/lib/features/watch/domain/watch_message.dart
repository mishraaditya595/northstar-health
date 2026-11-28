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
  'workout_link',
  'join',
  'workout_health',
};

const _commands = {
  'log_set',
  'correct_set',
  'skip_set',
  'add_set',
  'start_rest',
  'clear_rest',
  'pause',
  'resume',
  'finish',
  'discard',
};

const _rejectReasons = {
  'unknown_session',
  'unknown_set',
  'invalid_values',
  'not_allowed',
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
            'resting_hr_usual_bpm',
            'hrv_usual_ms',
            'week',
          },
        );
        if (b.has('readiness')) {
          final r = b.object(
            'readiness',
            required: {'score', 'band', 'headline', 'reason'},
            optional: {'factors'},
          );
          r.integer('score', max: 100);
          r.oneOf('band', {'good', 'fair', 'low'});
          r.string('headline', max: 60);
          r.string('reason', max: 140);
          if (r.has('factors')) {
            final inputs = <String>{};
            for (final f in r.list('factors', max: 4)) {
              final factor = StrictObject(
                f,
                required: {'input', 'status', 'tone'},
              );
              // Each input appears once; JSON Schema cannot say so.
              if (!inputs.add(
                factor.oneOf('input', {
                  'sleep',
                  'hrv',
                  'resting_hr',
                  'training_load',
                }),
              )) {
                throw const WatchContractException('invalid_value');
              }
              factor.string('status', max: 24);
              factor.oneOf('tone', {'good', 'neutral', 'caution'});
            }
          }
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
              'core_minutes',
              'awake_minutes',
            },
          );
          s.optionalInteger('score', max: 100);
          s.optionalInteger('asleep_minutes');
          s.optionalInteger('deep_minutes');
          s.optionalInteger('rem_minutes');
          s.optionalInteger('core_minutes');
          s.optionalInteger('awake_minutes');
        }
        final localDate = b.localDate('local_date');
        if (b.has('week')) {
          final week = b.list('week', max: 7);
          if (week.isEmpty) throw const WatchContractException('invalid_value');
          String? previous;
          for (final d in week) {
            final day = StrictObject(
              d,
              required: {'local_date'},
              optional: {
                'asleep_minutes',
                'sleep_score',
                'resting_hr_bpm',
                'hrv_ms',
                'steps',
              },
            );
            final date = day.localDate('local_date');
            // Dates are zero-padded, so string order is date order.
            if ((previous != null && date.compareTo(previous) <= 0) ||
                date.compareTo(localDate) > 0) {
              throw const WatchContractException('invalid_value');
            }
            previous = date;
            day.optionalInteger('asleep_minutes');
            day.optionalInteger('sleep_score', max: 100);
            day.optionalInteger('resting_hr_bpm');
            day.optionalInteger('hrv_ms');
            day.optionalInteger('steps');
          }
        }
        return HealthSnapshot(
          messageId: id,
          sentAtUtc: sent,
          accountKey: key,
          localDate: localDate,
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
          restingHrUsualBpm: b.optionalInteger('resting_hr_usual_bpm'),
          hrvUsualMs: b.optionalInteger('hrv_usual_ms'),
          week: b.has('week')
              ? [
                  for (final d in b.list('week'))
                    deepCopyJson(d)! as Map<String, Object?>,
                ]
              : null,
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
          {
            'current_set_id',
            'rest_deadline_utc',
            'end_reason',
            'paused_at_utc',
            'paused_seconds',
            'applied_command_ids',
            'rejected_commands',
          },
        );
        final status = b.oneOf('status', {'active', 'paused', 'ended'});
        // `end_reason` goes with `ended` and `paused_at_utc` with `paused`.
        if (b.has('end_reason') != (status == 'ended') ||
            (b.has('paused_at_utc') && status != 'paused')) {
          throw const WatchContractException('invalid_value');
        }
        if (b.has('end_reason')) {
          b.oneOf('end_reason', {'completed', 'discarded'});
        }
        if (b.has('paused_at_utc')) b.dateTime('paused_at_utc');
        b.optionalInteger('paused_seconds');
        if (b.has('applied_command_ids')) {
          for (final id in b.list('applied_command_ids', max: 20)) {
            StrictObject({'id': id}, required: {'id'}).uuid('id');
          }
        }
        if (b.has('rejected_commands')) {
          for (final r in b.list('rejected_commands', max: 20)) {
            final o = StrictObject(r, required: {'command_id', 'reason'});
            o.uuid('command_id');
            o.oneOf('reason', _rejectReasons);
          }
        }
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
              optional: {'input_unit', 'rest_seconds', ..._setValueKeys},
            );
            set.uuid('set_id');
            set.integer('position');
            set.oneOf('kind', {'working', 'warmup'});
            set.oneOf('status', {'planned', 'completed', 'skipped'});
            if (set.has('input_unit')) set.oneOf('input_unit', {'kg', 'lb'});
            set.optionalInteger('rest_seconds', min: 1, max: 3600);
            _setValues(set);
          }
        }
        return SessionState(
          messageId: id,
          sentAtUtc: sent,
          accountKey: key,
          sessionId: b.uuid('session_id'),
          owner: b.oneOf('owner', {'watch', 'phone'}),
          status: status,
          name: b.string('name', max: 120),
          startedAtUtc: b.dateTime('started_at_utc'),
          lastSequence: b.integer('last_sequence'),
          currentSetId: b.has('current_set_id')
              ? b.uuid('current_set_id')
              : null,
          restDeadlineUtc: b.has('rest_deadline_utc')
              ? b.dateTime('rest_deadline_utc')
              : null,
          endReason: b.has('end_reason')
              ? b.map['end_reason']! as String
              : null,
          pausedAtUtc: b.has('paused_at_utc')
              ? b.map['paused_at_utc']! as String
              : null,
          pausedSeconds: b.optionalInteger('paused_seconds'),
          appliedCommandIds: b.has('applied_command_ids')
              ? List<String>.from(b.map['applied_command_ids']! as List)
              : const [],
          rejectedCommands: b.has('rejected_commands')
              ? [
                  for (final r in b.map['rejected_commands']! as List)
                    (
                      commandId: (r as Map)['command_id']! as String,
                      reason: r['reason']! as String,
                    ),
                ]
              : const [],
          exercises: deepCopyJson(b.map['exercises'])! as List<Object?>,
        );
      case 'session_command':
        final b = body(
          {'session_id', 'command_id', 'command'},
          {'set', 'rest_seconds', 'exercise_id'},
        );
        final command = b.oneOf('command', _commands);
        // The schema requires `set` for these and `exercise_id` for add_set.
        if (const {'log_set', 'correct_set', 'skip_set'}.contains(command) &&
            !b.has('set')) {
          throw const WatchContractException('missing_field');
        }
        if (b.has('exercise_id') != (command == 'add_set')) {
          throw WatchContractException(
            command == 'add_set' ? 'missing_field' : 'unknown_key',
          );
        }
        if (b.has('exercise_id')) b.string('exercise_id', max: 128);
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
          command: command,
          exerciseId: b.has('exercise_id')
              ? b.map['exercise_id']! as String
              : null,
          set: b.has('set') ? b.copyOfObject('set') : null,
          restSeconds: b.optionalInteger('rest_seconds', min: 1, max: 3600),
        );
      case 'completed_workout':
        final b = body(
          {'workout', 'last_sequence'},
          {'healthkit_workout_uuid', 'program_day'},
        );
        final workout = b.map['workout'];
        if (workout is! Map) {
          throw const WatchContractException('invalid_value');
        }
        if (workout['origin'] != 'beyondrep_watch' ||
            workout['workout_id'] is! String) {
          throw const WatchContractException('invalid_value');
        }
        ({String planId, String programId, String localDate})? programDay;
        if (b.has('program_day')) {
          final d = b.object(
            'program_day',
            required: {'plan_id', 'program_id', 'local_date'},
          );
          programDay = (
            planId: d.string('plan_id', max: 128),
            programId: d.string('program_id', max: 128),
            localDate: d.localDate('local_date'),
          );
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
          programDay: programDay,
        );
      case 'workout_link':
        final b = body({'workout_id', 'healthkit_workout_uuid'});
        return WorkoutLink(
          messageId: id,
          sentAtUtc: sent,
          accountKey: key,
          workoutId: b.uuid('workout_id'),
          healthkitWorkoutUuid: b.uuid('healthkit_workout_uuid'),
        );
      case 'workout_health':
        final b = body(
          {'workout_id', 'start_utc', 'end_utc', 'heart_rate'},
          {'total_kcal'},
        );
        final startText = b.dateTime('start_utc');
        final endText = b.dateTime('end_utc');
        final start = DateTime.parse(startText).toUtc();
        final end = DateTime.parse(endText).toUtc();
        if (!end.isAfter(start)) {
          throw const WatchContractException('invalid_value');
        }
        DateTime? previous;
        final points = <HeartRatePoint>[];
        for (final item in b.list('heart_rate', max: 600)) {
          final p = StrictObject(item, required: {'at_utc', 'bpm'});
          final atText = p.dateTime('at_utc');
          final at = DateTime.parse(atText).toUtc();
          // Inside the workout and strictly increasing; JSON Schema cannot say so.
          if (at.isBefore(start) ||
              at.isAfter(end) ||
              (previous != null && !at.isAfter(previous))) {
            throw const WatchContractException('invalid_value');
          }
          previous = at;
          points.add(
            HeartRatePoint(
              atUtc: atText,
              bpm: p.integer('bpm', min: 25, max: 250),
            ),
          );
        }
        double? kcal;
        if (b.has('total_kcal')) {
          final k = b.map['total_kcal'];
          if (k is! num || !(k > 0 && k <= 10000)) {
            throw const WatchContractException('invalid_value');
          }
          kcal = k.toDouble();
        }
        return WorkoutHealth(
          messageId: id,
          sentAtUtc: sent,
          accountKey: key,
          workoutId: b.uuid('workout_id'),
          startUtc: startText,
          endUtc: endText,
          heartRate: points,
          totalKcal: kcal,
        );
      case 'join':
        final b = body(const {}, {'session_id'});
        return JoinMessage(
          messageId: id,
          sentAtUtc: sent,
          accountKey: key,
          sessionId: b.has('session_id') ? b.uuid('session_id') : null,
        );
      default:
        final b = body({'acked_message_id', 'result'}, {'reason'});
        final result = b.oneOf('result', {'stored', 'duplicate', 'rejected'});
        final reason = b.has('reason')
            ? b.oneOf('reason', {
                'wrong_account',
                'invalid',
                'unsupported_version',
                'not_written',
              })
            : null;
        // `not_written` goes with `rejected` only.
        if (reason == 'not_written' && result != 'rejected') {
          throw const WatchContractException('invalid_value');
        }
        return Ack(
          messageId: id,
          sentAtUtc: sent,
          accountKey: key,
          ackedMessageId: b.uuid('acked_message_id'),
          result: result,
          reason: reason,
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
    this.restingHrUsualBpm,
    this.hrvUsualMs,
    this.week,
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
  final int? restingHrUsualBpm;
  final int? hrvUsualMs;

  /// Up to 7 local days ending on [localDate], oldest first.
  final List<Map<String, Object?>>? week;

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
    'resting_hr_usual_bpm': ?restingHrUsualBpm,
    'hrv_usual_ms': ?hrvUsualMs,
    'week': ?week,
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
    this.endReason,
    this.pausedAtUtc,
    this.pausedSeconds,
    this.appliedCommandIds = const [],
    this.rejectedCommands = const [],
  });

  final String sessionId;
  final String owner;
  final String status;
  final String name;
  final String startedAtUtc;
  final int lastSequence;
  final String? currentSetId;
  final String? restDeadlineUtc;

  /// `completed` or `discarded`, only when [status] is `ended`.
  final String? endReason;

  /// Only while paused.
  final String? pausedAtUtc;

  /// The total of earlier pauses, in seconds.
  final int? pausedSeconds;

  /// Phone commands the watch applied, newest last, at most 20.
  final List<String> appliedCommandIds;
  final List<({String commandId, String reason})> rejectedCommands;
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
    'end_reason': ?endReason,
    'paused_at_utc': ?pausedAtUtc,
    'paused_seconds': ?pausedSeconds,
    if (appliedCommandIds.isNotEmpty) 'applied_command_ids': appliedCommandIds,
    if (rejectedCommands.isNotEmpty)
      'rejected_commands': [
        for (final r in rejectedCommands)
          {'command_id': r.commandId, 'reason': r.reason},
      ],
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
    this.exerciseId,
  });

  final String sessionId;
  final String commandId;
  final String command;

  /// Only for `add_set`.
  final String? exerciseId;
  final Map<String, Object?>? set;
  final int? restSeconds;

  @override
  String get type => 'session_command';

  @override
  Map<String, Object?> get bodyJson => {
    'session_id': sessionId,
    'command_id': commandId,
    'command': command,
    'exercise_id': ?exerciseId,
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
    this.programDay,
  });

  /// The cloud workout payload with origin `beyondrep_watch`. Full payload
  /// validation reuses the cloud workout validator in stage 4.
  final Map<String, Object?> workout;
  final int lastSequence;
  final String? healthkitWorkoutUuid;

  /// Today's program day the watch copied from `plans_snapshot.today`.
  final ({String planId, String programId, String localDate})? programDay;

  @override
  String get type => 'completed_workout';

  @override
  Map<String, Object?> get bodyJson => {
    'workout': workout,
    'last_sequence': lastSequence,
    'healthkit_workout_uuid': ?healthkitWorkoutUuid,
    if (programDay case final d?)
      'program_day': {
        'plan_id': d.planId,
        'program_id': d.programId,
        'local_date': d.localDate,
      },
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

/// The watch's receipt for a workout the phone owns: the one `HKWorkout` it
/// saved. No health values travel; the phone stores the id and acks it.
final class WorkoutLink extends WatchMessage {
  const WorkoutLink({
    required super.messageId,
    required super.sentAtUtc,
    required super.accountKey,
    required this.workoutId,
    required this.healthkitWorkoutUuid,
  });

  /// The phone workout's session id.
  final String workoutId;
  final String healthkitWorkoutUuid;

  @override
  String get type => 'workout_link';

  @override
  Map<String, Object?> get bodyJson => {
    'workout_id': workoutId,
    'healthkit_workout_uuid': healthkitWorkoutUuid,
  };
}

/// The watch tells the phone a follower is attached, so the phone sends its
/// state at once. [sessionId] is null when the watch does not know the session
/// yet (it was just launched): "whatever workout you are running".
final class JoinMessage extends WatchMessage {
  const JoinMessage({
    required super.messageId,
    required super.sentAtUtc,
    required super.accountKey,
    this.sessionId,
  });

  final String? sessionId;

  @override
  String get type => 'join';

  @override
  Map<String, Object?> get bodyJson => {
    if (sessionId != null) 'session_id': sessionId,
  };
}

/// One per-minute heart rate average of [WorkoutHealth].
class HeartRatePoint {
  const HeartRatePoint({required this.atUtc, required this.bpm});

  final String atUtc;
  final int bpm;
}

/// The heart rate and total calories of one finished watch workout, sent after
/// the phone acked the workout (Wear OS stage 3b). With `health_snapshot` the
/// only message that carries health values: the phone holds them in memory for
/// the Health Connect write and stores none of them.
final class WorkoutHealth extends WatchMessage {
  const WorkoutHealth({
    required super.messageId,
    required super.sentAtUtc,
    required super.accountKey,
    required this.workoutId,
    required this.startUtc,
    required this.endUtc,
    required this.heartRate,
    this.totalKcal,
  });

  final String workoutId;
  final String startUtc;
  final String endUtc;
  final List<HeartRatePoint> heartRate;
  final double? totalKcal;

  @override
  String get type => 'workout_health';

  @override
  Map<String, Object?> get bodyJson => {
    'workout_id': workoutId,
    'start_utc': startUtc,
    'end_utc': endUtc,
    'heart_rate': [
      for (final p in heartRate) {'at_utc': p.atUtc, 'bpm': p.bpm},
    ],
    'total_kcal': ?totalKcal,
  };
}
