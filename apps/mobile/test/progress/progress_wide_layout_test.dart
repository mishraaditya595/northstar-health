import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/layout.dart';
import 'package:beyondrep/features/progress/domain/workout_history_models.dart';
import 'package:beyondrep/features/progress/progress_page.dart';
import 'package:beyondrep/features/progress/workout_history_detail_page.dart';
import 'package:beyondrep/features/progress/workout_history_state.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_outbox.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _empty = 'Pick a workout to see its sets.';
final _now = DateTime.utc(2026, 11, 25, 12);

WorkoutSessionRecord _session(String id, String name, int daysAgo) =>
    WorkoutSessionRecord(
      uuid: id,
      name: name,
      status: WorkoutStatus.completed,
      startedAtUtc: _now.subtract(Duration(days: daysAgo, hours: 1)),
      completedAtUtc: _now.subtract(Duration(days: daysAgo)),
      originalOffsetMinutes: 0,
      revision: 1,
    );

final _two = WorkoutHistorySnapshot(
  sessions: [_session('s-1', 'Push day', 1), _session('s-2', 'Pull day', 2)],
);

class _Snapshot extends Notifier<WorkoutHistorySnapshot> {
  @override
  WorkoutHistorySnapshot build() => _two;

  void set(WorkoutHistorySnapshot value) => state = value;
}

final _snapshotProvider = NotifierProvider<_Snapshot, WorkoutHistorySnapshot>(
  _Snapshot.new,
);

void _size(WidgetTester tester, double w, double h) {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

late GoRouter _router;

Future<void> _pumpProgress(WidgetTester tester, Size size) async {
  _size(tester, size.width, size.height);
  _router = GoRouter(
    initialLocation: '/progress',
    routes: [
      GoRoute(
        path: '/progress',
        builder: (_, _) => const Scaffold(body: ProgressPage()),
      ),
      GoRoute(
        path: '/progress/workouts/:id',
        builder: (_, state) =>
            WorkoutHistoryDetailPage(sessionUuid: state.pathParameters['id']!),
      ),
    ],
  );
  addTearDown(_router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        completedWorkoutHistoryProvider.overrideWith(
          (ref) async => ref.watch(_snapshotProvider),
        ),
        progressNowProvider.overrideWithValue(_now),
        workoutSyncFlagsProvider.overrideWithValue(const {}),
      ],
      child: MaterialApp.router(
        theme: BeyondRepTheme.build(Brightness.light),
        routerConfig: _router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String get _path => _router.state.uri.path;

Future<void> _tapSession(WidgetTester tester, String name) async {
  await tester.scrollUntilVisible(
    find.text(name),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wide Progress opens a workout in the right pane', (
    tester,
  ) async {
    await _pumpProgress(tester, const Size(1194, 834));
    await _tapSession(tester, 'Push day');
    expect(find.text('Workout details'), findsOneWidget);
    expect(find.byType(ProgressPage), findsOneWidget);
    expect(_path, '/progress');
  });

  testWidgets('narrow Progress still pushes the detail page', (tester) async {
    await _pumpProgress(tester, const Size(390, 844));
    await _tapSession(tester, 'Push day');
    expect(_path, '/progress/workouts/s-1');
  });

  testWidgets('wide Progress shows the empty message before a pick', (
    tester,
  ) async {
    await _pumpProgress(tester, const Size(1194, 834));
    expect(find.text(_empty), findsOneWidget);
  });

  testWidgets('selected workout removed falls back to the empty message', (
    tester,
  ) async {
    await _pumpProgress(tester, const Size(1194, 834));
    await _tapSession(tester, 'Push day');
    expect(find.text('Workout details'), findsOneWidget);
    ProviderScope.containerOf(tester.element(find.byType(ProgressPage)))
        .read(_snapshotProvider.notifier)
        .set(
          WorkoutHistorySnapshot(sessions: [_session('s-2', 'Pull day', 2)]),
        );
    await tester.pumpAndSettle();
    expect(find.text(_empty), findsOneWidget);
    expect(find.text('Workout details'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrowing with a workout open pushes it', (tester) async {
    await _pumpProgress(tester, const Size(1194, 834));
    await _tapSession(tester, 'Push day');
    expect(_path, '/progress');
    _size(tester, 507, 1024);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_path, '/progress/workouts/s-1');
    expect(find.byType(NsListDetail), findsNothing);
    // Pushed exactly once: one pop returns to the list.
    _router.pop();
    await tester.pumpAndSettle();
    expect(_path, '/progress');
  });
}
