import 'dart:convert';

import '../../core/units/load_units.dart';
import '../workouts/domain/workout_models.dart';

/// A contract violation must never advance a durable restore cursor.
/// Avoid including server JSON or user-provided workout values in errors.
class RestoreContractException extends FormatException {
  const RestoreContractException(this.code, {this.request = false})
    : super(
        request
            ? 'Invalid workout restore request'
            : 'Invalid workout restore feed',
      );

  /// Stable non-PII reason; no server payload, account, or workout values.
  final String code;
  final bool request;
}

Never _invalid(String code) => throw RestoreContractException(code);

Never _invalidRequest() =>
    throw const RestoreContractException('invalid_request', request: true);

// PostgreSQL UUID input allows braces, optional 4-hex-group separators,
// upper-case and no hyphens. Always store the canonical lower-case identity.
final _pgUuid = RegExp(r'^[0-9a-fA-F]{4}(?:-?[0-9a-fA-F]{4}){7}$');
// Mirrors the P2-01 validator: full UTC instants can carry a Z or ±HH:MM.
final _timestamp = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(Z|[+-]\d{2}:\d{2})$',
);

String _id(Object? value) {
  if (value is! String) _invalid('invalid_uuid');
  final raw = value.startsWith('{') && value.endsWith('}')
      ? value.substring(1, value.length - 1)
      : value;
  if (!_pgUuid.hasMatch(raw)) _invalid('invalid_uuid');
  final hex = raw.replaceAll('-', '').toLowerCase();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

int _integer(Object? value, {int min = 0, int? max}) {
  if (value is! int || value < min || (max != null && value > max)) {
    _invalid('invalid_number');
  }
  return value;
}

String _text(Object? value, {bool allowEmpty = false}) {
  if (value is! String ||
      (!allowEmpty && value.isEmpty) ||
      value.runes.length > 160) {
    _invalid('invalid_text');
  }
  return value;
}

DateTime _date(Object? value) {
  if (value is! String) _invalid('invalid_timestamp');
  final match = _timestamp.firstMatch(value);
  if (match == null) _invalid('invalid_timestamp');
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  final fraction = match.group(7) ?? '';
  final zone = match.group(8)!;
  if (year == 0 ||
      hour > 24 ||
      minute > 59 ||
      second > 60 ||
      (hour == 24 &&
          (minute != 0 ||
              second != 0 ||
              fraction.replaceAll('0', '').isNotEmpty))) {
    _invalid('invalid_timestamp');
  }
  // DateTime normalizes dates like February 30. Validate the unmodified
  // calendar fields, then normalize PostgreSQL's 24:00 and leap-second
  // :60 conventions to the corresponding UTC instant.
  final calendar = DateTime.utc(year, month, day);
  if (calendar.year != year || calendar.month != month || calendar.day != day) {
    _invalid('invalid_timestamp');
  }
  if (zone != 'Z') {
    final zoneHour = int.parse(zone.substring(1, 3));
    final zoneMinute = int.parse(zone.substring(4, 6));
    if (zoneHour > 23 || zoneMinute > 59) {
      _invalid('invalid_timezone_offset');
    }
  }
  var normalized = value;
  if (hour == 24) normalized = normalized.replaceRange(11, 13, '00');
  if (second == 60) normalized = normalized.replaceRange(17, 19, '59');
  final parsed = DateTime.tryParse(normalized);
  if (parsed == null) _invalid('invalid_timestamp');
  return parsed.toUtc().add(
    Duration(days: hour == 24 ? 1 : 0, seconds: second == 60 ? 1 : 0),
  );
}

Map<String, dynamic> _map(
  Object? value,
  Set<String> required, [
  Set<String>? allowed,
]) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    _invalid('invalid_object');
  }
  final result = Map<String, dynamic>.from(value);
  final keys = result.keys.toSet();
  if (!keys.containsAll(required)) _invalid('missing_field');
  if (!((allowed ?? required).containsAll(keys))) {
    _invalid('unsupported_field');
  }
  return result;
}

List<dynamic> _list(Object? value, int max, {required String overflowCode}) {
  if (value is! List) _invalid('invalid_list');
  if (value.length > max) _invalid(overflowCode);
  return value;
}

