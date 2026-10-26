import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/units/load_units.dart';
import 'package:northstar_health/features/sync/workout_restore_feed.dart';
import 'package:northstar_health/features/workouts/domain/workout_models.dart';

const epochA = '10000000-0000-4000-8000-0000000000a1';
const epochB = '10000000-0000-4000-8000-0000000000b2';
const workoutId = '20000000-0000-4000-8000-000000000001';
const exerciseId = '20000000-0000-4000-8000-000000000002';
const setId = '20000000-0000-4000-8000-000000000003';

Map<String, dynamic> snapshot() => {
  'schema_version': 1,
  'workout_id': workoutId,
  'origin': 'northstar_phone',
  'status': 'completed',
  'name': 'Strength day',
  'started_at_utc': '2026-10-25T05:00:00Z',
  'completed_at_utc': '2026-10-25T06:00:00Z',
  'original_offset_minutes': 330,
  'exercises': [
    {
      'id': exerciseId,
      'name': 'Rows',
      'muscle': 'Back',
      'equipment': 'Cable',
      'position': 0,
      'sets': [
        {
          'id': setId,
          'position': 0,
          'kind': 'working',
          'status': 'completed',
          'reps': 10,
          'load_grams': 15000,
          'input_unit': 'kg',
          'rpe': 8.5,
          'completed_at_utc': '2026-10-25T05:20:00Z',
        },
      ],
    },
  ],
};

// Simulate JSON-decoded RPC payloads so nested maps/lists accept nulls.
Map<String, dynamic> mutableSnapshot() =>
    jsonDecode(jsonEncode(snapshot())) as Map<String, dynamic>;

Map<String, dynamic> change({
  bool deleted = false,
  int seq = 3,
  int revision = 2,
}) => {
  'workout_id': workoutId,
  'server_revision': revision,
  'change_seq': seq,
  'deleted': deleted,
  'payload': deleted ? null : snapshot(),
};

Map<String, dynamic> page({
  bool reset = false,
  String epoch = epochA,
  int next = 3,
  bool more = false,
  List<dynamic>? changes,
}) => {
  'schema_version': 1,
  'cursor_epoch': epoch,
  'cursor_reset': reset,
  'next_cursor': next,
  'has_more': more,
  'changes': changes ?? [change()],
};

WorkoutRestorePage decode(
  Map<String, dynamic> raw, {
  int after = 0,
  String? epoch = epochA,
  int limit = 100,
}) => WorkoutRestorePage.decode(
  raw,
  afterSeq: after,
  requestedEpoch: epoch,
  limit: limit,
);

