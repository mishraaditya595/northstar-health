import 'dart:io';

import 'package:beyondrep/features/catalog/domain/catalog_models.dart';
import 'package:beyondrep/features/catalog/domain/catalog_programs.dart';
import 'package:beyondrep/features/programs/domain/program_models.dart';
import 'package:beyondrep/features/workouts/domain/workout_library_models.dart';
import 'package:beyondrep/features/catalog/domain/catalog_templates.dart';
import 'package:beyondrep/features/programs/data/objectbox_program_repository.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'program_test_support.dart';

Future<void> tapLow(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

class _FailsOnceAfterCommit extends ObjectBoxProgramRepository {
  _FailsOnceAfterCommit(super.store);
  final requests = <String>[];

  @override
  TrainingProgramRecord importProgram({
    required String requestUuid,
    required CatalogProgram program,
    required Map<String, List<TemplateRowInput>> templateRows,
    required Map<String, String> templateNames,
    Map<String, String> templateDescriptions = const {},
    required int release,
    required int firstDayWeekday,
    required bool makeActive,
    required DateTime localToday,
  }) {
    requests.add(requestUuid);
    final result = super.importProgram(
      requestUuid: requestUuid,
      program: program,
      templateRows: templateRows,
      templateNames: templateNames,
      templateDescriptions: templateDescriptions,
      release: release,
      firstDayWeekday: firstDayWeekday,
      makeActive: makeActive,
      localToday: localToday,
    );
    if (requests.length == 1) throw StateError('lost after commit');
    return result;
  }
}

void main() {
  late Directory directory;
  late Store store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-programs-ui-');
    store = Store(getObjectBoxModel(), directory: directory.path);
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  /// Imports a synthetic program straight into the store.
  String seed(String id, {int firstDay = 3, bool active = true}) {
    final snapshot = programsSnapshot();
    final program = browsablePrograms(snapshot).firstWhere((p) => p.id == id);
    final templates = {
      for (final t in program.week.whereType<String>())
        t: programTemplate(snapshot, t)!,
    };
    return ObjectBoxProgramRepository(store)
        .importProgram(
          requestUuid: 'seed-${store.box<TrainingProgramEntity>().count()}',
          program: program,
          templateRows: {
            for (final e in templates.entries)
              e.key: templateRowInputs(e.value, snapshot),
          },
          templateNames: {
            for (final e in templates.entries) e.key: e.value.name,
          },
          release: 4,
          firstDayWeekday: firstDay,
          makeActive: active,
          localToday: DateTime(2026, 11, 25),
        )
        .uuid;
  }

  TrainingProgramEntity onlyProgram() =>
      store.box<TrainingProgramEntity>().getAll().single;

  Future<List<String>> open(
    WidgetTester tester,
    String initial, {
    Brightness brightness = Brightness.light,
    double textScale = 1,
    DateTime? now,
    DateTime Function()? clock,
  }) => pumpPrograms(
    tester,
    store: store,
    directory: directory,
    initial: initial,
    brightness: brightness,
    textScale: textScale,
    now: now,
    clock: clock,
  );

  group('programs list', () {
    testWidgets('lists programs with their summary and filters', (
      tester,
    ) async {
      await open(tester, '/train/programs');
      expect(find.text('Synthetic three-day'), findsOneWidget);
      expect(find.text('Synthetic six-day'), findsOneWidget);
      expect(
        find.textContaining('3 days a week · Beginner · about 40 min'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'six');
      await tester.pumpAndSettle();
      expect(find.text('Synthetic three-day'), findsNothing);
      expect(find.text('Synthetic six-day'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Beginner'));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic six-day'), findsNothing);
      expect(find.text('Synthetic three-day'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No matching programs.'), findsOneWidget);
    });

    group('filters', () {
      Future<void> pick(WidgetTester tester, List<String> labels) async {
        await tester.tap(find.byTooltip('Filters'));
        await tester.pumpAndSettle();
        for (final label in labels) {
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Show results'));
        await tester.pumpAndSettle();
      }

      testWidgets('goal, equipment and days per week narrow the list', (
        tester,
      ) async {
        await open(tester, '/train/programs');
        await pick(tester, ['Hypertrophy']);
        expect(find.text('Synthetic six-day'), findsOneWidget);
        expect(find.text('Synthetic three-day'), findsNothing);
        expect(find.text('Filters (1)'), findsOneWidget);
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();
        expect(find.text('Synthetic three-day'), findsOneWidget);

        // Cable is only needed by the six-day program.
        await pick(tester, ['Barbell', 'Dumbbell']);
        expect(find.text('Synthetic three-day'), findsOneWidget);
        expect(find.text('Synthetic six-day'), findsNothing);
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();

        await pick(tester, ['6']);
        expect(find.text('Synthetic six-day'), findsOneWidget);
        expect(find.text('Synthetic three-day'), findsNothing);
      });

      testWidgets('days per week is single select and can be unselected', (
        tester,
      ) async {
        await open(tester, '/train/programs');
        await pick(tester, ['3', '6']);
        expect(find.text('Synthetic six-day'), findsOneWidget);
        expect(find.text('Synthetic three-day'), findsNothing);
        await pick(tester, ['6']);
        expect(find.text('Synthetic three-day'), findsOneWidget);
        expect(find.text('Synthetic six-day'), findsOneWidget);
      });

      testWidgets('no match says so', (tester) async {
        await open(tester, '/train/programs');
        await pick(tester, ['Hypertrophy', '3']);
        expect(find.text('Filters (2)'), findsOneWidget);
        expect(find.text('No matching programs.'), findsOneWidget);
      });

      for (final brightness in Brightness.values) {
        testWidgets('the sheet at text scale 2.0 (${brightness.name})', (
          tester,
        ) async {
          await open(
            tester,
            '/train/programs',
            textScale: 2,
            brightness: brightness,
          );
          await tester.tap(find.byTooltip('Filters'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(
            find.text('Show results'),
            100,
            scrollable: find
                .descendant(
                  of: find.byType(BottomSheet),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(tester.takeException(), isNull);
        });
      }
    });

    testWidgets('your programs are listed first and open', (tester) async {
      final uuid = seed('prog.three');
      await open(tester, '/train/programs');
      expect(find.text('Your programs'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      await tester.tap(find.text('Active'));
      await tester.pumpAndSettle();
      expect(find.text('Your program'), findsOneWidget);
      expect(uuid, isNotEmpty);
    });

    testWidgets('an unavailable catalogue says so', (tester) async {
      await pumpPrograms(
        tester,
        store: store,
        directory: directory,
        initial: '/train/programs',
        state: unavailableCatalog(),
      );
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('program detail', () {
    testWidgets('shows seven days and expands one', (tester) async {
      await open(tester, '/train/programs/prog.three');
      expect(
        find.textContaining('Day 1 · Synthetic push · 2 exercises'),
        findsOneWidget,
      );
      expect(find.text('Day 2 · Rest'), findsOneWidget);
      for (var i = 3; i <= 7; i++) {
        await tester.scrollUntilVisible(
          find.textContaining('Day $i ·'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await tester.scrollUntilVisible(
        find.textContaining('Day 1 ·'),
        -400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('4 × 6–8 reps'), findsNothing);
      await tester.tap(find.textContaining('Day 1 · Synthetic push'));
      await tester.pumpAndSettle();
      expect(find.textContaining('4 × 6–8 reps'), findsOneWidget);
      expect(find.textContaining('Rest 2 min 30 s'), findsOneWidget);
      expect(find.text('Pause at the bottom'), findsOneWidget);
      await tester.tap(find.textContaining('Day 1 · Synthetic push'));
      await tester.pumpAndSettle();
      expect(find.textContaining('4 × 6–8 reps'), findsNothing);
    });

    testWidgets('shows how to use the program, also at 200% text', (
      tester,
    ) async {
      await open(tester, '/train/programs/prog.three', textScale: 2);
      final scroll = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.textContaining('How to use this program', findRichText: true),
        300,
        scrollable: scroll,
      );
      for (final text in [
        'Warm up',
        '2 reps in reserve',
        'Add load only',
        'Times are approximate',
      ]) {
        expect(find.textContaining(text, findRichText: true), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a program-only template is previewed', (tester) async {
      await open(tester, '/train/programs/prog.three');
      expect(find.textContaining('Synthetic hidden'), findsOneWidget);
    });

    testWidgets('an unknown program is not available', (tester) async {
      await open(tester, '/train/programs/prog.nope');
      expect(find.text("This program isn't available."), findsOneWidget);
    });

    testWidgets('Add on Wednesday, active: creates the program and opens it', (
      tester,
    ) async {
      await open(tester, '/train/programs/prog.three');
      await tester.tap(find.text('Add program'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wednesday'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add program').last);
      await tester.pumpAndSettle();
      final program = onlyProgram();
      expect(program.firstDayWeekday, 3);
      expect(program.isActive, isTrue);
      expect(store.box<WorkoutPlanEntity>().count(), 3);
      expect(find.text('Your program'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Added Synthetic three-day'), findsOneWidget);
    });

    testWidgets('unchecking active adds an inactive program', (tester) async {
      await open(tester, '/train/programs/prog.three');
      await tester.tap(find.text('Add program'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Make it my active program'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add program').last);
      await tester.pumpAndSettle();
      expect(onlyProgram().isActive, isFalse);
      expect(find.text('Not active'), findsOneWidget);
    });

    testWidgets('a double tap on Add gives one program', (tester) async {
      await open(tester, '/train/programs/prog.three');
      await tester.tap(find.text('Add program'));
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(FilledButton, 'Add program').last;
      await tester.tap(confirm);
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(store.box<TrainingProgramEntity>().count(), 1);
      expect(store.box<WorkoutPlanEntity>().count(), 3);
    });

    testWidgets('a retry after a failure reuses the request: one program', (
      tester,
    ) async {
      // The first add commits, then reports a failure (as if the app lost
      // the result). Tapping Add again must return that program, not make
      // a second one.
      final flaky = _FailsOnceAfterCommit(store);
      await pumpPrograms(
        tester,
        store: store,
        directory: directory,
        initial: '/train/programs/prog.three',
        programRepository: flaky,
      );
      await tester.tap(find.text('Add program'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add program').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Could not add this program. Try again.'),
        findsOneWidget,
      );
      expect(store.box<TrainingProgramEntity>().count(), 1);
      await tester.tap(find.text('Add program'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add program').last);
      await tester.pumpAndSettle();
      expect(store.box<TrainingProgramEntity>().count(), 1);
      expect(store.box<WorkoutPlanEntity>().count(), 3);
      expect(find.text('Your program'), findsOneWidget);
      expect(flaky.requests.toSet(), hasLength(1));
      expect(flaky.requests, hasLength(2));
    });

    testWidgets('a second add later is numbered (2)', (tester) async {
      seed('prog.three');
      await open(tester, '/train/programs/prog.three');
      await tester.tap(find.text('Add program'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add program').last);
      await tester.pumpAndSettle();
      expect(find.text('Synthetic three-day (2)'), findsOneWidget);
      expect(store.box<TrainingProgramEntity>().count(), 2);
      expect(
        store.box<TrainingProgramEntity>().getAll().where((p) => p.isActive),
        hasLength(1),
      );
    });
  });

  group('your program', () {
    final wednesday = DateTime(2026, 11, 25, 10);

    testWidgets('lists the week from the first weekday', (tester) async {
      final uuid = seed('prog.three');
      await open(tester, '/train/program/$uuid', now: wednesday);
      expect(find.text('Wednesday · Synthetic push'), findsOneWidget);
      expect(find.text('Thursday · Rest'), findsOneWidget);
      expect(find.text('Day 1 · Today'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('start today opens the logger with the program fields', (
      tester,
    ) async {
      final uuid = seed('prog.three');
      final visited = await open(
        tester,
        '/train/program/$uuid',
        now: wednesday,
      );
      await tester.tap(find.text("Start today's workout"));
      await tester.pumpAndSettle();
      expect(visited, ['logger']);
      final session = store.box<WorkoutSessionEntity>().getAll().single;
      expect(session.programUuid, uuid);
      expect(session.programDayLocalDate, '2026-11-25');
      expect(session.name, 'Synthetic push');
    });

    testWidgets('the clock crossing midnight after build does not start', (
      tester,
    ) async {
      final uuid = seed('prog.three');
      var clock = DateTime(2026, 11, 25, 23, 58);
      final visited = await open(
        tester,
        '/train/program/$uuid',
        now: DateTime(2026, 11, 25, 23, 58),
        clock: () => clock,
      );
      clock = DateTime(2026, 11, 26, 0, 2); // Thursday: a rest day
      await tester.tap(find.text("Start today's workout"));
      await tester.pumpAndSettle();
      expect(visited, isEmpty);
      expect(store.box<WorkoutSessionEntity>().count(), 0);
      expect(
        find.text("Today's workout changed. Check it and try again."),
        findsOneWidget,
      );
    });

    testWidgets('a clock still on the same day starts and stores that date', (
      tester,
    ) async {
      final uuid = seed('prog.three');
      final visited = await open(
        tester,
        '/train/program/$uuid',
        now: DateTime(2026, 11, 25, 9),
        clock: () => DateTime(2026, 11, 25, 23, 50),
      );
      await tester.tap(find.text("Start today's workout"));
      await tester.pumpAndSettle();
      expect(visited, ['logger']);
      expect(
        store.box<WorkoutSessionEntity>().getAll().single.programDayLocalDate,
        '2026-11-25',
      );
    });

    testWidgets('a rest day shows Rest day today and no start', (tester) async {
      final uuid = seed('prog.three');
      await open(
        tester,
        '/train/program/$uuid',
        now: DateTime(2026, 11, 26, 10),
      );
      expect(find.text('Rest day today'), findsOneWidget);
      expect(find.text("Start today's workout"), findsNothing);
    });

    group('status and missed days', () {
      // Monday first, activated Wednesday 2026-11-25, now Friday 2026-11-27:
      // Mon push is before activation, Wed pull is missed, Fri hidden is today.
      final friday = DateTime(2026, 11, 27, 10);

      Future<String> openMissed(
        WidgetTester tester, {
        DateTime Function()? clock,
        double textScale = 1,
        Brightness brightness = Brightness.light,
      }) async {
        final uuid = seed('prog.three', firstDay: 1);
        await open(
          tester,
          '/train/program/$uuid',
          now: friday,
          clock: clock,
          textScale: textScale,
          brightness: brightness,
        );
        return uuid;
      }

      testWidgets('each row carries a status tag', (tester) async {
        await openMissed(tester);
        expect(find.text('Upcoming'), findsOneWidget); // Monday
        expect(find.text('Missed'), findsOneWidget); // Wednesday
        expect(find.text('Today'), findsOneWidget); // Friday
        expect(find.text('Rest'), findsWidgets);
        expect(find.text('Start for Wednesday'), findsOneWidget);
      });

      testWidgets('Start for Wednesday opens the logger and records that '
          'date', (tester) async {
        final uuid = await openMissed(tester);
        await tapLow(tester, 'Start for Wednesday');
        final session = store.box<WorkoutSessionEntity>().getAll().single;
        expect(session.programUuid, uuid);
        expect(session.programDayLocalDate, '2026-11-25');
        expect(session.name, 'Synthetic pull');
        expect(find.text('LOGGER'), findsOneWidget);
      });

      testWidgets('a day that stopped being missed before the tap does not '
          'start', (tester) async {
        var clock = friday;
        await openMissed(tester, clock: () => clock);
        clock = DateTime(2026, 11, 30, 0, 5); // next Monday: a new week
        await tapLow(tester, 'Start for Wednesday');
        expect(store.box<WorkoutSessionEntity>().count(), 0);
        expect(
          find.text('This day changed. Check it and try again.'),
          findsOneWidget,
        );
      });

      testWidgets('text scale 2.0, light and dark: tags and start rows '
          'do not overflow', (tester) async {
        for (final brightness in Brightness.values) {
          await openMissed(tester, textScale: 2, brightness: brightness);
          await tester.scrollUntilVisible(
            find.text('Start for Wednesday'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Start for Wednesday'), findsOneWidget);
        }
      });

      testWidgets('an inactive program shows no Start and says how to get '
          'one', (tester) async {
        final uuid = seed('prog.three', firstDay: 3, active: false);
        await open(tester, '/train/program/$uuid', now: wednesday);
        expect(
          find.text('Make this your active program to start its workouts'),
          findsOneWidget,
        );
        expect(find.text("Start today's workout"), findsNothing);
        expect(find.textContaining('Start for'), findsNothing);
        expect(find.text('Missed'), findsNothing);
      });
    });

    testWidgets('a day can be changed to Rest', (tester) async {
      final uuid = seed('prog.three');
      await open(tester, '/train/program/$uuid', now: wednesday);
      await tester.tap(find.text('Wednesday · Synthetic push'));
      await tester.pumpAndSettle();
      expect(find.text('Edit workout'), findsOneWidget);
      await tester.tap(find.text('Synthetic push').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rest').last);
      await tester.pumpAndSettle();
      final days = store.box<ProgramDayEntity>().getAll()
        ..sort((a, b) => a.dayIndex.compareTo(b.dayIndex));
      expect(days.first.planUuid, isNull);
      expect(find.text('Wednesday · Rest'), findsOneWidget);
    });

    testWidgets('a rest day can be pointed at another program workout', (
      tester,
    ) async {
      final uuid = seed('prog.three');
      await open(tester, '/train/program/$uuid', now: wednesday);
      await tester.tap(find.text('Thursday · Rest'));
      await tester.pumpAndSettle();
      expect(find.text('Edit workout'), findsNothing);
      await tester.tap(find.text('Rest').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Synthetic pull').last);
      await tester.pumpAndSettle();
      expect(find.text('Thursday · Synthetic pull'), findsOneWidget);
    });

    testWidgets('a single-use day set to Rest can be pointed back', (
      tester,
    ) async {
      final uuid = seed('prog.three');
      await open(tester, '/train/program/$uuid', now: wednesday);
      // Friday (day 2) is the only day using Synthetic pull.
      await tester.tap(find.text('Friday · Synthetic pull'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Synthetic pull').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rest').last);
      await tester.pumpAndSettle();
      expect(find.text('Friday · Rest'), findsOneWidget);
      await tester.tap(find.text('Friday · Rest'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rest').last);
      await tester.pumpAndSettle();
      expect(find.text('Synthetic pull'), findsOneWidget);
      await tester.tap(find.text('Synthetic pull'));
      await tester.pumpAndSettle();
      expect(find.text('Friday · Synthetic pull'), findsOneWidget);
    });

    testWidgets('Edit workout opens that plan in the editor', (tester) async {
      final uuid = seed('prog.three');
      final visited = await open(
        tester,
        '/train/program/$uuid',
        now: wednesday,
      );
      await tester.tap(find.text('Wednesday · Synthetic push'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit workout'));
      await tester.pumpAndSettle();
      final plan = store.box<WorkoutPlanEntity>().getAll().firstWhere(
        (p) => p.name == 'Synthetic push',
      );
      expect(visited, ['edit ${plan.uuid}']);
    });

    testWidgets('changing the start day reorders the week', (tester) async {
      final uuid = seed('prog.three');
      await open(tester, '/train/program/$uuid', now: wednesday);
      await tapLow(tester, 'Change start day');
      await tester.tap(find.text('Monday'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(onlyProgram().firstDayWeekday, 1);
      expect(find.text('Monday · Synthetic push'), findsOneWidget);
    });

    testWidgets('stop using and make active', (tester) async {
      final uuid = seed('prog.three');
      await open(tester, '/train/program/$uuid', now: wednesday);
      await tapLow(tester, 'Stop using this program');
      expect(onlyProgram().isActive, isFalse);
      await tapLow(tester, 'Make active');
      expect(onlyProgram().isActive, isTrue);
      expect(onlyProgram().activatedLocalDate, '2026-11-25');
    });

    testWidgets('archive asks first, then archives program and plans', (
      tester,
    ) async {
      final uuid = seed('prog.three');
      await open(tester, '/train/program/$uuid', now: wednesday);
      await tapLow(tester, 'Archive program');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(onlyProgram().archivedAtMs, isNull);
      await tapLow(tester, 'Archive program');
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      expect(onlyProgram().archivedAtMs, isNotNull);
      expect(
        store.box<WorkoutPlanEntity>().getAll().every(
          (p) => p.archivedAtMs != null,
        ),
        isTrue,
      );
    });

    testWidgets('a day whose plan was archived shows unavailable, no start', (
      tester,
    ) async {
      final uuid = seed('prog.three');
      final plan = store.box<WorkoutPlanEntity>().getAll().firstWhere(
        (p) => p.name == 'Synthetic push',
      );
      plan.archivedAtMs = 1;
      store.box<WorkoutPlanEntity>().put(plan);
      await open(tester, '/train/program/$uuid', now: wednesday);
      expect(find.text('Workout unavailable'), findsOneWidget);
      expect(find.text("Start today's workout"), findsNothing);
      expect(find.text('Rest day today'), findsNothing);
    });

    testWidgets('a week with no training day says so', (tester) async {
      final uuid = seed('prog.three');
      final repo = ObjectBoxProgramRepository(store);
      for (var i = 0; i < 7; i++) {
        repo.setDayPlan(uuid, i, null);
      }
      await open(tester, '/train/program/$uuid', now: wednesday);
      expect(find.text('No training days'), findsOneWidget);
      expect(find.text('Rest day today'), findsOneWidget);
    });
  });

  group('train page', () {
    testWidgets('programs card always, program card only when active', (
      tester,
    ) async {
      await open(tester, '/train');
      await tester.scrollUntilVisible(
        find.text('Programs'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Programs'), findsOneWidget);
      expect(
        find.text('Multi-week plans with a weekly schedule'),
        findsOneWidget,
      );
      expect(find.text('Your program'), findsNothing);
    });

    testWidgets('the active program shows today; its plans are not listed', (
      tester,
    ) async {
      seed('prog.three');
      await open(tester, '/train', now: DateTime(2026, 11, 25, 10));
      expect(find.text('Your program'), findsOneWidget);
      expect(find.text('Synthetic three-day'), findsOneWidget);
      expect(find.text('Today: Synthetic push'), findsOneWidget);
      expect(find.text('Synthetic pull'), findsNothing);
      expect(find.text('No plans yet'), findsOneWidget);
    });

    testWidgets('a rest day reads Today: Rest day', (tester) async {
      seed('prog.three');
      await open(tester, '/train', now: DateTime(2026, 11, 26, 10));
      expect(find.text('Today: Rest day'), findsOneWidget);
    });

    testWidgets('an archived plan today reads Workout unavailable', (
      tester,
    ) async {
      seed('prog.three');
      final plan = store.box<WorkoutPlanEntity>().getAll().firstWhere(
        (p) => p.name == 'Synthetic push',
      );
      plan.archivedAtMs = 1;
      store.box<WorkoutPlanEntity>().put(plan);
      await open(tester, '/train', now: DateTime(2026, 11, 25, 10));
      expect(find.text('Today: Workout unavailable'), findsOneWidget);
      expect(find.text('Today: Rest day'), findsNothing);
    });

    testWidgets('an inactive program has no card', (tester) async {
      seed('prog.three', active: false);
      await open(tester, '/train');
      expect(find.text('Your program'), findsNothing);
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'text scale 2.0: six-day detail does not overflow (${brightness.name})',
      (tester) async {
        await open(
          tester,
          '/train/programs/prog.six',
          brightness: brightness,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        final scrollable = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.textContaining('Day 3 ·'),
          200,
          scrollable: scrollable,
        );
        await tester.ensureVisible(find.textContaining('Day 3 ·'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Day 3 ·'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.textContaining('Day 7 ·'),
          300,
          scrollable: scrollable,
        );
        await tester.ensureVisible(find.textContaining('Day 7 ·'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Day 7 ·').hitTestable(), findsOneWidget);
      },
    );

    testWidgets(
      'text scale 2.0: Your program does not overflow (${brightness.name})',
      (tester) async {
        final uuid = seed('prog.six');
        await open(
          tester,
          '/train/program/$uuid',
          brightness: brightness,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Archive program'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Archive program').hitTestable(), findsOneWidget);
      },
    );
  }
}