const _pageFields = <String>{
  'schema_version',
  'cursor_epoch',
  'cursor_reset',
  'next_cursor',
  'has_more',
  'changes',
};
const _changeFields = <String>{
  'workout_id',
  'server_revision',
  'change_seq',
  'deleted',
  'payload',
};
const _workoutFields = <String>{
  'schema_version',
  'workout_id',
  'origin',
  'status',
  'name',
  'started_at_utc',
  'completed_at_utc',
  'original_offset_minutes',
  'exercises',
};
const _exerciseRequired = <String>{'id', 'name', 'position', 'sets'};
const _exerciseFields = <String>{..._exerciseRequired, 'muscle', 'equipment'};
const _setRequired = <String>{'id', 'position', 'kind', 'status', 'input_unit'};
const _setFields = <String>{
  ..._setRequired,
  'reps',
  'load_grams',
  'rpe',
  'completed_at_utc',
};

/// Server-side snapshots have no *local* optimistic-lock revision.
/// ObjectBox assigns a local revision only during a guarded import; the server
/// revision is carried by RemoteWorkoutChange for compare-and-swap decisions.
class RemoteWorkoutSnapshot {
  const RemoteWorkoutSnapshot({
    required this.uuid,
    required this.name,
    required this.startedAtUtc,
    required this.completedAtUtc,
    required this.originalOffsetMinutes,
    required this.exercises,
    required this.sets,
  });

  final String uuid;
  final String name;
  final DateTime startedAtUtc;
  final DateTime completedAtUtc;
  final int originalOffsetMinutes;
  final List<WorkoutExerciseRecord> exercises;
  final List<WorkoutSetRecord> sets;
  WorkoutStatus get status => WorkoutStatus.completed;
}

/// Immutable validated workout change, deliberately detached from ObjectBox.
class RemoteWorkoutChange {
  const RemoteWorkoutChange({
    required this.workoutId,
    required this.serverRevision,
    required this.changeSeq,
    required this.deleted,
    required this.snapshot,
  });

  final String workoutId;
  final int serverRevision;
  final int changeSeq;
  final bool deleted;
  final RemoteWorkoutSnapshot? snapshot;
}

/// Pure decoder for the P2-06 server epoch-aware restore contract.
///
/// The caller supplies the request tuple. Validation rejects invalid server
/// state, unknown schema keys, cross-page cursor gaps, out-of-order changes,
/// unexpected deletion payloads and all non-phone-completed snapshots.
/// No local data is mutated by decoding.
class WorkoutRestorePage {
  const WorkoutRestorePage({
    required this.cursorEpoch,
    required this.cursorReset,
    required this.nextCursor,
    required this.hasMore,
    required this.changes,
  });

  final String cursorEpoch;
  final bool cursorReset;
  final int nextCursor;
  final bool hasMore;
  final List<RemoteWorkoutChange> changes;

  /// Validates arguments *before* issuing a network request as well as
  /// when decoding its response.
  static void validateRequest({
    required int afterSeq,
    required int limit,
    required String? requestedEpoch,
  }) {
    // Dart int already occupies the signed 64-bit range on the app targets.
    if (afterSeq < 0 || limit < 1 || limit > 200) {
      _invalidRequest();
    }
    if (requestedEpoch != null) {
      try {
        _id(requestedEpoch);
      } on RestoreContractException {
        _invalidRequest();
      }
    }
    if (afterSeq > 0 && requestedEpoch == null) _invalidRequest();
  }

