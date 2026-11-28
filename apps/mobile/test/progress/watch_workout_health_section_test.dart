import 'dart:async';

import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/application/own_workout_health.dart';
import 'package:beyondrep/features/health/data/health_connection_repository.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/data/health_workout_writer.dart';
import 'package:beyondrep/features/health/domain/own_workout_health.dart';
import 'package:beyondrep/features/progress/data/objectbox_workout_history_repository.dart';
import 'package:beyondrep/features/progress/domain/workout_history_models.dart';
import 'package:beyondrep/features/progress/workout_history_detail_page.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_outbox.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_health_reader.dart';
import '../support/fake_health_workout_writer.dart';

class _History implements WorkoutHistoryRepository {
  _History(this.sessions);
  final List<WorkoutSessionRecord> sessions;
  @override
  WorkoutHistorySnapshot readCompleted() =>
      WorkoutHistorySnapshot(sessions: sessions);
  @override
  Future<WorkoutHistorySnapshot> readCompletedAsync() async => readCompleted();
}

class _Connected implements HealthConnectionRepository {
  @override
  bool isConnected(String ownerAccountId) => true;
  @override
  DateTime? connectedAt(String ownerAccountId) => null;
  @override
  void connect(String ownerAccountId, DateTime at) {}
  @override
  void disconnect(String ownerAccountId) {}
  @override
  int accessScope(String ownerAccountId) => 0;
  @override
  void recordAccessScope(String ownerAccountId, int scope) {}
}

WorkoutSessionRecord _session(WorkoutOrigin origin) => WorkoutSessionRecord(
  uuid: 'w-1',
  name: 'Synthetic push',
  status: WorkoutStatus.completed,
  startedAtUtc: DateTime.utc(2026, 11, 20, 9),
  completedAtUtc: DateTime.utc(2026, 11, 20, 9, 40),
  originalOffsetMinutes: 0,
  revision: 1,
  origin: origin,
);

