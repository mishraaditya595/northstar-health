import 'package:flutter_test/flutter_test.dart';

import 'package:beyondrep/features/catalog/domain/catalog_filter.dart';
import 'package:beyondrep/features/catalog/domain/catalog_models.dart';

CatalogTemplate template({
  String name = 'Synthetic push',
  String description = 'Synthetic description.',
  String level = 'beginner',
  List<String> goals = const ['strength'],
  List<String> equipment = const ['barbell'],
}) => CatalogTemplate(
  id: 'tpl.x',
  name: name,
  description: description,
  goals: goals,
  level: level,
  equipment: equipment,
  estimatedMinutes: 40,
  exercises: const [],
);

CatalogProgram program({
  String name = 'Synthetic program',
  String level = 'beginner',
  List<String> goals = const ['strength'],
  List<String> equipment = const ['barbell'],
  int daysPerWeek = 3,
}) => CatalogProgram(
  id: 'prog.x',
  name: name,
  description: 'Synthetic description.',
  goals: goals,
  level: level,
  daysPerWeek: daysPerWeek,
  estimatedMinutes: 40,
  equipment: equipment,
  week: const [null, null, null, null, null, null, null],
);

void main() {
  test('an empty filter matches everything and counts nothing', () {
    const filter = CatalogFilter();
    expect(filter.isEmpty, isTrue);
    expect(filter.activeCount, 0);
    expect(matchesTemplate(template(), filter), isTrue);
    expect(matchesTemplate(template(goals: [], equipment: []), filter), isTrue);
    expect(matchesProgram(program(), filter), isTrue);
  });

  group('goal', () {
    test('matches when any selected goal is one of the item goals', () {
      final t = template(goals: ['strength', 'hypertrophy']);
      expect(
        matchesTemplate(t, const CatalogFilter(goals: {'hypertrophy'})),
        isTrue,
      );
      expect(
        matchesTemplate(
          t,
          const CatalogFilter(goals: {'endurance', 'strength'}),
        ),
        isTrue,
      );
      expect(
        matchesTemplate(t, const CatalogFilter(goals: {'endurance'})),
        isFalse,
      );
      expect(
        matchesProgram(
          program(goals: ['general']),
          const CatalogFilter(goals: {'strength'}),
        ),
        isFalse,
      );
    });
  });

  group('equipment I have', () {
    test('an item shows when every piece it needs is selected', () {
      final t = template(equipment: ['barbell', 'bench']);
      expect(
        matchesTemplate(t, const CatalogFilter(equipment: {'barbell'})),
        isFalse,
      );
      expect(
        matchesTemplate(
          t,
          const CatalogFilter(equipment: {'barbell', 'bench', 'dumbbell'}),
        ),
        isTrue,
      );
    });

    test('bodyweight always counts as available', () {
      expect(
        matchesTemplate(
          template(equipment: ['bodyweight']),
          const CatalogFilter(equipment: {'dumbbell'}),
        ),
        isTrue,
      );
      expect(
        matchesTemplate(
          template(equipment: ['bodyweight', 'dumbbell']),
          const CatalogFilter(equipment: {'dumbbell'}),
        ),
        isTrue,
      );
      expect(
        matchesProgram(
          program(equipment: ['bodyweight', 'cable']),
          const CatalogFilter(equipment: {'dumbbell'}),
        ),
        isFalse,
      );
    });

    test('an item that needs nothing always matches', () {
      expect(
        matchesTemplate(
          template(equipment: []),
          const CatalogFilter(equipment: {'dumbbell'}),
        ),
        isTrue,
      );
    });

    test('nothing selected means the filter is off', () {
      expect(
        matchesTemplate(template(equipment: ['cable']), const CatalogFilter()),
        isTrue,
      );
    });
  });

  group('days per week', () {
    test('applies to programs only and matches exactly', () {
      expect(
        matchesProgram(
          program(daysPerWeek: 4),
          const CatalogFilter(daysPerWeek: 4),
        ),
        isTrue,
      );
      expect(
        matchesProgram(
          program(daysPerWeek: 4),
          const CatalogFilter(daysPerWeek: 3),
        ),
        isFalse,
      );
      expect(
        matchesTemplate(template(), const CatalogFilter(daysPerWeek: 5)),
        isTrue,
      );
    });
  });

  group('level and query', () {
    test('level is exact', () {
      expect(
        matchesTemplate(template(), const CatalogFilter(level: 'advanced')),
        isFalse,
      );
      expect(
        matchesProgram(program(), const CatalogFilter(level: 'beginner')),
        isTrue,
      );
    });

    test(
      'query matches the name or description, ignoring case of the item',
      () {
        expect(
          matchesTemplate(
            template(name: 'Upper Body'),
            const CatalogFilter(query: 'upper'),
          ),
          isTrue,
        );
        expect(
          matchesTemplate(
            template(),
            const CatalogFilter(query: 'description'),
          ),
          isTrue,
        );
        expect(
          matchesProgram(program(), const CatalogFilter(query: 'zzz')),
          isFalse,
        );
      },
    );
  });

  test('all rules combine, and activeCount counts the sheet filters only', () {
    const filter = CatalogFilter(
      goals: {'strength'},
      equipment: {'barbell'},
      daysPerWeek: 3,
      level: 'beginner',
      query: 'x',
    );
    expect(filter.activeCount, 3);
    expect(filter.isEmpty, isFalse);
    expect(const CatalogFilter(level: 'beginner').activeCount, 0);
    expect(const CatalogFilter(level: 'beginner').isEmpty, isFalse);
    expect(matchesProgram(program(name: 'xyz'), filter), isTrue);
    expect(
      matchesProgram(program(name: 'xyz', daysPerWeek: 4), filter),
      isFalse,
    );
  });

  test('toggling returns a new filter and leaves the old one alone', () {
    const base = CatalogFilter();
    final a = base.toggleGoal('strength').toggleEquipment('cable');
    expect(base.goals, isEmpty);
    expect(a.goals, {'strength'});
    expect(a.equipment, {'cable'});
    expect(a.toggleGoal('strength').goals, isEmpty);
    expect(a.withDays(4).daysPerWeek, 4);
    expect(a.withDays(4).withDays(4).daysPerWeek, isNull);
    expect(a.withDays(4).withDays(null).daysPerWeek, isNull);
    expect(a.clearedSheetFilters().activeCount, 0);
    expect(a.withLevel('advanced').clearedSheetFilters().level, 'advanced');
  });
}
