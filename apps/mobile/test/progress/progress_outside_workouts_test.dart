import 'dart:io';

import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/page_header.dart';
import 'package:beyondrep/core/storage/objectbox_store_provider.dart';
import 'package:beyondrep/features/health/application/health_overview.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/domain/outside_workouts.dart';
import 'package:beyondrep/features/health/widgets/detail_layout.dart';
import 'package:beyondrep/features/progress/data/objectbox_workout_history_repository.dart';
import 'package:beyondrep/features/progress/domain/workout_history_models.dart';
import 'package:beyondrep/features/progress/outside_workout_detail_page.dart';
import 'package:beyondrep/features/progress/progress_page.dart';
import 'package:beyondrep/features/progress/workout_history_state.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fake_health_overview.dart';
import '../support/fake_health_reader.dart';
import '../support/health_overview_fixtures.dart';

const _owner = 'synthetic-owner';
final _anchor = DateTime.utc(2026, 11, 24, 12);

class _History implements WorkoutHistoryRepository {
  _History(this.sessions);
  final List<WorkoutSessionRecord> sessions;
  @override
  WorkoutHistorySnapshot readCompleted() =>
      WorkoutHistorySnapshot(sessions: sessions);
  @override
  Future<WorkoutHistorySnapshot> readCompletedAsync() async => readCompleted();
}

WorkoutSessionRecord _session(String name, DateTime startUtc) =>
    WorkoutSessionRecord(
      uuid: name,
      name: name,
      status: WorkoutStatus.completed,
      startedAtUtc: startUtc,
      completedAtUtc: startUtc.add(const Duration(minutes: 60)),
      originalOffsetMinutes: 0,
      revision: 1,
    );

OutsideWorkout _outside(
  String id,
  DateTime startUtc, {
  int minutes = 30,
  OutsideWorkoutKind kind = OutsideWorkoutKind.running,
  double? kcal,
  double? meters,
  String source = 'Synthetic app',
}) => OutsideWorkout(
  id: id,
  kind: kind,
  start: startUtc,
  end: startUtc.add(Duration(minutes: minutes)),
  activeKcal: kcal,
  distanceMeters: meters,
  source: source,
);

const _oldFooter =
    'Only finished BeyondRep workouts appear here. '
    'Paused, discarded and imported health workouts are excluded. '
    'Finished workouts back up to your account when you are online.';
const _newFooter =
    'Only finished BeyondRep workouts count towards your totals and back up '
    'to your account. Workouts from other apps are read from Apple Health '
    'for the last 90 days, never saved, and shown here for reference.';