  static WorkoutRestorePage decode(
    Object? raw, {
    required int afterSeq,
    required int limit,
    required String? requestedEpoch,
  }) {
    validateRequest(
      afterSeq: afterSeq,
      limit: limit,
      requestedEpoch: requestedEpoch,
    );
    final epoch = requestedEpoch == null ? null : _id(requestedEpoch);

    final body = _map(raw, _pageFields);
    if (body['schema_version'] != 1) _invalid('invalid_schema_version');
    final currentEpoch = _id(body['cursor_epoch']);
    final reset = body['cursor_reset'];
    final more = body['has_more'];
    if (reset is! bool || more is! bool) _invalid('invalid_page_flags');
    final next = _integer(body['next_cursor']);
    final values = _list(
      body['changes'],
      200,
      overflowCode: 'too_many_changes',
    );
    if (reset == true) {
      if (next != 0 || more != false || values.isNotEmpty) {
        _invalid('invalid_cursor_reset');
      }
      return WorkoutRestorePage(
        cursorEpoch: currentEpoch,
        cursorReset: true,
        nextCursor: 0,
        hasMore: false,
        changes: const [],
      );
    }
    // A normal page must be bound to the request epoch, unless it is the
    // zero-cursor bootstrap. A mismatched epoch is only valid with reset=true.
    if (epoch != null && epoch != currentEpoch) {
      _invalid('epoch_mismatch');
    }
    if (values.length > limit || (more == true && values.length != limit)) {
      _invalid('invalid_page_limit');
    }

    final changes = <RemoteWorkoutChange>[];
    final seen = <String>{};
    var seq = afterSeq;
    for (final rawChange in values) {
      final value = _map(rawChange, _changeFields);
      final id = _id(value['workout_id']);
      final revision = _integer(value['server_revision'], min: 1);
      final changeSeq = _integer(value['change_seq'], min: 1);
      if (!seen.add(id)) _invalid('duplicate_workout_id');
      if (changeSeq <= seq) _invalid('invalid_change_order');
      seq = changeSeq;
      if (value['deleted'] is! bool) _invalid('invalid_delete_flag');
      final deleted = value['deleted'] as bool;
      final payload = value['payload'];
      if (deleted && payload != null || !deleted && payload == null) {
        _invalid('invalid_change_payload');
      }
      final workout = deleted ? null : _workout(payload, id);
      changes.add(
        RemoteWorkoutChange(
          workoutId: id,
          serverRevision: revision,
          changeSeq: changeSeq,
          deleted: deleted,
          snapshot: workout,
        ),
      );
    }
    if (next != seq || (changes.isEmpty && more == true)) {
      _invalid('invalid_next_cursor');
    }
    return WorkoutRestorePage(
      cursorEpoch: currentEpoch,
      cursorReset: false,
      nextCursor: next,
      hasMore: more,
      changes: List.unmodifiable(changes),
    );
  }