void main() {
  test('decodes a completed workout and immutable nested snapshots', () {
    final decoded = decode(page());
    expect(decoded.cursorEpoch, epochA);
    expect(decoded.nextCursor, 3);
    expect(decoded.cursorReset, false);
    expect(decoded.changes, hasLength(1));
    final change = decoded.changes.single;
    expect(change.serverRevision, 2);
    expect(change.snapshot, isNot(isA<WorkoutSessionRecord>()));
    expect(change.snapshot!.uuid, workoutId);
    expect(change.snapshot!.status, WorkoutStatus.completed);
    expect(change.snapshot!.originalOffsetMinutes, 330);
    expect(change.snapshot!.sets.single.inputUnit, LoadUnit.kg);
    expect(change.snapshot!.sets.single.loadGrams, 15000);
    expect(change.snapshot!.sets.single.rpe, 8.5);
    expect(() => decoded.changes.clear(), throwsUnsupportedError);
    expect(() => change.snapshot!.sets.clear(), throwsUnsupportedError);
  });

  test('bootstrap without epoch allowed only at cursor zero', () {
    expect(decode(page(), epoch: null).cursorEpoch, epochA);
    expect(
      () => decode(page(next: 5, changes: const []), after: 5, epoch: null),
      throwsFormatException,
    );
  });

  test('accepts empty non-reset continuation without cursor advancement', () {
    final decoded = decode(page(next: 5, changes: const []), after: 5);
    expect(decoded.nextCursor, 5);
    expect(decoded.changes, isEmpty);
  });

  test('reset accepts new epoch and must have empty page plus zero cursor', () {
    final response = page(reset: true, epoch: epochB, next: 0, changes: []);
    final result = decode(response, after: 8);
    expect(result.cursorReset, true);
    expect(result.cursorEpoch, epochB);
    expect(result.nextCursor, 0);
    expect(
      () => decode(page(reset: true, epoch: epochB), after: 8),
      throwsFormatException,
    );
    expect(
      () => decode(page(reset: true, epoch: epochB, next: 8, changes: [])),
      throwsFormatException,
    );
    expect(
      () => decode(
        page(reset: true, epoch: epochB, next: 0, changes: [], more: true),
      ),
      throwsFormatException,
    );
  });

  test(
    'rejects changed epoch without cursor_reset even when cursor overtaken',
    () {
      // A stale cursor 8 is lower than the new database's seq 10. Epoch
      // mismatch must not be silently processed as a regular continuation.
      expect(
        () => decode(
          page(epoch: epochB, next: 10, changes: [change(seq: 10)]),
          after: 8,
        ),
        throwsFormatException,
      );
    },
  );

  test('rejects missing or unknown response keys and invalid types', () {
    final missing = page()..remove('has_more');
    expect(() => decode(missing), throwsFormatException);
    final extra = page()..['user_id'] = workoutId;
    expect(() => decode(extra), throwsFormatException);
    expect(() => decode(page()..['schema_version'] = 2), throwsFormatException);
    expect(
      () => decode(page()..['cursor_epoch'] = 'abc'),
      throwsFormatException,
    );
    expect(() => decode(page()..['has_more'] = 'false'), throwsFormatException);
    expect(() => decode(page()..['next_cursor'] = 3.0), throwsFormatException);
  });

  test('pagination has strict monotonic sequence and final item cursor', () {
    expect(() => decode(page(next: 4)), throwsFormatException);
    expect(() => decode(page(), after: 3), throwsFormatException);
    expect(
      () => decode(page(more: true, changes: [change()]), limit: 2),
      throwsFormatException,
    );
    expect(
      () => decode(page(changes: [change(), change(seq: 4)], next: 4)),
      throwsFormatException,
    );
    expect(
      () =>
          decode(page(changes: [change(), change(seq: 4)], next: 4), limit: 1),
      throwsFormatException,
    );
    expect(decode(page(more: true), limit: 1).hasMore, true);
    expect(decode(page(), limit: 1).hasMore, false);
  });

  test('deletion tombstone must not include payload and is not a workout', () {
    final deleted = decode(page(changes: [change(deleted: true)]));
    expect(deleted.changes.single.deleted, true);
    expect(deleted.changes.single.snapshot, isNull);
    final invalid = change(deleted: true)..['payload'] = snapshot();
    expect(() => decode(page(changes: [invalid])), throwsFormatException);
    expect(
      () => decode(page(changes: [change()..['payload'] = null])),
      throwsFormatException,
    );
  });

  test('rejects missing and unexpected nested payload fields', () {
    final missing = snapshot()..remove('original_offset_minutes');
    expect(
      () => decode(page(changes: [change()..['payload'] = missing])),
      throwsFormatException,
    );
    final raw = snapshot()..['heart_rate'] = 100;
    expect(
      () => decode(page(changes: [change()..['payload'] = raw])),
      throwsFormatException,
    );
    final changeWithOwner = change()..['user_id'] = workoutId;
    expect(
      () => decode(page(changes: [changeWithOwner])),
      throwsFormatException,
    );
  });

  test('rejects a forged workout id, origin and non-completed status', () {
    for (final entry in <String, Object>{
      'workout_id': exerciseId,
      'origin': 'watch',
      'status': 'inProgress',
    }.entries) {
      final raw = snapshot()..[entry.key] = entry.value;
      expect(
        () => decode(page(changes: [change()..['payload'] = raw])),
        throwsFormatException,
      );
    }
  });

  test(
    'accepts server-valid timestamp offsets and converts instants to UTC',
    () {
      final raw = mutableSnapshot()
        ..['started_at_utc'] = '2026-10-25T05:00:00+05:30'
        ..['completed_at_utc'] = '2026-10-25T06:00:00+05:30';
      final ex = (raw['exercises'] as List).single as Map<String, dynamic>;
      final set = (ex['sets'] as List).single as Map<String, dynamic>;
      set['completed_at_utc'] = '2026-10-25T05:20:00+05:30';
      final result = decode(page(changes: [change()..['payload'] = raw]));
      expect(
        result.changes.single.snapshot!.startedAtUtc.toIso8601String(),
        '2026-10-24T23:30:00.000Z',
      );
      expect(
        result.changes.single.snapshot!.sets.single.completedAtUtc!
            .toIso8601String(),
        '2026-10-24T23:50:00.000Z',
      );
    },
  );

  test('rejects malformed or non-calendar timestamps and reversed times', () {
    for (final invalidTime in [
      '2026-99-25T05:00:00Z',
      '2026-10-25T99:00:00Z',
      '2026-02-30T05:00:00Z',
      '2026-10-25T05:00:00+05:99',
    ]) {
      final raw = snapshot()..['started_at_utc'] = invalidTime;
      expect(
        () => decode(page(changes: [change()..['payload'] = raw])),
        throwsFormatException,
      );
    }
    final reversed = snapshot()..['completed_at_utc'] = '2026-10-25T04:00:00Z';
    expect(
      () => decode(page(changes: [change()..['payload'] = reversed])),
      throwsFormatException,
    );
  });

  test('decodes server pgTAP fixture without optional exercise or set keys', () {
    // Exact completed-workout JSON shape in
    // supabase/tests/workout_sync.test.sql (northstar.fixture).
    const serverFixture =
        '{"schema_version":1,"workout_id":"00000000-0000-4000-8000-000000000101","origin":"northstar_phone","status":"completed","name":"Rows","started_at_utc":"2026-10-25T05:00:00Z","completed_at_utc":"2026-10-25T06:00:00Z","original_offset_minutes":330,"exercises":[{"id":"00000000-0000-4000-8000-000000000201","name":"Seated row","position":0,"sets":[{"id":"00000000-0000-4000-8000-000000000301","position":0,"kind":"working","status":"completed","input_unit":"kg","reps":8,"load_grams":60000,"completed_at_utc":"2026-10-25T05:08:00Z"},{"id":"00000000-0000-4000-8000-000000000302","position":1,"kind":"warmup","status":"completed","input_unit":"kg","reps":12,"load_grams":20000,"completed_at_utc":"2026-10-25T05:09:00Z"},{"id":"00000000-0000-4000-8000-000000000303","position":2,"kind":"working","status":"completed","input_unit":"kg","reps":10,"load_grams":null,"completed_at_utc":"2026-10-25T05:10:00Z"},{"id":"00000000-0000-4000-8000-000000000304","position":3,"kind":"working","status":"completed","input_unit":"kg","reps":5,"load_grams":0,"completed_at_utc":"2026-10-25T05:11:00Z"}]}]}';
    final raw = jsonDecode(serverFixture) as Map<String, dynamic>;
    final remoteChange = change()
      ..['workout_id'] = raw['workout_id']
      ..['payload'] = raw;
    final decoded = decode(page(changes: [remoteChange])).changes.single;
    expect(decoded.snapshot!.sets.length, 4);
    expect(decoded.snapshot!.exercises.single.muscleSnapshot, '');
    expect(decoded.snapshot!.exercises.single.equipmentSnapshot, '');
    expect(decoded.snapshot!.sets.first.rpe, isNull);
    expect(decoded.snapshot!.sets[2].loadGrams, isNull);
    expect(decoded.serverRevision, 2);
    expect(decoded.snapshot, isNot(isA<WorkoutSessionRecord>()));
  });

  test('separate exercise and set UUID domains may share an ID', () {
    final raw = mutableSnapshot();
    final exercise = (raw['exercises'] as List).first as Map<String, dynamic>;
    final set = (exercise['sets'] as List).first as Map<String, dynamic>;
    set['id'] = exerciseId;
    final result = decode(page(changes: [change()..['payload'] = raw]));
    expect(result.changes.single.snapshot!.sets.single.uuid, exerciseId);
  });

  test('set IDs repeated across two exercises remain invalid', () {
    final raw = mutableSnapshot();
    final exercises = raw['exercises'] as List;
    final copy =
        jsonDecode(jsonEncode(exercises.first)) as Map<String, dynamic>;
    copy['id'] = '20000000-0000-4000-8000-000000000020';
    exercises.add(copy);
    expect(
      () => decode(page(changes: [change()..['payload'] = raw])),
      throwsFormatException,
    );
  });

  test('nested health fields are forbidden even when required keys exist', () {
    final raw = mutableSnapshot();
    final exercise = (raw['exercises'] as List).first as Map<String, dynamic>;
    exercise['heart_rate'] = 100;
    expect(
      () => decode(page(changes: [change()..['payload'] = raw])),
      throwsFormatException,
    );
    exercise.remove('heart_rate');
    final set = (exercise['sets'] as List).first as Map<String, dynamic>;
    set['hrv'] = 44;
    expect(
      () => decode(page(changes: [change()..['payload'] = raw])),
      throwsFormatException,
    );
  });

  test('same-epoch reset is valid for an ahead-of-server cursor', () {
    final response = page(reset: true, next: 0, changes: []);
    final result = decode(response, after: 10, epoch: epochA);
    expect(result.cursorReset, true);
    expect(result.cursorEpoch, epochA);
  });

  test('request bounds reject invalid epochs, limits and cursor values', () {
    for (final limit in [0, -1, 201]) {
      expect(() => decode(page(), limit: limit), throwsFormatException);
    }
    for (final cursor in [-1]) {
      expect(() => decode(page(), after: cursor), throwsFormatException);
    }
    expect(() => decode(page(), epoch: 'not-a-uuid'), throwsFormatException);
    expect(() => decode(page(), after: 1, epoch: null), throwsFormatException);
    expect(decode(page(), limit: 200).nextCursor, 3);
    const maxCursor = 9223372036854775807;
    expect(
      decode(
        page(next: maxCursor, changes: []),
        after: maxCursor,
      ).nextCursor,
      maxCursor,
    );
  });

  test('rejects malformed exercise and set content', () {
    final invalidSet = mutableSnapshot();
    final item =
        (invalidSet['exercises'] as List).first as Map<String, dynamic>;
    final set = (item['sets'] as List).first as Map<String, dynamic>;
    set['rpe'] = 10.5;
    expect(
      () => decode(page(changes: [change()..['payload'] = invalidSet])),
      throwsFormatException,
    );
    final invalidMissingReps = mutableSnapshot();
    final exercise =
        (invalidMissingReps['exercises'] as List).first as Map<String, dynamic>;
    final row = (exercise['sets'] as List).first as Map<String, dynamic>;
    row['reps'] = null;
    expect(
      () => decode(page(changes: [change()..['payload'] = invalidMissingReps])),
      throwsFormatException,
    );
  });

  test('rejects duplicate IDs within each domain and oversized payloads', () {
    final duplicated = mutableSnapshot();
    final ex = (duplicated['exercises'] as List).first as Map<String, dynamic>;
    (ex['sets'] as List).add(
      Map<String, dynamic>.from((ex['sets'] as List).first as Map),
    );
    expect(
      () => decode(page(changes: [change()..['payload'] = duplicated])),
      throwsFormatException,
    );
    // Every value below is valid under the server's per-field limits.
    // The only violation is the *aggregate* encoded size over 64 KiB.
    final oversized = mutableSnapshot();
    final exercises = oversized['exercises'] as List;
    exercises.clear();
    for (var ex = 0; ex < 5; ex++) {
      final sets = <Map<String, dynamic>>[];
      for (var index = 0; index < 150; index++) {
        final id = ex * 150 + index + 1;
        sets.add({
          'id':
              '30000000-0000-4000-8000-${id.toRadixString(16).padLeft(12, '0')}',
          'position': index,
          'kind': 'working',
          'status': 'completed',
          'input_unit': 'kg',
          'reps': 12,
          'load_grams': 60000,
          'completed_at_utc': '2026-10-25T05:20:00Z',
        });
      }
      exercises.add({
        'id':
            '20000000-0000-4000-8000-${(ex + 1).toRadixString(16).padLeft(12, '0')}',
        'name': 'Valid exercise',
        'position': ex,
        'sets': sets,
      });
    }
    expect(utf8.encode(jsonEncode(oversized)).length, greaterThan(65536));
    expect(
      () => decode(page(changes: [change()..['payload'] = oversized])),
      throwsFormatException,
    );
    final malformedJson = jsonDecode(jsonEncode(snapshot())) as Map;
    malformedJson['exercises'] = 'not a list';
    expect(
      () => decode(page(changes: [change()..['payload'] = malformedJson])),
      throwsFormatException,
    );
  });
  test('PostgreSQL UUID spellings normalize to canonical local identities', () {
    const canonical = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
    for (final spelling in [
      'A0EEBC99-9C0B-4EF8-BB6D-6BB9BD380A11',
      '{A0EEBC99-9C0B-4EF8-BB6D-6BB9BD380A11}',
      'a0eebc999c0b4ef8bb6d6bb9bd380a11',
      'a0ee-bc99-9c0b-4ef8-bb6d-6bb9-bd38-0a11',
      '{a0ee-bc99-9c0b4ef8-bb6d6bb9-bd380a11}',
    ]) {
      final raw = mutableSnapshot();
      final ex = (raw['exercises'] as List).single as Map<String, dynamic>;
      ex['id'] = spelling;
      final parsed = decode(page(changes: [change()..['payload'] = raw]));
      expect(parsed.changes.single.snapshot!.exercises.single.uuid, canonical);
      final set = (ex['sets'] as List).single as Map<String, dynamic>;
      set['id'] = spelling;
      final withSet = decode(page(changes: [change()..['payload'] = raw]));
      expect(withSet.changes.single.snapshot!.sets.single.uuid, canonical);
    }
  });

  test('canonical collision within set domain stops page with reason code', () {
    final raw = mutableSnapshot();
    final ex = (raw['exercises'] as List).single as Map<String, dynamic>;
    final sets = ex['sets'] as List;
    final duplicate = Map<String, dynamic>.from(sets.single as Map);
    duplicate['id'] = setId.toUpperCase().replaceAll('-', '');
    duplicate['position'] = 1;
    sets.add(duplicate);
    expect(
      () => decode(page(changes: [change()..['payload'] = raw])),
      throwsA(
        isA<RestoreContractException>()
            .having((error) => error.code, 'code', 'duplicate_set_id')
            .having((error) => error.request, 'request', false),
      ),
    );
  });

  test('canonical collision within exercise domain stops page safely', () {
    final raw = mutableSnapshot();
    final exercises = raw['exercises'] as List;
    final copy =
        jsonDecode(jsonEncode(exercises.single)) as Map<String, dynamic>;
    copy['id'] = exerciseId.toUpperCase().replaceAll('-', '');
    copy['position'] = 1;
    copy['sets'] = <Map<String, dynamic>>[];
    exercises.add(copy);
    expect(
      () => decode(page(changes: [change()..['payload'] = raw])),
      throwsA(
        isA<RestoreContractException>()
            .having((error) => error.code, 'code', 'duplicate_exercise_id')
            .having((error) => error.request, 'request', false),
      ),
    );
  });

  test('24:00 and leap second timestamps normalize to proper UTC instants', () {
    final midnight = mutableSnapshot()
      ..['started_at_utc'] = '2026-10-25T24:00:00+05:30'
      ..['completed_at_utc'] = '2026-10-26T00:05:00+05:30';
    final ex = (midnight['exercises'] as List).single as Map<String, dynamic>;
    final set = (ex['sets'] as List).single as Map<String, dynamic>;
    set['completed_at_utc'] = '2026-10-26T00:02:00+05:30';
    final parsed = decode(page(changes: [change()..['payload'] = midnight]))
        .changes
        .single
        .snapshot!;
    expect(parsed.startedAtUtc.toIso8601String(), '2026-10-25T18:30:00.000Z');

    final leap = mutableSnapshot()
      ..['started_at_utc'] = '2026-10-25T23:59:60Z'
      ..['completed_at_utc'] = '2026-10-26T00:05:00Z';
    final leapEx = (leap['exercises'] as List).single as Map<String, dynamic>;
    final leapSet = (leapEx['sets'] as List).single as Map<String, dynamic>;
    leapSet['completed_at_utc'] = '2026-10-26T00:01:00Z';
    final parsedLeap = decode(page(changes: [change()..['payload'] = leap]))
        .changes
        .single
        .snapshot!;
    expect(
      parsedLeap.startedAtUtc.toIso8601String(),
      '2026-10-26T00:00:00.000Z',
    );
  });

  test('invalid near-midnight input keeps precise non-PII failure code', () {
    for (final invalid in [
      '2026-10-25T24:00:01Z',
      '2026-10-25T24:00:00.000001Z',
      '2026-10-25T24:01:00Z',
      '2026-10-25T23:59:61Z',
      '2026-02-30T24:00:00Z',
    ]) {
      final raw = mutableSnapshot()..['started_at_utc'] = invalid;
      expect(
        () => decode(page(changes: [change()..['payload'] = raw])),
        throwsA(
          isA<RestoreContractException>()
              .having((error) => error.code, 'code', 'invalid_timestamp')
              .having((error) => error.request, 'request', false),
        ),
      );
    }
  });

  test('bad page and oversized payload supply safe reason codes', () {
    final extra = page()..['health_metrics'] = 'do-not-log-this-content';
    expect(
      () => decode(extra),
      throwsA(
        isA<RestoreContractException>()
            .having((error) => error.code, 'code', 'unsupported_field')
            .having(
              (error) => error.message.contains('do-not-log'),
              'privacy',
              false,
            ),
      ),
    );
    final badEpoch = page(epoch: epochB);
    expect(
      () => decode(badEpoch),
      throwsA(
        isA<RestoreContractException>().having(
          (error) => error.code,
          'code',
          'epoch_mismatch',
        ),
      ),
    );
  });

  test('leap seconds at midday and with fractions preserve instants', () {
    for (final entry in <String, String>{
      '2026-10-25T12:34:60Z': '2026-10-25T12:35:00.000Z',
      '2026-10-25T12:34:60.250000+05:30': '2026-10-25T07:05:00.250Z',
    }.entries) {
      final raw = mutableSnapshot()
        ..['started_at_utc'] = entry.key
        ..['completed_at_utc'] = '2026-10-25T12:40:00Z';
      final ex = (raw['exercises'] as List).single as Map<String, dynamic>;
      final set = (ex['sets'] as List).single as Map<String, dynamic>;
      set['completed_at_utc'] = '2026-10-25T12:36:00Z';
      final actual = decode(page(changes: [change()..['payload'] = raw]))
          .changes
          .single
          .snapshot!
          .startedAtUtc
          .toIso8601String();
      expect(actual, entry.value);
    }
  });

  test('unpaired UUID braces are rejected with invalid_uuid', () {
    for (final invalid in ['{$exerciseId', '$exerciseId}']) {
      final raw = mutableSnapshot();
      final ex = (raw['exercises'] as List).single as Map<String, dynamic>;
      ex['id'] = invalid;
      expect(
        () => decode(page(changes: [change()..['payload'] = raw])),
        throwsA(
          isA<RestoreContractException>().having(
            (e) => e.code,
            'code',
            'invalid_uuid',
          ),
        ),
      );
    }
  });

  test('month and day zero are invalid timestamps', () {
    for (final invalid in ['2026-00-25T05:00:00Z', '2026-10-00T05:00:00Z']) {
      final raw = mutableSnapshot()..['started_at_utc'] = invalid;
      expect(
        () => decode(page(changes: [change()..['payload'] = raw])),
        throwsA(
          isA<RestoreContractException>().having(
            (e) => e.code,
            'code',
            'invalid_timestamp',
          ),
        ),
      );
    }
  });

  test('bad time zone offset has distinct code', () {
    for (final offset in ['+24:00', '-23:60', '+99:01']) {
      final raw = mutableSnapshot()
        ..['started_at_utc'] = '2026-10-25T05:00:00$offset';
      expect(
        () => decode(page(changes: [change()..['payload'] = raw])),
        throwsA(
          isA<RestoreContractException>().having(
            (e) => e.code,
            'code',
            'invalid_timezone_offset',
          ),
        ),
      );
    }
  });

  test('set validation codes distinguish kind status unit rpe and time', () {
    void check(String field, Object? value, String code) {
      final raw = mutableSnapshot();
      final ex = (raw['exercises'] as List).single as Map<String, dynamic>;
      final set = (ex['sets'] as List).single as Map<String, dynamic>;
      set[field] = value;
      expect(
        () => decode(page(changes: [change()..['payload'] = raw])),
        throwsA(
          isA<RestoreContractException>().having((e) => e.code, 'code', code),
        ),
      );
    }

    check('kind', 'dropset', 'invalid_set_kind');
    check('status', 'failed', 'invalid_set_status');
    check('input_unit', 'stones', 'invalid_set_unit');
    check('rpe', 10.5, 'invalid_set_rpe');
    check('reps', null, 'invalid_set_completion');
    check('completed_at_utc', null, 'invalid_set_completion');
    check('completed_at_utc', '2026-10-25T04:00:00Z', 'invalid_set_time_order');
  });

  test('workout validation codes distinguish offset and time order', () {
    final badOffset = mutableSnapshot()..['original_offset_minutes'] = 900;
    final badTime = mutableSnapshot()
      ..['completed_at_utc'] = '2026-10-25T04:00:00Z';
    for (final entry in {
      'invalid_original_offset': badOffset,
      'invalid_workout_time_order': badTime,
    }.entries) {
      expect(
        () => decode(page(changes: [change()..['payload'] = entry.value])),
        throwsA(
          isA<RestoreContractException>().having(
            (e) => e.code,
            'code',
            entry.key,
          ),
        ),
      );
    }
  });

  test('collection overflows have distinct stable codes', () {
    expect(
      () => decode(page(changes: List<dynamic>.filled(201, null))),
      throwsA(
        isA<RestoreContractException>().having(
          (e) => e.code,
          'code',
          'too_many_changes',
        ),
      ),
    );
    final tooManyEx = mutableSnapshot()
      ..['exercises'] = List<dynamic>.filled(121, null);
    expect(
      () => decode(page(changes: [change()..['payload'] = tooManyEx])),
      throwsA(
        isA<RestoreContractException>().having(
          (e) => e.code,
          'code',
          'too_many_exercises',
        ),
      ),
    );
    final tooManySets = mutableSnapshot();
    final ex =
        (tooManySets['exercises'] as List).single as Map<String, dynamic>;
    ex['sets'] = List<dynamic>.filled(301, null);
    expect(
      () => decode(page(changes: [change()..['payload'] = tooManySets])),
      throwsA(
        isA<RestoreContractException>().having(
          (e) => e.code,
          'code',
          'too_many_sets',
        ),
      ),
    );
  });

  test('page and tombstone violations expose specific codes', () {
    final flags = page()..['has_more'] = 'yes';
    expect(
      () => decode(flags),
      throwsA(
        isA<RestoreContractException>().having(
          (e) => e.code,
          'code',
          'invalid_page_flags',
        ),
      ),
    );
    expect(
      () => decode(page(next: 4)),
      throwsA(
        isA<RestoreContractException>().having(
          (e) => e.code,
          'code',
          'invalid_next_cursor',
        ),
      ),
    );
    expect(
      () => decode(page(more: true), limit: 2),
      throwsA(
        isA<RestoreContractException>().having(
          (e) => e.code,
          'code',
          'invalid_page_limit',
        ),
      ),
    );
    final tombstone = change(deleted: true)..['payload'] = snapshot();
    expect(
      () => decode(page(changes: [tombstone])),
      throwsA(
        isA<RestoreContractException>().having(
          (e) => e.code,
          'code',
          'invalid_change_payload',
        ),
      ),
    );
  });
}