void main() {
  late Directory directory;
  late Store store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-progress-out-');
    store = Store(getObjectBoxModel(), directory: directory.path);
  });
  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  Future<void> show(
    WidgetTester tester, {
    List<WorkoutSessionRecord> sessions = const [],
    Section<WorkoutsOverview>? workouts,
    FakeHealthReader? reader,
    bool connected = true,
    double width = 900,
    double textScale = 1,
    String initial = '/progress',
    bool overviewLoading = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 5200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: '/progress',
          builder: (_, _) => const Scaffold(body: ProgressPage()),
        ),
        GoRoute(
          path: '/progress/workouts/:id',
          builder: (_, state) =>
              Scaffold(body: Text('session ${state.pathParameters['id']}')),
        ),
        GoRoute(
          path: '/progress/health-workouts/:id',
          builder: (_, state) =>
              OutsideWorkoutDetailPage(workoutId: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          workoutHistoryRepositoryProvider.overrideWithValue(
            _History(sessions),
          ),
          progressNowProvider.overrideWithValue(_anchor),
          fakeHealthOverview(
            FakeHealthOverviewController(
              pending: overviewLoading,
              connected
                  ? overview(
                      workouts:
                          workouts ??
                          const SectionData(WorkoutsOverview(outside: [])),
                    )
                  : null,
            ),
          ),
          healthReaderProvider.overrideWithValue(reader ?? FakeHealthReader()),
          healthOwnerIdProvider.overrideWithValue(_owner),
          healthClockProvider.overrideWithValue(() => overviewReadAt),
        ],
        child: MaterialApp.router(
          theme: BeyondRepTheme.build(Brightness.light),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    if (overviewLoading) {
      await tester.pump(const Duration(milliseconds: 50));
    } else {
      await tester.pumpAndSettle();
    }
  }

  final a = _session('Session A', DateTime.utc(2026, 11, 20, 10));
  final b = _session('Session B', DateTime.utc(2026, 11, 10, 10));
  final run = _outside(
    'run',
    DateTime(2026, 11, 15, 8).toUtc(),
    kcal: 286,
    meters: 5000,
  );

  testWidgets('outside running row sits between two BeyondRep sessions by '
      'date', (tester) async {
    await show(
      tester,
      sessions: [a, b],
      workouts: SectionData(WorkoutsOverview(outside: [run])),
    );
    final ya = tester.getTopLeft(find.text('Session A')).dy;
    final yr = tester.getTopLeft(find.text('Running')).dy;
    final yb = tester.getTopLeft(find.text('Session B')).dy;
    expect(ya, lessThan(yr));
    expect(yr, lessThan(yb));
    expect(find.text('From Synthetic app'), findsOneWidget);
    expect(find.textContaining('15 Nov · 8:00 AM · 30 min'), findsOneWidget);
    expect(find.textContaining('5.0 km'), findsOneWidget);
    expect(find.textContaining('286 kcal'), findsOneWidget);
  });

  testWidgets('finished count ignores outside workouts', (tester) async {
    await show(
      tester,
      sessions: [a, b],
      workouts: SectionData(WorkoutsOverview(outside: [run])),
    );
    expect(find.text('2 finished'), findsOneWidget);
  });

  testWidgets('merged session shows From Apple Watch · 131 kcal · avg 112 '
      'bpm', (tester) async {
    final reader = FakeHealthReader()
      ..series[HealthSeriesType.heartRate] = [
        (
          from: DateTime.utc(2026, 11, 20, 10, 10),
          to: DateTime.utc(2026, 11, 20, 10, 10),
          value: 100.0,
          source: 'Synthetic watch',
        ),
        (
          from: DateTime.utc(2026, 11, 20, 10, 20),
          to: DateTime.utc(2026, 11, 20, 10, 20),
          value: 124.0,
          source: 'Synthetic watch',
        ),
      ];
    await show(
      tester,
      sessions: [a],
      reader: reader,
      workouts: SectionData(
        WorkoutsOverview(
          outside: [
            _outside(
              'watch',
              DateTime.utc(2026, 11, 20, 10, 5),
              kcal: 131,
              source: 'Apple Watch',
            ),
          ],
        ),
      ),
    );
    expect(
      find.text('From Apple Watch · 131 kcal · avg 112 bpm'),
      findsOneWidget,
    );
    // Merged into the session, so not listed on its own.
    expect(find.text('Running'), findsNothing);
  });

  testWidgets('merged session with no kcal and no HR shows From Apple Watch '
      'only', (tester) async {
    await show(
      tester,
      sessions: [a],
      workouts: SectionData(
        WorkoutsOverview(
          outside: [
            _outside(
              'watch',
              DateTime.utc(2026, 11, 20, 10, 5),
              source: 'Apple Watch',
            ),
          ],
        ),
      ),
    );
    expect(find.text('From Apple Watch'), findsOneWidget);
  });

  testWidgets('period 30 days hides an outside workout from 40 days ago', (
    tester,
  ) async {
    await show(
      tester,
      sessions: [a],
      workouts: SectionData(
        WorkoutsOverview(
          outside: [
            _outside(
              'old',
              DateTime.utc(2026, 10, 15, 8),
              kind: OutsideWorkoutKind.cycling,
            ),
          ],
        ),
      ),
    );
    expect(find.text('Cycling'), findsNothing);
    await tester.tap(find.text('90 days'));
    await tester.pumpAndSettle();
    expect(find.text('Cycling'), findsOneWidget);
    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    expect(
      find.text('Workouts from other apps go back 90 days.'),
      findsOneWidget,
    );
  });

  testWidgets('no BeyondRep sessions: empty state plus From other apps', (
    tester,
  ) async {
    await show(tester, workouts: SectionData(WorkoutsOverview(outside: [run])));
    expect(find.text('Nothing logged yet'), findsOneWidget);
    expect(find.text('From other apps'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
  });

  testWidgets('disconnected health shows exactly the stage 1 page and '
      'footer', (tester) async {
    await show(tester, sessions: [a], connected: false);
    expect(find.text(_oldFooter), findsOneWidget);
    expect(find.text('From other apps'), findsNothing);
    expect(find.text(_newFooter), findsNothing);
  });

  testWidgets('workouts not allowed keeps the old footer and no rows', (
    tester,
  ) async {
    await show(
      tester,
      sessions: [a],
      workouts: const SectionGap(MetricGap.notAllowed),
    );
    expect(find.text(_oldFooter), findsOneWidget);
    expect(find.text('Running'), findsNothing);
  });

  testWidgets('connected with workouts shows the new footer', (tester) async {
    await show(tester, sessions: [a]);
    expect(find.text(_newFooter), findsOneWidget);
    expect(find.text(_oldFooter), findsNothing);
  });

  testWidgets('text scale 2.0 no overflow at 320 dp', (tester) async {
    // Progress's overview tiles and body map already overflow at this size
    // (stage 1); nothing else may.
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      await show(
        tester,
        sessions: [a, b],
        width: 320,
        textScale: 2,
        workouts: SectionData(
          WorkoutsOverview(
            outside: [
              run,
              _outside(
                'watch',
                DateTime.utc(2026, 11, 20, 10, 5),
                kcal: 131,
                source: 'Apple Watch With A Long Source Name',
              ),
            ],
          ),
        ),
      );
    } finally {
      FlutterError.onError = previous;
    }
    // Only the layout overflows of StatTile (stats.dart) and the body map
    // (muscle_map.dart) are known; any other error fails the test.
    bool known(FlutterErrorDetails e) {
      final text = e.toString();
      return text.contains('A RenderFlex overflowed') &&
          (text.contains('lib/core/design/stats.dart') ||
              text.contains('lib/features/progress/muscle_map.dart'));
    }

    final unexpected = errors.where((e) => !known(e));
    expect(unexpected, isEmpty);
    await tester.scrollUntilVisible(
      find.text('Running'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Running'), findsOneWidget);
  });

  testWidgets('tapping an outside row opens its read-only detail', (
    tester,
  ) async {
    await show(
      tester,
      sessions: [a],
      workouts: SectionData(WorkoutsOverview(outside: [run])),
    );
    await tester.tap(find.text('Running'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Read from Apple Health. Read only and not saved in BeyondRep.',
      ),
      findsOneWidget,
    );
  });

  group('outside workout detail', () {
    testWidgets('shows type, duration, kcal, source and read-only caption', (
      tester,
    ) async {
      await show(
        tester,
        initial: '/progress/health-workouts/run',
        workouts: SectionData(WorkoutsOverview(outside: [run])),
      );
      expect(find.text('Running'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);
      expect(find.text('286 kcal'), findsOneWidget);
      expect(find.text('5.0 km'), findsOneWidget);
      expect(find.text('Synthetic app'), findsOneWidget);
      expect(
        find.text(
          'Read from Apple Health. Read only and not saved in BeyondRep.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('About Workouts from other apps'),
        findsOneWidget,
      );
    });

    testWidgets('HR shows — when no samples', (tester) async {
      await show(
        tester,
        initial: '/progress/health-workouts/run',
        workouts: SectionData(WorkoutsOverview(outside: [run])),
      );
      expect(
        find.descendant(
          of: find.widgetWithText(DetailRow, 'Average heart rate'),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('average HR comes from samples in the window', (tester) async {
      final reader = FakeHealthReader()
        ..series[HealthSeriesType.heartRate] = [
          (
            from: DateTime(2026, 11, 15, 8, 10).toUtc(),
            to: DateTime(2026, 11, 15, 8, 10).toUtc(),
            value: 130.0,
            source: 'Synthetic watch',
          ),
        ];
      await show(
        tester,
        reader: reader,
        initial: '/progress/health-workouts/run',
        workouts: SectionData(WorkoutsOverview(outside: [run])),
      );
      expect(find.text('130 bpm'), findsOneWidget);
    });

    testWidgets('cold load shows a loading state, not no longer available', (
      tester,
    ) async {
      await show(
        tester,
        initial: '/progress/health-workouts/run',
        overviewLoading: true,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('This workout is no longer available.'), findsNothing);
    });

    testWidgets('unknown id shows This workout is no longer available.', (
      tester,
    ) async {
      await show(tester, initial: '/progress/health-workouts/gone');
      expect(find.text('This workout is no longer available.'), findsOneWidget);
      expect(find.byType(NsBackButton), findsOneWidget);
    });
  });
}
