import 'package:beyondrep/features/catalog/data/catalog_repository.dart';
import 'package:beyondrep/features/catalog/domain/catalog_models.dart';

import '../catalog/catalog_fixtures.dart';

CatalogPrescription _rx(
  String id, {
  int sets = 3,
  int repsMin = 8,
  int repsMax = 10,
  int? seconds,
  int rest = 90,
  String note = '',
}) => CatalogPrescription(
  exerciseId: id,
  sets: sets,
  repsMin: seconds == null ? repsMin : null,
  repsMax: seconds == null ? repsMax : null,
  durationSeconds: seconds,
  restSeconds: rest,
  note: note,
);

CatalogTemplate _tpl(
  String id,
  String name,
  String level,
  List<CatalogPrescription> rows, {
  bool standalone = true,
  List<String> equipment = const ['barbell'],
  List<String> goals = const ['general'],
}) => CatalogTemplate(
  id: id,
  name: name,
  description: 'Synthetic description for $name.',
  goals: goals,
  level: level,
  equipment: equipment,
  estimatedMinutes: 40,
  standalone: standalone,
  exercises: rows,
);

/// Synthetic exercises and templates for the Workouts screens.
CatalogSnapshot templatesSnapshot() {
  final exercises = [
    for (var i = 1; i <= 6; i++)
      catalogExercise('builtin.v1.synthetic-move-$i', 'Synthetic move $i'),
    catalogExercise(
      'builtin.v1.synthetic-hold',
      'Synthetic hold',
      mode: 'duration',
      category: 'core',
      group: 'Core',
      equipment: const ['bodyweight'],
      primary: const ['abs'],
    ),
  ];
  return CatalogSnapshot(
    release: 3,
    schemaVersion: 1,
    minAppCatalogSchema: 1,
    publishedAt: '2026-11-26T00:00:00Z',
    sha256: 'a' * 64,
    exercises: exercises,
    templates: [
      _tpl('tpl.push', 'Synthetic push', 'beginner', [
        _rx(
          'builtin.v1.synthetic-move-1',
          sets: 4,
          repsMin: 6,
          repsMax: 8,
          rest: 150,
          note: 'Pause at the bottom',
        ),
        _rx('builtin.v1.synthetic-hold', seconds: 45, rest: 60),
      ]),
      _tpl(
        'tpl.pull',
        'Synthetic pull',
        'intermediate',
        [
          _rx('builtin.v1.synthetic-move-2'),
          _rx('builtin.v1.synthetic-move-3', repsMin: 10, repsMax: 10),
        ],
        equipment: const ['dumbbell'],
        goals: const ['strength', 'hypertrophy'],
      ),
      _tpl('tpl.hidden', 'Synthetic hidden', 'beginner', [
        _rx('builtin.v1.synthetic-move-1'),
      ], standalone: false),
      _tpl('tpl.big', 'Synthetic seven', 'advanced', [
        for (var i = 1; i <= 6; i++) _rx('builtin.v1.synthetic-move-$i'),
        _rx('builtin.v1.synthetic-hold', seconds: 30, rest: 60),
      ]),
    ],
    programs: const [],
  );
}

CatalogState readyTemplates() =>
    CatalogState(snapshot: templatesSnapshot(), status: CatalogStatus.ready);