  static RemoteWorkoutSnapshot _workout(Object? raw, String workoutId) {
    // Bound the bytes before traversing a potentially large nested response.
    try {
      if (utf8.encode(jsonEncode(raw)).length > 65536) {
        _invalid('payload_too_large');
      }
    } on RestoreContractException {
      rethrow;
    } catch (_) {
      _invalid('invalid_payload');
    }
    final data = _map(raw, _workoutFields);
    if (data['schema_version'] != 1) _invalid('invalid_workout_schema');
    if (_id(data['workout_id']) != workoutId) _invalid('workout_id_mismatch');
    if (data['origin'] != 'northstar_phone') {
      _invalid('invalid_workout_origin');
    }
    if (data['status'] != 'completed') _invalid('invalid_workout_status');
    final name = _text(data['name']);
    final start = _date(data['started_at_utc']);
    final finish = _date(data['completed_at_utc']);
    if (finish.isBefore(start)) _invalid('invalid_workout_time_order');
    final offset = data['original_offset_minutes'];
    if (offset is! int || offset < -840 || offset > 840) {
      _invalid('invalid_original_offset');
    }
    final exerciseRows = _list(
      data['exercises'],
      120,
      overflowCode: 'too_many_exercises',
    );
    final exercises = <WorkoutExerciseRecord>[];
    final sets = <WorkoutSetRecord>[];
    // PostgreSQL requires uniqueness within exercises and within sets,
    // independently; reusing an ID across those two domains is permitted.
    final exerciseIds = <String>{};
    final setIds = <String>{};
    for (final rawExercise in exerciseRows) {
      final exercise = _map(rawExercise, _exerciseRequired, _exerciseFields);
      final exerciseId = _id(exercise['id']);
      if (!exerciseIds.add(exerciseId)) {
        _invalid('duplicate_exercise_id');
      }
      final item = WorkoutExerciseRecord(
        uuid: exerciseId,
        sessionUuid: workoutId,
        nameSnapshot: _text(exercise['name']),
        muscleSnapshot: exercise.containsKey('muscle')
            ? _text(exercise['muscle'], allowEmpty: true)
            : '',
        equipmentSnapshot: exercise.containsKey('equipment')
            ? _text(exercise['equipment'], allowEmpty: true)
            : '',
        position: _integer(exercise['position'], max: 10000),
      );
      exercises.add(item);
      for (final rawSet in _list(
        exercise['sets'],
        300,
        overflowCode: 'too_many_sets',
      )) {
        final row = _map(rawSet, _setRequired, _setFields);
        final setId = _id(row['id']);
        if (!setIds.add(setId)) _invalid('duplicate_set_id');
        final kind = switch (row['kind']) {
          'working' => WorkoutSetKind.working,
          'warmup' => WorkoutSetKind.warmup,
          _ => _invalid('invalid_set_kind'),
        };
        final status = switch (row['status']) {
          'planned' => WorkoutSetStatus.planned,
          'completed' => WorkoutSetStatus.completed,
          'skipped' => WorkoutSetStatus.skipped,
          _ => _invalid('invalid_set_status'),
        };
        final unit = switch (row['input_unit']) {
          'kg' => LoadUnit.kg,
          'lb' => LoadUnit.lb,
          _ => _invalid('invalid_set_unit'),
        };
        final rpeRaw = row['rpe'];
        if (rpeRaw != null &&
            (rpeRaw is! num ||
                !rpeRaw.isFinite ||
                rpeRaw < 0 ||
                rpeRaw > 10 ||
                (rpeRaw * 2) % 1 != 0)) {
          _invalid('invalid_set_rpe');
        }
        final double? rpe = rpeRaw == null ? null : (rpeRaw as num).toDouble();
        final completion = row['completed_at_utc'] == null
            ? null
            : _date(row['completed_at_utc']);
        if (completion != null && completion.isBefore(start)) {
          _invalid('invalid_set_time_order');
        }
        if (status == WorkoutSetStatus.completed &&
            (row['reps'] == null || completion == null)) {
          _invalid('invalid_set_completion');
        }
        final workoutSet = WorkoutSetRecord(
          uuid: setId,
          exerciseUuid: exerciseId,
          position: _integer(row['position'], max: 10000),
          kind: kind,
          status: status,
          reps: row['reps'] == null ? null : _integer(row['reps'], max: 10000),
          loadGrams: row['load_grams'] == null
              ? null
              : _integer(row['load_grams'], max: 100000000),
          inputUnit: unit,
          rpe: rpe,
          completedAtUtc: completion,
        );
        try {
          workoutSet.validate();
        } catch (_) {
          _invalid('invalid_set');
        }
        sets.add(workoutSet);
      }
    }
    return RemoteWorkoutSnapshot(
      uuid: workoutId,
      name: name,
      startedAtUtc: start,
      completedAtUtc: finish,
      originalOffsetMinutes: offset,
      exercises: List.unmodifiable(exercises),
      sets: List.unmodifiable(sets),
    );
  }
}


/// Versioned, owner-scoped point lookup for an explicitly reviewed conflict.
/// A missing row is different from a tombstone and must never be synthesized
/// into a new upsert/deletion without the user's choice.
class WorkoutRemoteReview {
  const WorkoutRemoteReview({required this.cursorEpoch, required this.change});

  final String cursorEpoch;
  final RemoteWorkoutChange? change;

  static String validateWorkoutId(String value) => _id(value);

  static WorkoutRemoteReview decode(Object? raw, String workoutId) {
    final id = _id(workoutId);
    final body = _map(raw, const {
      'schema_version',
      'cursor_epoch',
      'change',
    });
    if (body['schema_version'] != 1) _invalid('invalid_schema_version');
    final epoch = _id(body['cursor_epoch']);
    final row = body['change'];
    if (row == null) {
      return WorkoutRemoteReview(cursorEpoch: epoch, change: null);
    }
    // Reuse the exact strict change/DTO decoder used for paged restores.
    final change = _map(row, _changeFields);
    if (_id(change['workout_id']) != id) {
      _invalid('workout_id_mismatch');
    }
    final decoded = WorkoutRestorePage.decode(
      {
        'schema_version': 1,
        'cursor_epoch': epoch,
        'cursor_reset': false,
        'next_cursor': change['change_seq'],
        'has_more': false,
        'changes': [change],
      },
      afterSeq: 0,
      limit: 1,
      requestedEpoch: epoch,
    );
    return WorkoutRemoteReview(
      cursorEpoch: epoch,
      change: decoded.changes.single,
    );
  }
}
