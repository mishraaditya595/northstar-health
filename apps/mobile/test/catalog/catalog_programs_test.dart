import 'dart:convert';
import 'dart:io';

import 'package:beyondrep/features/catalog/domain/catalog_models.dart';
import 'package:beyondrep/features/catalog/domain/catalog_parser.dart';
import 'package:beyondrep/features/catalog/domain/catalog_programs.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_fixtures.dart';
import 'catalog_parser_test.dart' show validSnapshot, expectCode;

CatalogPrescription _rx(String id) => CatalogPrescription(
  exerciseId: id,
  sets: 3,
  repsMin: 8,
  repsMax: 10,
  durationSeconds: null,
  restSeconds: 90,
  note: '',
);

CatalogTemplate _template(
  String id,
  String exerciseId, {
  bool standalone = true,
}) => CatalogTemplate(
  id: id,
  name: id,
  description: 'Synthetic.',
  goals: const ['general'],
  level: 'beginner',
  equipment: const ['barbell'],
  estimatedMinutes: 40,
  standalone: standalone,
  exercises: [_rx(exerciseId)],
);

CatalogProgram _program(String id, List<String?> week, {String name = 'P'}) =>
    CatalogProgram(
      id: id,
      name: name,
      description: 'Synthetic.',
      goals: const ['general'],
      level: 'beginner',
      daysPerWeek: week.whereType<String>().length,
      estimatedMinutes: 40,
      equipment: const ['barbell'],
      week: week,
    );

CatalogSnapshot _snapshot(
  List<CatalogExercise> exercises,
  List<CatalogTemplate> templates,
  List<CatalogProgram> programs,
) => CatalogSnapshot(
  release: 4,
  schemaVersion: 1,
  minAppCatalogSchema: 1,
  publishedAt: '2026-11-26T00:00:00Z',
  sha256: 'a' * 64,
  exercises: exercises,
  templates: templates,
  programs: programs,
);

void main() {
  group('parsing', () {
    test('typed program fields', () {
      final p = parseCatalogSnapshot(validSnapshot()).programs.single;
      expect(p.id, 'prog.a');
      expect(p.name, 'P');
      expect(p.goals, ['general']);
      expect(p.level, 'beginner');
      expect(p.daysPerWeek, 3);
      expect(p.estimatedMinutes, 40);
      expect(p.equipment, ['barbell']);
      expect(p.week, ['tpl.a', null, 'tpl.a', null, 'tpl.a', null, null]);
    });

    test('published releases 1 to 3 still parse', () {
      for (final name in [
        '20261126000100_catalog_release_1',
        '20261126030000_catalog_release_2',
        '20261126040000_catalog_release_3',
      ]) {
        final sql = File('../../supabase/migrations/$name.sql')
            .readAsStringSync();
        final start = sql.indexOf(r'$catalog$') + r'$catalog$'.length;
        final end = sql.indexOf(r'$catalog$', start);
        final snapshot = parseCatalogSnapshot(
          jsonDecode(sql.substring(start, end)),
        );
        expect(snapshot.programs, isEmpty, reason: name);
      }
    });

    test('daysPerWeek mismatch is rejected', () {
      final json = validSnapshot();
      ((json['programs']! as List).first
              as Map<String, Object?>)['daysPerWeek'] =
          4;
      expectCode(json, 'range');
    });

    test('a program with no training day is rejected', () {
      final json = validSnapshot();
      ((json['programs']! as List).first as Map<String, Object?>)
        ..['daysPerWeek'] = 0
        ..['week'] = List<Object?>.filled(7, null);
      expectCode(json, 'range');
    });
  });

  group('browsablePrograms', () {
    final squat = catalogExercise('builtin.v1.squat', 'Squat');
    final old = catalogExercise('builtin.v1.old', 'Old');
    final retired = CatalogExercise(
      id: old.id,
      name: old.name,
      aliases: const [],
      muscleGroup: 'Legs',
      primaryMuscles: const ['quads'],
      secondaryMuscles: const [],
      equipment: const ['barbell'],
      category: 'squat',
      mode: 'reps_load',
      cues: const [],
      retired: true,
    );

    test('lists program-only templates, hides retired ones, sorts', () {
      final s = _snapshot(
        [squat, retired],
        [
          _template('tpl.only', squat.id, standalone: false),
          _template('tpl.old', retired.id),
        ],
        [
          _program('prog.b', [
            'tpl.only',
            null,
            'tpl.only',
            null,
            null,
            null,
            null,
          ], name: 'Zed'),
          _program('prog.c', [
            'tpl.only',
            'tpl.only',
            null,
            null,
            null,
            null,
            null,
          ], name: 'Alpha'),
          _program('prog.d', [
            'tpl.only',
            'tpl.only',
            'tpl.only',
            null,
            null,
            null,
            null,
          ], name: 'Aaa'),
          _program('prog.x', ['tpl.old', null, null, null, null, null, null]),
        ],
      );
      expect(browsablePrograms(s).map((p) => p.id), [
        'prog.c',
        'prog.b',
        'prog.d',
      ]);
    });

    test('programTemplate finds program-only templates', () {
      final s = _snapshot(
        [squat],
        [_template('tpl.only', squat.id, standalone: false)],
        const [],
      );
      expect(programTemplate(s, 'tpl.only')?.id, 'tpl.only');
      expect(programTemplate(s, 'tpl.nope'), isNull);
    });
  });
}
