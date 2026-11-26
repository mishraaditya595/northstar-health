import 'dart:convert';
import 'dart:io';

import 'package:beyondrep/features/catalog/domain/canonical_json.dart';
import 'package:beyondrep/features/catalog/domain/catalog_models.dart';
import 'package:beyondrep/features/catalog/domain/catalog_parser.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> exercise(String id, {String mode = 'reps_load'}) => {
  'id': id,
  'name': 'Name of $id',
  'aliases': ['Alias of $id'],
  'muscleGroup': 'Legs',
  'primaryMuscles': ['quads'],
  'secondaryMuscles': ['glutes'],
  'equipment': ['barbell'],
  'category': 'squat',
  'mode': mode,
  'cues': ['Cue'],
  'status': 'active',
};

Map<String, Object?> validSnapshot() => {
  'schemaVersion': 1,
  'minAppCatalogSchema': 1,
  'release': 3,
  'publishedAt': '2026-11-26T00:00:00Z',
  'provenance': {'source': 's', 'license': 'MPL-2.0', 'attribution': ''},
  'exercises': [
    exercise('builtin.v1.squat'),
    exercise('builtin.v1.plank', mode: 'duration'),
  ],
  'templates': [
    {
      'id': 'tpl.a',
      'name': 'A',
      'description': '',
      'tags': {
        'goal': ['general'],
        'level': 'beginner',
        'equipment': ['barbell'],
      },
      'estimatedMinutes': 40,
      'exercises': [
        {
          'exerciseId': 'builtin.v1.squat',
          'sets': 3,
          'repsMin': 5,
          'repsMax': 8,
          'restSeconds': 90,
        },
        {
          'exerciseId': 'builtin.v1.plank',
          'sets': 3,
          'durationSeconds': 45,
          'restSeconds': 60,
        },
      ],
    },
  ],
  'programs': [
    {
      'id': 'prog.a',
      'name': 'P',
      'description': '',
      'goals': ['general'],
      'level': 'beginner',
      'daysPerWeek': 3,
      'estimatedMinutes': 40,
      'equipment': ['barbell'],
      'week': ['tpl.a', null, 'tpl.a', null, 'tpl.a', null, null],
    },
  ],
};

Map<String, Object?> firstPrescription(Map<String, Object?> s) {
  final template = (s['templates']! as List).first as Map<String, Object?>;
  return (template['exercises']! as List).first as Map<String, Object?>;
}

void expectCode(Object? json, String code, {String? expectedSha256}) {
  expect(
    () => parseCatalogSnapshot(json, expectedSha256: expectedSha256),
    throwsA(isA<CatalogFormatException>().having((e) => e.code, 'code', code)),
  );
}

String releaseOneBody() {
  final sql = File(
    '../../supabase/migrations/20261126000100_catalog_release_1.sql',
  ).readAsStringSync();
  final start = sql.indexOf(r'$catalog$') + r'$catalog$'.length;
  final end = sql.indexOf(r'$catalog$', start);
  return sql.substring(start, end);
}

