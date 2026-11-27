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

    test('replay case events all decode', () {
      for (final f in _files('watch_link/v1/cases/replay')) {
        for (final e in (_read(f)['events']! as List)) {
          WorkoutEventV2.fromJson(e as Map<String, Object?>);
        }
      }
    });
  });
}
