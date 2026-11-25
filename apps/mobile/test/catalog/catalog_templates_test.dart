import 'package:beyondrep/features/catalog/domain/catalog_models.dart';
import 'package:beyondrep/features/catalog/domain/catalog_parser.dart';
import 'package:beyondrep/features/catalog/domain/catalog_templates.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_fixtures.dart';

CatalogPrescription rx(
  String id, {
  int sets = 3,
  int? repsMin = 8,
  int? repsMax = 10,
  int? seconds,
}) => CatalogPrescription(
  exerciseId: id,
  sets: sets,
  repsMin: seconds == null ? repsMin : null,
  repsMax: seconds == null ? repsMax : null,
  durationSeconds: seconds,
  restSeconds: 90,
  note: '',
);

CatalogTemplate template(
  String id,
  List<CatalogPrescription> rows, {
  bool standalone = true,
  String name = 'Template',
}) => CatalogTemplate(
  id: id,
  name: name,
  description: 'Synthetic description.',
  goals: const ['general'],
  level: 'beginner',
  equipment: const ['barbell'],
  estimatedMinutes: 40,
  standalone: standalone,
  exercises: rows,
);

CatalogSnapshot snapshotWith(
  List<CatalogExercise> exercises,
  List<CatalogTemplate> templates,
) => CatalogSnapshot(
  release: 3,
  schemaVersion: 1,
  minAppCatalogSchema: 1,
  publishedAt: '2026-11-26T00:00:00Z',
  sha256: 'a' * 64,
  exercises: exercises,
  templates: templates,
  programs: const [],
);

void main() {
  group('parsing', () {
    Map<String, Object?> json({bool withStandalone = false}) {
      final j = snapshotJson(release: 3);
      j['templates'] = [
        {
          'id': 'tpl.a',
          'name': 'A',
          'description': 'Desc',
          'tags': {
            'goal': ['general'],
            'level': 'beginner',
            'equipment': ['barbell'],
          },
          'estimatedMinutes': 40,
          if (withStandalone) 'standalone': false,
          'futureKey': 1,
          'exercises': [
            {
              'exerciseId': 'builtin.v1.squat',
              'sets': 4,
              'repsMin': 6,
              'repsMax': 8,
              'restSeconds': 120,
              'note': 'Slow',
            },
            {
              'exerciseId': 'builtin.v1.plank',
              'sets': 3,
              'durationSeconds': 45,
              'restSeconds': 60,
            },
          ],
        },
      ];
      return j;
    }

    test('typed fields, standalone defaults true', () {
      final t = parseCatalogSnapshot(json()).templates.single;
      expect(t.id, 'tpl.a');
      expect(t.name, 'A');
      expect(t.level, 'beginner');
      expect(t.goals, ['general']);
      expect(t.equipment, ['barbell']);
      expect(t.estimatedMinutes, 40);
      expect(t.standalone, isTrue);
      expect(t.exercises, hasLength(2));
      final a = t.exercises.first;
      expect(
        [a.exerciseId, a.sets, a.repsMin, a.repsMax, a.restSeconds, a.note],
        ['builtin.v1.squat', 4, 6, 8, 120, 'Slow'],
      );
      expect(a.durationSeconds, isNull);
      final b = t.exercises.last;
      expect([b.durationSeconds, b.repsMin, b.note], [45, null, '']);
    });

    test('standalone false is read', () {
      final t = parseCatalogSnapshot(json(withStandalone: true))
          .templates
          .single;
      expect(t.standalone, isFalse);
    });
  });

  group('browsableTemplates', () {
    final squat = catalogExercise('builtin.v1.squat', 'Squat');
    final plank = catalogExercise(
      'builtin.v1.plank',
      'Plank',
      mode: 'duration',
    );
    final carry = catalogExercise(
      'builtin.v1.carry',
      'Carry',
      mode: 'duration_load',
    );
    final retired = CatalogExercise(
      id: 'builtin.v1.old',
      name: 'Old',
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

    test('hides non-standalone, retired, unloggable; sorts by name', () {
      final s = snapshotWith(
        [squat, plank, carry, retired],
        [
          template('tpl.z', [rx(squat.id)], name: 'Zeta'),
          template('tpl.a', [rx(plank.id, seconds: 30)], name: 'alpha'),
          template('tpl.hidden', [rx(squat.id)], standalone: false),
          template('tpl.old', [rx(squat.id), rx(retired.id)]),
          template('tpl.carry', [rx(squat.id), rx(carry.id, seconds: 30)]),
          template('tpl.missing', [rx('builtin.v1.nope')]),
        ],
      );
      expect(browsableTemplates(s).map((t) => t.id), ['tpl.a', 'tpl.z']);
    });
  });

  group('labels', () {
    test('prescriptionLabel', () {
      expect(
        prescriptionLabel(rx('x', sets: 4, repsMin: 6, repsMax: 8)),
        '4 × 6–8 reps',
      );
      expect(
        prescriptionLabel(rx('x', repsMin: 10, repsMax: 10)),
        '3 × 10 reps',
      );
      expect(prescriptionLabel(rx('x', seconds: 45)), '3 × 45 s');
      expect(prescriptionLabel(rx('x', seconds: 90)), '3 × 1 min 30 s');
    });

    test('restLabel', () {
      expect(restLabel(90), 'Rest 90 s');
      expect(restLabel(60), 'Rest 60 s');
      expect(restLabel(150), 'Rest 2 min 30 s');
      expect(restLabel(120), 'Rest 2 min');
      expect(restLabel(0), 'No rest');
    });
  });
}