void main() {
  group('snapshot', () {
    test('parses valid snapshot', () {
      final json = validSnapshot();
      final snapshot = parseCatalogSnapshot(
        json,
        expectedSha256: sha256Hex(canonicalJsonBytes(json)),
      );
      expect(snapshot.release, 3);
      expect(snapshot.schemaVersion, 1);
      expect(snapshot.minAppCatalogSchema, 1);
      expect(snapshot.exercises, hasLength(2));
      expect(snapshot.templates, hasLength(1));
      expect(snapshot.programs, hasLength(1));
      expect(snapshot.sha256, sha256Hex(canonicalJsonBytes(json)));
      final squat = snapshot.exercises.first;
      expect(squat.id, 'builtin.v1.squat');
      expect(squat.aliases, ['Alias of builtin.v1.squat']);
      expect(squat.primaryMuscles, ['quads']);
      expect(squat.retired, isFalse);
    });

    test('parses the published release 1', () {
      final snapshot = parseCatalogSnapshot(jsonDecode(releaseOneBody()));
      expect(snapshot.release, 1);
      expect(snapshot.exercises, hasLength(18));
      expect(
        snapshot.exercises.firstWhere((e) => e.id == 'builtin.v1.plank').mode,
        'duration',
      );
    });

    test('activeExercises hides retired exercises', () {
      final json = validSnapshot();
      (json['templates']! as List).clear();
      (json['programs']! as List).clear();
      (json['exercises']! as List<Object?>).add({
        ...exercise('builtin.v1.old'),
        'status': 'retired',
      });
      final snapshot = parseCatalogSnapshot(json);
      expect(snapshot.exercises, hasLength(3));
      expect(
        snapshot.activeExercises.map((e) => e.id),
        isNot(contains('builtin.v1.old')),
      );
      expect(snapshot.exercises.last.retired, isTrue);
    });

    test('template and program status: missing is active, retired parses', () {
      final plain = parseCatalogSnapshot(validSnapshot());
      expect(plain.templates.single.retired, isFalse);
      expect(plain.programs.single.retired, isFalse);

      final json = validSnapshot();
      ((json['templates']! as List).first as Map<String, Object?>)['status'] =
          'retired';
      ((json['programs']! as List).first as Map<String, Object?>)['status'] =
          'retired';
      final retired = parseCatalogSnapshot(json);
      expect(retired.templates.single.retired, isTrue);
      expect(retired.programs.single.retired, isTrue);

      ((json['templates']! as List).first as Map<String, Object?>)['status'] =
          'active';
      expect(parseCatalogSnapshot(json).templates.single.retired, isFalse);
    });

    test('an unknown template or program status keeps the snapshot and hides '
        'only that item', () {
      for (final key in ['templates', 'programs']) {
        for (final bad in ['archived', 3, '', 'Retired']) {
          final json = validSnapshot();
          ((json[key]! as List).first as Map<String, Object?>)['status'] = bad;
          final snapshot = parseCatalogSnapshot(json);
          expect(snapshot.exercises, hasLength(2), reason: '$key $bad');
          final item = key == 'templates'
              ? snapshot.templates.single.retired
              : snapshot.programs.single.retired;
          expect(item, isTrue, reason: '$key $bad');
        }
      }
    });

    test('an unknown exercise status is still rejected', () {
      final json = validSnapshot();
      ((json['exercises']! as List).first as Map<String, Object?>)['status'] =
          'archived';
      expectCode(json, 'shape');
    });

    test('checksum mismatch', () {
      expectCode(validSnapshot(), 'checksum', expectedSha256: 'a' * 64);
    });

    test('min app schema above the supported one is a schema error', () {
      final json = validSnapshot()
        ..['schemaVersion'] = 2
        ..['minAppCatalogSchema'] = 2;
      expectCode(json, 'schema');
    });

    test('newer schemaVersion with min 1 is accepted and extras ignored', () {
      final json = validSnapshot()
        ..['schemaVersion'] = 2
        ..['minAppCatalogSchema'] = 1
        ..['futureTopLevel'] = {
          'anything': [1, 2],
        };
      ((json['exercises']! as List).first
              as Map<String, Object?>)['futureKey'] =
          'x';
      ((json['templates']! as List).first
              as Map<String, Object?>)['futureKey'] =
          1;
      firstPrescription(json)['futureKey'] = true;
      ((json['programs']! as List).first as Map<String, Object?>)['futureKey'] =
          0;
      final snapshot = parseCatalogSnapshot(json);
      expect(snapshot.schemaVersion, 2);
      expect(snapshot.exercises, hasLength(2));
    });

    test('shape: missing field', () {
      final json = validSnapshot()..remove('exercises');
      expectCode(json, 'shape');
    });

    test('shape: wrong type', () {
      final json = validSnapshot()..['release'] = '3';
      expectCode(json, 'shape');
    });

    test('shape: not an object', () {
      expectCode(<Object?>[], 'shape');
      expectCode(null, 'shape');
    });

    test('shape: double anywhere', () {
      final json = validSnapshot();
      firstPrescription(json)['restSeconds'] = 90.5;
      expectCode(json, 'shape');
    });

    test('shape: unknown mode value', () {
      final json = validSnapshot();
      ((json['exercises']! as List).first as Map<String, Object?>)['mode'] =
          'weird';
      expectCode(json, 'shape');
    });

    test('duplicate id', () {
      final json = validSnapshot();
      (json['exercises']! as List<Object?>).add(exercise('builtin.v1.squat'));
      expectCode(json, 'duplicateId');
    });

    test('duplicate id across kinds', () {
      final json = validSnapshot();
      ((json['programs']! as List).first as Map<String, Object?>)['id'] =
          'tpl.a';
      expectCode(json, 'duplicateId');
    });

    test('reference: unknown exercise in template', () {
      final json = validSnapshot();
      firstPrescription(json)['exerciseId'] = 'builtin.v1.missing';
      expectCode(json, 'reference');
    });

    test('reference: retired exercise in template', () {
      final json = validSnapshot();
      ((json['exercises']! as List).first as Map<String, Object?>)['status'] =
          'retired';
      expectCode(json, 'reference');
    });

    test('reference: unknown template in program week', () {
      final json = validSnapshot();
      (((json['programs']! as List).first as Map<String, Object?>)['week']!
              as List<Object?>)[0] =
          'tpl.missing';
      expectCode(json, 'reference');
    });

    test('range: sets', () {
      for (final bad in [0, 31]) {
        final json = validSnapshot();
        firstPrescription(json)['sets'] = bad;
        expectCode(json, 'range');
      }
    });

    test('range: reps', () {
      final low = validSnapshot();
      firstPrescription(low)['repsMin'] = 0;
      expectCode(low, 'range');
      final high = validSnapshot();
      firstPrescription(high)['repsMax'] = 1001;
      expectCode(high, 'range');
      final inverted = validSnapshot();
      firstPrescription(inverted)
        ..['repsMin'] = 9
        ..['repsMax'] = 8;
      expectCode(inverted, 'range');
    });

    test('range: rest', () {
      for (final bad in [-1, 3601]) {
        final json = validSnapshot();
        firstPrescription(json)['restSeconds'] = bad;
        expectCode(json, 'range');
      }
    });

    test('range: duration', () {
      for (final bad in [0, 3601]) {
        final json = validSnapshot();
        final plank =
            ((json['templates']! as List).first
                    as Map<String, Object?>)['exercises']
                as List<Object?>;
        (plank[1]! as Map<String, Object?>)['durationSeconds'] = bad;
        expectCode(json, 'range');
      }
    });

    test('range: week length', () {
      final json = validSnapshot();
      (((json['programs']! as List).first as Map<String, Object?>)['week']!
              as List<Object?>)
          .removeLast();
      expectCode(json, 'range');
    });

    test('mode: reps on a duration exercise', () {
      final json = validSnapshot();
      final items =
          ((json['templates']! as List).first
                  as Map<String, Object?>)['exercises']
              as List<Object?>;
      (items[1]! as Map<String, Object?>)
        ..remove('durationSeconds')
        ..['repsMin'] = 5
        ..['repsMax'] = 8;
      expectCode(json, 'mode');
    });

    test('mode: seconds on a rep exercise', () {
      final json = validSnapshot();
      firstPrescription(json)
        ..remove('repsMin')
        ..remove('repsMax')
        ..['durationSeconds'] = 30;
      expectCode(json, 'mode');
    });

    test('mode: both reps and seconds', () {
      final json = validSnapshot();
      firstPrescription(json)['durationSeconds'] = 30;
      expectCode(json, 'mode');
    });

    test('mode: neither reps nor seconds', () {
      final json = validSnapshot();
      firstPrescription(json)
        ..remove('repsMin')
        ..remove('repsMax');
      expectCode(json, 'mode');
    });
  });

  group('manifest', () {
    Map<String, Object?> manifest() => {
      'release': 3,
      'schemaVersion': 1,
      'minAppCatalogSchema': 1,
      'publishedAt': '2026-11-26T00:00:00Z',
      'sha256': 'ab' * 32,
      'sizeBytes': 6801,
      'url': 'https://example.invalid/x',
    };

    test('parses', () {
      final m = parseCatalogManifest(manifest())!;
      expect(m.release, 3);
      expect(m.sha256, 'ab' * 32);
      expect(m.sizeBytes, 6801);
    });

    test('manifest null means no live release', () {
      expect(parseCatalogManifest(null), isNull);
    });

    test('manifest rejects bad sha', () {
      for (final bad in ['A' * 64, 'ab' * 31, 'zz' * 32]) {
        expect(
          () => parseCatalogManifest(manifest()..['sha256'] = bad),
          throwsA(isA<CatalogFormatException>()),
        );
      }
    });

    test('manifest rejects missing key', () {
      for (final key in manifest().keys) {
        expect(
          () => parseCatalogManifest(manifest()..remove(key)),
          throwsA(
            isA<CatalogFormatException>().having(
              (e) => e.code,
              'code',
              'shape',
            ),
          ),
        );
      }
    });
  });
}
