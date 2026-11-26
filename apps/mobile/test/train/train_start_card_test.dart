import 'dart:io';

import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/features/catalog/domain/catalog_programs.dart';
import 'package:beyondrep/features/catalog/domain/catalog_templates.dart';
import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/domain/readiness.dart';
import 'package:beyondrep/features/programs/data/objectbox_program_repository.dart';
import 'package:beyondrep/features/train/active_workout_state.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/features/workouts/domain/live_workout_engine.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_health_overview.dart';
import '../support/health_overview_fixtures.dart';
import 'program_test_support.dart';

/// Wednesday 25 Nov 2026: day 1 of a program seeded to start on Wednesday.
final _wednesday = DateTime(2026, 11, 25, 10);
final _thursday = DateTime(2026, 11, 26, 10);

Section<ReadinessOverview> _ready(int value) => SectionData(
  ReadinessOverview(
    result: ReadinessReady(
      Readiness(
        value: value,
        band: readinessBandOf(value),
        parts: const [
          ReadinessPart(input: ReadinessInput.hrv, score: 40, weight: .5),
          ReadinessPart(input: ReadinessInput.sleep, score: 50, weight: .5),
        ],
      ),
    ),
    hasHrv: true,
    hasRestingHr: false,
    hasSleep: true,
    hrvVsNormal: null,
    restingHrVsNormal: null,
    hrvBaseline: null,
    restingHrBaseline: null,
    hrvIsSdnn: true,
  ),
);

const _building = SectionData(
  ReadinessOverview(
    result: ReadinessNotReady(daysUntilBaseline: 5),
    hasHrv: true,
    hasRestingHr: false,
    hasSleep: true,
    hrvVsNormal: null,
    restingHrVsNormal: null,
    hrvBaseline: null,
    restingHrBaseline: null,
    hrvIsSdnn: true,
  ),
);

const _notEnough = SectionData(
  ReadinessOverview(
    result: ReadinessNotReady(noSleep: true),
    hasHrv: false,
    hasRestingHr: false,
    hasSleep: false,
    hrvVsNormal: null,
    restingHrVsNormal: null,
    hrvBaseline: null,
    restingHrBaseline: null,
    hrvIsSdnn: true,
  ),
);

HealthOverview _today(Section<ReadinessOverview> readiness) =>
    overview(readiness: readiness, readAt: DateTime(2026, 11, 25, 7));

ActiveWorkoutView _unfinished() => ActiveWorkoutView(
  WorkoutSessionRecord(
    uuid: 'open',
    name: 'Morning lift',
    status: WorkoutStatus.paused,
    startedAtUtc: DateTime.utc(2026, 11, 25, 7),
    originalOffsetMinutes: 0,
    revision: 2,
  ),
  const WorkoutRecoveryCheckpoint(sessionUuid: 'open', checkpointRevision: 1),
);