void main() {
  late FakeHealthReader fake;

  setUp(() => fake = FakeHealthReader());

  Future<void> show(
    WidgetTester tester, {
    WorkoutOrigin origin = WorkoutOrigin.watch,
    double width = 800,
    double textScale = 1,
    bool receipt = true,
    bool ios = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workoutHistoryRepositoryProvider.overrideWithValue(
            _History([_session(origin)]),
          ),
          workoutSyncFlagsProvider.overrideWithValue(const {}),
          healthReaderProvider.overrideWithValue(fake),
          healthWorkoutWriterProvider.overrideWithValue(
            FakeHealthWorkoutWriter(isIos: ios),
          ),
          healthConnectionRepositoryProvider.overrideWithValue(_Connected()),
          healthOwnerIdProvider.overrideWithValue('owner-a'),
          watchWorkoutPlatformIdProvider.overrideWith(
            (ref, uuid) => receipt ? 'hk-1' : null,
          ),
        ],
        child: MaterialApp(
          theme: BeyondRepTheme.build(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const WorkoutHistoryDetailPage(sessionUuid: 'w-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows average, max and kcal for an Apple Watch workout', (
    tester,
  ) async {
    fake.ownWorkout = const SeriesData(
      OwnWorkoutHealth(averageBpm: 128, maxBpm: 161, activeKcal: 212.6),
    );
    await show(tester);
    expect(find.text('From Apple Health'), findsOneWidget);
    expect(find.text('Average heart rate'), findsOneWidget);
    expect(find.text('128 bpm'), findsOneWidget);
    expect(find.text('Max heart rate'), findsOneWidget);
    expect(find.text('161 bpm'), findsOneWidget);
    expect(find.text('Active energy'), findsOneWidget);
    expect(find.text('213 kcal'), findsOneWidget);
  });

  testWidgets('hides rows that are missing', (tester) async {
    fake.ownWorkout = const SeriesData(OwnWorkoutHealth(activeKcal: 90));
    await show(tester);
    expect(find.text('From Apple Health'), findsOneWidget);
    expect(find.text('Average heart rate'), findsNothing);
    expect(find.text('Max heart rate'), findsNothing);
    expect(find.text('90 kcal'), findsOneWidget);
    expect(find.textContaining(' 0 '), findsNothing);
  });

  testWidgets('shows the section for a phone workout that has a receipt', (
    tester,
  ) async {
    fake.ownWorkout = const SeriesData(OwnWorkoutHealth(averageBpm: 128));
    await show(tester, origin: WorkoutOrigin.phone);
    expect(find.text('From Apple Health'), findsOneWidget);
    expect(find.text('128 bpm'), findsOneWidget);
  });

  testWidgets('shows no section for a phone workout without a receipt', (
    tester,
  ) async {
    fake.ownWorkout = const SeriesData(OwnWorkoutHealth(averageBpm: 128));
    await show(tester, origin: WorkoutOrigin.phone, receipt: false);
    expect(find.text('From Apple Health'), findsNothing);
    expect(fake.ownWorkoutCalls, isEmpty);
  });

  testWidgets(
    'on Android a watch workout without a receipt shows the Watch tag and '
    'no heart rate row',
    (tester) async {
      fake.ownWorkout = const SeriesData(OwnWorkoutHealth(averageBpm: 128));
      await show(tester, receipt: false, ios: false);
      expect(find.text('Watch'), findsOneWidget);
      expect(find.text('Apple Watch'), findsNothing);
      expect(find.text('Average heart rate'), findsNothing);
      expect(find.text('From Health Connect'), findsNothing);
      expect(fake.ownWorkoutCalls, isEmpty);
    },
  );

  testWidgets('historyDetailShowsWatchHeartRateOnAndroid', (tester) async {
    fake.ownWorkout = const SeriesData(
      OwnWorkoutHealth(averageBpm: 128, maxBpm: 161, activeKcal: 212.6),
    );
    await show(tester, ios: false);
    expect(find.text('From Health Connect'), findsOneWidget);
    expect(find.text('From Apple Health'), findsNothing);
    expect(find.text('Average heart rate'), findsOneWidget);
    expect(find.text('128 bpm'), findsOneWidget);
    expect(find.text('Max heart rate'), findsOneWidget);
    expect(find.text('161 bpm'), findsOneWidget);
    expect(find.text('Calories'), findsOneWidget);
    expect(find.text('Active energy'), findsNothing);
    expect(find.text('213 kcal'), findsOneWidget);
  });

  testWidgets(
    'on Android a phone workout is never read back, even with an export '
    'receipt (a watch workout overlapping it would show its heart rate)',
    (tester) async {
      fake.ownWorkout = const SeriesData(
        OwnWorkoutHealth(averageBpm: 128, maxBpm: 161, activeKcal: 212),
      );
      await show(tester, origin: WorkoutOrigin.phone, ios: false);
      expect(find.text('From Health Connect'), findsNothing);
      expect(find.text('Average heart rate'), findsNothing);
      expect(fake.ownWorkoutCalls, isEmpty);
    },
  );

  testWidgets('shows no section while loading or when null', (tester) async {
    final gate = Completer<void>();
    fake.ownWorkout = const SeriesData(OwnWorkoutHealth(averageBpm: 128));
    fake.ownWorkoutGate = gate;
    await tester.pumpWidget(const SizedBox());
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workoutHistoryRepositoryProvider.overrideWithValue(
            _History([_session(WorkoutOrigin.watch)]),
          ),
          workoutSyncFlagsProvider.overrideWithValue(const {}),
          healthReaderProvider.overrideWithValue(fake),
          healthWorkoutWriterProvider.overrideWithValue(
            FakeHealthWorkoutWriter(),
          ),
          healthConnectionRepositoryProvider.overrideWithValue(_Connected()),
          healthOwnerIdProvider.overrideWithValue('owner-a'),
          watchWorkoutPlatformIdProvider.overrideWith((ref, uuid) => 'hk-1'),
        ],
        child: MaterialApp(
          theme: BeyondRepTheme.build(Brightness.light),
          home: const WorkoutHistoryDetailPage(sessionUuid: 'w-1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('From Apple Health'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('From Apple Health'), findsOneWidget);
  });

  testWidgets('null result shows no section', (tester) async {
    fake.ownWorkout = const SeriesData(null);
    await show(tester);
    expect(find.text('From Apple Health'), findsNothing);
  });

  testWidgets('fits at text scale 2.0 and 320 dp wide', (tester) async {
    fake.ownWorkout = const SeriesData(
      OwnWorkoutHealth(averageBpm: 128, maxBpm: 161, activeKcal: 212),
    );
    await show(tester, width: 320, textScale: 2);
    expect(find.text('From Apple Health'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
