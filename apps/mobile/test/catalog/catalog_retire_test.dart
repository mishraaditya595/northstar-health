import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:beyondrep/features/catalog/domain/catalog_models.dart';
import 'package:beyondrep/features/catalog/domain/catalog_programs.dart';
import 'package:beyondrep/features/catalog/domain/catalog_templates.dart';
import 'package:beyondrep/features/programs/data/objectbox_program_repository.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_library_repository.dart';
import 'package:beyondrep/objectbox.g.dart';

import '../train/program_test_support.dart';

CatalogTemplate _retire(CatalogTemplate t) => CatalogTemplate(
  id: t.id,
  name: t.name,
  description: t.description,
  goals: t.goals,
  level: t.level,
  equipment: t.equipment,
  estimatedMinutes: t.estimatedMinutes,
  standalone: t.standalone,
  retired: true,
  exercises: t.exercises,
);

CatalogProgram _retireProgram(CatalogProgram p) => CatalogProgram(
  id: p.id,
  name: p.name,
  description: p.description,
  goals: p.goals,
  level: p.level,
  daysPerWeek: p.daysPerWeek,
  estimatedMinutes: p.estimatedMinutes,
  equipment: p.equipment,
  retired: true,
  week: p.week,
);

CatalogSnapshot _with(
  CatalogSnapshot s, {
  List<CatalogTemplate>? templates,
  List<CatalogProgram>? programs,
}) => CatalogSnapshot(
  release: s.release,
  schemaVersion: s.schemaVersion,
  minAppCatalogSchema: s.minAppCatalogSchema,
  publishedAt: s.publishedAt,
  sha256: s.sha256,
  exercises: s.exercises,
  templates: templates ?? s.templates,
  programs: programs ?? s.programs,
);

void main() {
  final base = programsSnapshot();

  test('retired templates and programs leave the browse lists', () {
    expect(
      browsableTemplates(base).map((t) => t.id),
      isNot(contains('tpl.old')),
    );
    expect(
      browsablePrograms(base).map((p) => p.id),
      isNot(contains('prog.old')),
    );
    final retiredPush = _with(
      base,
      templates: [
        for (final t in base.templates) t.id == 'tpl.push' ? _retire(t) : t,
      ],
    );
    expect(
      browsableTemplates(retiredPush).map((t) => t.id),
      isNot(contains('tpl.push')),
    );
    expect(browsableTemplates(base).map((t) => t.id), contains('tpl.push'));
    final retiredProgram = _with(
      base,
      programs: [
        for (final p in base.programs)
          p.id == 'prog.three' ? _retireProgram(p) : p,
      ],
    );
    expect(browsablePrograms(retiredProgram).map((p) => p.id), ['prog.six']);
  });

  test('a retired program-only template is still previewable', () {
    final retired = _with(
      base,
      templates: [
        for (final t in base.templates) t.id == 'tpl.hidden' ? _retire(t) : t,
      ],
    );
    expect(programTemplate(retired, 'tpl.hidden'), isNotNull);
  });

  group('copies, imported programs and plans stay', () {
    late Directory directory;
    late Store store;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('beyondrep-retire-');
      store = Store(getObjectBoxModel(), directory: directory.path);
    });
    tearDown(() {
      store.close();
      directory.deleteSync(recursive: true);
    });

    test('retiring the source changes nothing the user already has', () {
      final program = browsablePrograms(base)
          .firstWhere((p) => p.id == 'prog.three');
      final ids = program.week.whereType<String>().toSet();
      final repo = ObjectBoxProgramRepository(store);
      repo.importProgram(
        requestUuid: 'r1',
        program: program,
        templateRows: {
          for (final id in ids)
            id: templateRowInputs(programTemplate(base, id)!, base),
        },
        templateNames: {
          for (final id in ids) id: programTemplate(base, id)!.name,
        },
        release: 4,
        firstDayWeekday: 1,
        makeActive: true,
        localToday: DateTime(2026, 11, 25),
      );
      final push = browsableTemplates(base)
          .firstWhere((t) => t.id == 'tpl.push');
      ObjectBoxWorkoutLibraryRepository(store).copyCatalogTemplate(
        requestUuid: 'c1',
        name: push.name,
        description: push.description,
        rows: templateRowInputs(push, base),
        release: 4,
      );

      // The next release retires all of it; nothing local reads the catalogue.
      final retired = _with(
        base,
        templates: [for (final t in base.templates) _retire(t)],
        programs: [for (final p in base.programs) _retireProgram(p)],
      );
      expect(browsableTemplates(retired), isEmpty);
      expect(browsablePrograms(retired), isEmpty);

      final programs = repo.listPrograms();
      expect(programs, hasLength(1));
      expect(programs.single.isActive, isTrue);
      expect(repo.programPlans(programs.single.uuid), hasLength(3));
      expect(
        ObjectBoxWorkoutLibraryRepository(store).listPlans(),
        hasLength(1),
      );
    });
  });
}