void main() {
  late Directory directory;
  late Store store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-start-card-');
    store = Store(getObjectBoxModel(), directory: directory.path);
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  /// Imports the three-day program starting Wednesday and makes it active.
  void seedProgram() {
    final snapshot = programsSnapshot();
    final program = browsablePrograms(snapshot)
        .firstWhere((p) => p.id == 'prog.three');
    final templates = {
      for (final t in program.week.whereType<String>())
        t: programTemplate(snapshot, t)!,
    };
    ObjectBoxProgramRepository(store).importProgram(
      requestUuid: 'seed',
      program: program,
      templateRows: {
        for (final e in templates.entries)
          e.key: templateRowInputs(e.value, snapshot),
      },
      templateNames: {for (final e in templates.entries) e.key: e.value.name},
      release: 4,
      firstDayWeekday: 3,
      makeActive: true,
      localToday: DateTime(2026, 11, 25),
    );
  }

  Future<List<String>> open(
    WidgetTester tester, {
    HealthOverview? health,
    FakeHealthOverviewController? controller,
    DateTime? now,
    double textScale = 1,
    double width = 390,
    Brightness brightness = Brightness.light,
    List<Override> overrides = const [],
  }) async {
    final visited = await pumpPrograms(
      tester,
      store: store,
      directory: directory,
      initial: '/train',
      now: now ?? _wednesday,
      textScale: textScale,
      brightness: brightness,
      health: controller ?? FakeHealthOverviewController(health),
      overrides: [
        healthOwnerIdProvider.overrideWith((ref) => 'synthetic-owner'),
        ...overrides,
      ],
    );
    if (width != 390) {
      tester.view.physicalSize = Size(width, 1600);
      await tester.pumpAndSettle();
    }
    return visited;
  }

  group('readiness strip', () {
    testWidgets('good readiness shows the strip above Quick workout', (
      tester,
    ) async {
      await open(tester, health: _today(_ready(82)));
      final strip = find.text('Good readiness. Good to train.');
      expect(strip, findsOneWidget);
      expect(
        tester.getTopLeft(strip).dy,
        lessThan(tester.getTopLeft(find.text('Quick workout')).dy),
      );
      expect(find.text('Build the work.'), findsOneWidget);
      expect(find.text('82'), findsOneWidget);
    });

    testWidgets('fair strip text', (tester) async {
      await open(tester, health: _today(_ready(64)));
      expect(
        find.text('Fair readiness. Train as planned, watch effort.'),
        findsOneWidget,
      );
      expect(find.text('Your plans are not changed'), findsNothing);
    });

    testWidgets('low strip says plans are not changed and uses red', (
      tester,
    ) async {
      await open(tester, health: _today(_ready(41)));
      expect(find.text('Low readiness. Recovery low.'), findsOneWidget);
      expect(find.text('Your plans are not changed'), findsOneWidget);
      final score = tester.widget<Text>(find.text('41'));
      expect(score.style?.color, BeyondRepPalette.redLight);
    });

    testWidgets('the strip is one button that opens the readiness detail', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await open(tester, health: _today(_ready(64)));
      expect(
        find.bySemanticsLabel(
          'Readiness 64, Train as planned, watch effort. See why',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('building baseline shows the N more days line', (tester) async {
      await open(tester, health: _today(_building));
      expect(
        find.text('Readiness starts after 5 more days with data.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    for (final (name, health) in <(String, HealthOverview?)>[
      ('not enough data', _today(_notEnough)),
      ('a gap', _today(const SectionGap(MetricGap.noData))),
      ('not connected', null),
      ('read yesterday', overview(readiness: _ready(82))),
    ]) {
      testWidgets('$name shows no strip and the card is unchanged', (
        tester,
      ) async {
        await open(tester, health: health);
        expect(find.textContaining('readiness.'), findsNothing);
        expect(find.textContaining('Readiness starts'), findsNothing);
        expect(find.text('Build the work.'), findsOneWidget);
        expect(find.text('Quick workout'), findsOneWidget);
      });
    }

    testWidgets('loading shows no strip', (tester) async {
      await open(
        tester,
        controller: FakeHealthOverviewController(null, pending: true),
      );
      expect(find.textContaining('readiness.'), findsNothing);
      expect(find.text('Quick workout'), findsOneWidget);
    });

    testWidgets('shown, it asks the overview to re-read if stale', (
      tester,
    ) async {
      final controller = FakeHealthOverviewController(_today(_ready(64)));
      await open(tester, controller: controller);
      expect(controller.refreshIfStaleCalls, 1);
    });
  });

  group('program workout today', () {
    testWidgets('the card names the workout and Start runs the program day', (
      tester,
    ) async {
      seedProgram();
      final visited = await open(tester, health: _today(_ready(82)));
      expect(find.text('Program'), findsOneWidget);
      expect(find.text('Today in Synthetic three-day'), findsOneWidget);
      expect(find.text('Build the work.'), findsNothing);
      expect(find.text('Quick workout'), findsOneWidget);
      await tester.tap(find.text('Start Synthetic push'));
      await tester.pumpAndSettle();
      expect(visited, ['logger']);
      final session = store.box<WorkoutSessionEntity>().getAll().single;
      expect(session.name, 'Synthetic push');
      expect(session.programDayLocalDate, '2026-11-25');
    });

    testWidgets('the strip sits above Start and Quick workout is secondary', (
      tester,
    ) async {
      seedProgram();
      await open(tester, health: _today(_ready(82)));
      final strip = tester.getTopLeft(
        find.text('Good readiness. Good to train.'),
      );
      expect(
        strip.dy,
        lessThan(tester.getTopLeft(find.text('Start Synthetic push')).dy),
      );
      expect(find.widgetWithText(TextButton, 'Quick workout'), findsOneWidget);
    });

    testWidgets('Quick workout still starts an empty workout', (tester) async {
      seedProgram();
      await open(tester, health: _today(_ready(82)));
      await tester.tap(find.text('Quick workout'));
      await tester.pumpAndSettle();
      expect(find.text('Start an empty workout'), findsOneWidget);
    });

    testWidgets('a rest day falls back to Quick workout', (tester) async {
      seedProgram();
      await open(tester, health: _today(_ready(82)), now: _thursday);
      expect(find.text('Build the work.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Quick workout'), findsOne);
      expect(find.textContaining('Start Synthetic'), findsNothing);
    });

    testWidgets('an unavailable day falls back to Quick workout', (
      tester,
    ) async {
      seedProgram();
      final plan = store.box<WorkoutPlanEntity>().getAll().firstWhere(
        (p) => p.name == 'Synthetic push',
      );
      plan.archivedAtMs = 1;
      store.box<WorkoutPlanEntity>().put(plan);
      await open(tester, health: _today(_ready(82)));
      expect(find.text('Build the work.'), findsOneWidget);
      expect(find.textContaining('Start Synthetic'), findsNothing);
    });

    testWidgets('no program shows the unchanged card', (tester) async {
      await open(tester, health: _today(_ready(82)));
      expect(find.text('Strength'), findsOneWidget);
      expect(find.text('Build the work.'), findsOneWidget);
      expect(find.text('Your program'), findsNothing);
    });

    testWidgets('an unfinished workout blocks Start with the failure message', (
      tester,
    ) async {
      seedProgram();
      await open(
        tester,
        health: _today(_ready(82)),
        overrides: [
          activeWorkoutProvider.overrideWith(
            (ref) => AsyncData<ActiveWorkoutView?>(_unfinished()),
          ),
        ],
      );
      await tester.tap(find.text('Start Synthetic push'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not start this workout'),
        findsOneWidget,
      );
      expect(store.box<WorkoutSessionEntity>().count(), 0);
    });

    testWidgets('low readiness still shows the once-per-day note first', (
      tester,
    ) async {
      seedProgram();
      final visited = await open(tester, health: _today(_ready(41)));
      await tester.tap(find.text('Start Synthetic push'));
      await tester.pumpAndSettle();
      expect(find.text('Recovery is low today'), findsOneWidget);
      expect(store.box<WorkoutSessionEntity>().count(), 0);
      await tester.tap(find.text('Start workout'));
      await tester.pumpAndSettle();
      expect(visited, ['logger']);
      expect(store.box<WorkoutSessionEntity>().count(), 1);
    });

    testWidgets('after today is done the card falls back to Quick workout', (
      tester,
    ) async {
      seedProgram();
      final programUuid = store
          .box<TrainingProgramEntity>()
          .getAll()
          .first
          .uuid;
      store.box<WorkoutSessionEntity>().put(
        WorkoutSessionEntity(
          uuid: 'done-today',
          name: 'Synthetic push',
          status: WorkoutStatus.completed.name,
          startedAtMs: _wednesday.millisecondsSinceEpoch,
          completedAtMs: _wednesday.millisecondsSinceEpoch,
          originalOffsetMinutes: 0,
          updatedAtMs: _wednesday.millisecondsSinceEpoch,
          programUuid: programUuid,
          programDayLocalDate: '2026-11-25',
        ),
      );
      await open(tester, health: _today(_ready(82)));
      expect(find.text('Start Synthetic push'), findsNothing);
      expect(find.text('Build the work.'), findsOneWidget);
      expect(find.text('Quick workout'), findsOneWidget);
    });

    testWidgets('Your program row is still shown', (tester) async {
      seedProgram();
      await open(tester, health: _today(_ready(82)));
      await tester.scrollUntilVisible(
        find.text('Your program'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Today: Synthetic push'), findsOneWidget);
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets('start card fits 2x text at 390 px (${brightness.name})', (
      tester,
    ) async {
      seedProgram();
      await open(
        tester,
        health: _today(_ready(41)),
        textScale: 2,
        brightness: brightness,
      );
      expect(tester.takeException(), isNull);
      expect(
        find.text('Start Synthetic push', skipOffstage: false),
        findsOneWidget,
      );
    });
  }

  testWidgets('start card stays on screen at 2x text and 320 dp', (
    tester,
  ) async {
    seedProgram();
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);
    await open(tester, health: _today(_ready(41)), textScale: 2, width: 320);
    expect(errors.map((e) => e.toString()), isEmpty);
    for (final text in [
      'Low readiness. Recovery low.',
      'Start Synthetic push',
    ]) {
      final rect = tester.getRect(find.text(text));
      expect(rect.left, greaterThanOrEqualTo(0), reason: text);
      expect(rect.right, lessThanOrEqualTo(320), reason: text);
    }
  });
}
