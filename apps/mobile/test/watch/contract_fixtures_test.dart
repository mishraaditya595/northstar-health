import 'dart:convert';
import 'dart:io';

import 'package:beyondrep/features/watch/domain/watch_message.dart';
import 'package:beyondrep/features/watch/domain/workout_event_v2.dart';
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
      expect(files.length, greaterThanOrEqualTo(12));
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
      expect(files.length, greaterThanOrEqualTo(7));
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
      expect(files.length, greaterThanOrEqualTo(8));
      for (final f in files) {
        expect(
          () => WatchMessage.fromJson(_read(f)),
          throwsA(isA<WatchContractException>()),
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
