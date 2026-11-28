import 'dart:convert';
import 'dart:io';

import 'package:beyondrep/features/sync/workout_restore_feed.dart';
import 'package:beyondrep/features/watch/domain/watch_message.dart';
import 'package:beyondrep/features/watch/domain/workout_event_v2.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:flutter_test/flutter_test.dart';

List<File> _files(String dir) =>
    Directory('../../contracts/$dir')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

Map<String, Object?> _read(File f) =>
    jsonDecode(f.readAsStringSync()) as Map<String, Object?>;

String _name(File f) => f.uri.pathSegments.last;

void main() {
  group('workout_sync v2', () {
    test('valid fixtures round-trip', () {
      final files = _files('workout_sync/v2/fixtures/valid');
      expect(files.length, greaterThanOrEqualTo(15));
      for (final f in files) {
        final json = _read(f);
        expect(
          WorkoutEventV2.fromJson(json).toJson(),
          equals(json),
          reason: _name(f),
        );
      }
    });

    test('invalid fixtures are rejected', () {
      final files = _files('workout_sync/v2/fixtures/invalid');
      expect(files.length, greaterThanOrEqualTo(14));
      for (final f in files) {
        expect(
          () => WorkoutEventV2.fromJson(_read(f)),
          throwsA(isA<WatchContractException>()),
          reason: _name(f),
        );
      }
    });

    test('rejects v1 envelope with unsupported_version', () {
      final json = _read(
        File('../../contracts/workout_sync/v1/fixtures/valid/set_logged.json'),
      );
      expect(
        () => WorkoutEventV2.fromJson(json),
        throwsA(
          isA<WatchContractException>().having(
            (e) => e.code,
            'code',
            'unsupported_version',
          ),
        ),
      );
    });
  });

  group('watch_link v1', () {
    test('valid fixtures round-trip', () {
      final files = _files('watch_link/v1/fixtures/valid');
      expect(files.length, greaterThanOrEqualTo(10));
      for (final f in files) {
        final json = _read(f);
        expect(
          WatchMessage.fromJson(json).toJson(),
          equals(json),
          reason: _name(f),
        );
      }
    });

    test('invalid fixtures are rejected', () {
      final files = _files('watch_link/v1/fixtures/invalid');
      expect(files.length, greaterThanOrEqualTo(20));
      for (final f in files) {
        expect(
          () => WatchMessage.fromJson(_read(f)),
          throwsA(isA<WatchContractException>()),
          reason: _name(f),
        );
      }
    });

    test('workout_health decodes into a typed message', () {
      WatchMessage read(String name) => WatchMessage.fromJson(
        _read(File('../../contracts/watch_link/v1/fixtures/valid/$name.json')),
      );
      final full = read('workout_health') as WorkoutHealth;
      expect(full.type, 'workout_health');
      expect(full.workoutId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
      expect(full.heartRate.map((p) => p.bpm), [71, 84, 96]);
      expect(full.heartRate.first.atUtc, '2026-10-23T11:00:00Z');
      expect(full.totalKcal, 312.5);
      final minimal = read('workout_health_minimal') as WorkoutHealth;
      expect(minimal.heartRate, isEmpty);
      expect(minimal.totalKcal, isNull);
      expect(minimal.bodyJson.containsKey('total_kcal'), isFalse);
      final ack = read('ack_not_written') as Ack;
      expect(ack.reason, 'not_written');
    });

    test('workout_health invalid fixtures fail for their reason', () {
      void rejects(String name, String code) => expect(
        () => WatchMessage.fromJson(
          _read(
            File('../../contracts/watch_link/v1/fixtures/invalid/$name.json'),
          ),
        ),
        throwsA(
          isA<WatchContractException>().having((e) => e.code, 'code', code),
        ),
        reason: name,
      );
      rejects('workout_health_bpm_zero', 'invalid_value');
      rejects('workout_health_sample_outside', 'invalid_value');
      rejects('workout_health_unsorted', 'invalid_value');
      rejects('workout_health_extra_field', 'unknown_key');
      rejects('ack_not_written_stored', 'invalid_value');
    });

    test('workout_health bounds follow the schema', () {
      Map<String, Object?> base() => _read(
        File(
          '../../contracts/watch_link/v1/fixtures/valid/workout_health.json',
        ),
      );
      void rejects(void Function(Map<String, Object?> body) edit, String why) {
        final json = base();
        edit(json['body']! as Map<String, Object?>);
        expect(
          () => WatchMessage.fromJson(json),
          throwsA(isA<WatchContractException>()),
          reason: why,
        );
      }

      rejects((b) => b['total_kcal'] = 0, 'zero kcal');
      rejects((b) => b['total_kcal'] = 10001, 'kcal above the ceiling');
      rejects((b) {
        ((b['heart_rate']! as List).first as Map)['bpm'] = 24;
      }, 'bpm below 25');
      rejects((b) {
        ((b['heart_rate']! as List).first as Map)['bpm'] = 251;
      }, 'bpm above 250');
      rejects((b) {
        ((b['heart_rate']! as List).first as Map)['bpm'] = 70.5;
      }, 'fractional bpm');
      rejects(
        (b) => b['heart_rate'] = List.generate(
          601,
          (_) => {'at_utc': '2026-10-23T11:00:00Z', 'bpm': 70},
        ),
        '601 samples',
      );
      rejects((b) => b['end_utc'] = b['start_utc'], 'end not after start');
    });

    test('session_state live fields decode into typed values', () {
      SessionState read(String name) => WatchMessage.fromJson(
        _read(File('../../contracts/watch_link/v1/fixtures/valid/$name.json')),
      ) as SessionState;
      final paused = read('session_state_paused');
      expect(paused.status, 'paused');
      expect(paused.pausedAtUtc, isNotNull);
      expect(paused.pausedSeconds, 45);
      expect(read('session_state_ended').endReason, 'completed');
      final applied = read('session_state_applied_rejected');
      expect(applied.appliedCommandIds, hasLength(2));
      expect(applied.rejectedCommands.first.reason, 'unknown_set');
      final add = WatchMessage.fromJson(
        _read(
          File(
            '../../contracts/watch_link/v1/fixtures/valid/'
            'session_command_add_set.json',
          ),
        ),
      ) as SessionCommand;
      expect(add.command, 'add_set');
      expect(add.exerciseId, isNotNull);
    });

    test('workout_link, join and a phone-owned state decode', () {
      WatchMessage read(String name) => WatchMessage.fromJson(
        _read(File('../../contracts/watch_link/v1/fixtures/valid/$name.json')),
      );
      final link = read('workout_link') as WorkoutLink;
      expect(link.workoutId, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
      expect(link.healthkitWorkoutUuid, 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
      final join = read('join') as JoinMessage;
      expect(join.sessionId, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
      final any = read('join_any') as JoinMessage;
      expect(any.sessionId, isNull);
      expect(any.bodyJson, isEmpty);
      expect((read('session_state_phone') as SessionState).owner, 'phone');
    });

    test('completed_workout program_day round-trips', () {
      final json = _read(
        File(
          '../../contracts/watch_link/v1/fixtures/valid/'
          'completed_workout_program_day.json',
        ),
      );
      final message = WatchMessage.fromJson(json) as CompletedWorkout;
      final day =
          (json['body']! as Map<String, Object?>)['program_day']!
              as Map<String, Object?>;
      expect(message.programDay!.programId, day['program_id']);
      expect(message.programDay!.planId, day['plan_id']);
      expect(message.programDay!.localDate, day['local_date']);
      expect(message.toJson(), equals(json));
    });

    test('completed_workout without program_day has none', () {
      final json = _read(
        File(
          '../../contracts/watch_link/v1/fixtures/valid/completed_workout.json',
        ),
      );
      final message = WatchMessage.fromJson(json) as CompletedWorkout;
      expect(message.programDay, isNull);
      expect(message.toJson(), equals(json));
    });

    test('completed cases decode and pass parseWorkout', () {
      final files = _files('watch_link/v1/cases/completed');
      expect(files.length, greaterThanOrEqualTo(2));
      for (final f in files) {
        final c = _read(f);
        for (final e in (c['events']! as List)) {
          WorkoutEventV2.fromJson(e as Map<String, Object?>);
        }
        final expected = c['expected']! as Map<String, Object?>;
        final message = WatchMessage.fromJson(expected);
        expect(message, isA<CompletedWorkout>(), reason: _name(f));
        final workout =
            (expected['body']! as Map<String, Object?>)['workout']!
                as Map<String, Object?>;
        final snapshot = WorkoutRestorePage.parseWorkout(
          workout,
          workoutId: workout['workout_id']! as String,
          origins: {WorkoutOrigin.watch},
        );
        expect(snapshot.uuid, workout['workout_id'], reason: _name(f));
      }
    });

    test('session_state cases decode and round-trip', () {
      final files = _files('watch_link/v1/cases/session_state');
      expect(files.length, greaterThanOrEqualTo(4));
      for (final f in files) {
        final c = _read(f);
        for (final e in (c['events']! as List)) {
          WorkoutEventV2.fromJson(e as Map<String, Object?>);
        }
        final expected = c['expected']! as Map<String, Object?>;
        expect(
          WatchMessage.fromJson(expected).toJson(),
          equals(expected),
          reason: _name(f),
        );
      }
    });

    test('replay case events all decode', () {
      for (final f in _files('watch_link/v1/cases/replay')) {
        for (final e in (_read(f)['events']! as List)) {
          WorkoutEventV2.fromJson(e as Map<String, Object?>);
        }
      }
    });
  });
}
