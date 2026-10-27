import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/design/northstar_theme.dart';
import 'package:northstar_health/core/storage/objectbox_store_provider.dart';
import 'package:northstar_health/features/account/account_auth_controller.dart';
import 'package:northstar_health/features/progress/data/objectbox_workout_history_repository.dart';
import 'package:northstar_health/features/progress/domain/workout_history_models.dart';
import 'package:northstar_health/features/progress/workout_history_detail_page.dart';
import 'package:northstar_health/features/sync/workout_upload_coordinator.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_outbox.dart';
import 'package:northstar_health/features/workouts/data/workout_entities.dart';
import 'package:northstar_health/objectbox.g.dart';

import '../support/fake_account_auth.dart';

const workout = '00000000-0000-4000-8000-000000002101';

class OfflineUpload implements WorkoutUploadTransport {
  @override
  Future<Map<String, dynamic>> send(
    WorkoutSyncOperation operation, {
    required int expectedServerRevision,
  }) => throw StateError('No network in widget test');
}

class ImmediateHistory extends ObjectBoxWorkoutHistoryRepository {
  ImmediateHistory(super.store);
  @override
  Future<WorkoutHistorySnapshot> readCompletedAsync() async => readCompleted();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Store store;
  late FakeAuthApi api;
  late AccountAuthController auth;
  late WorkoutUploadCoordinator worker;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('northstar-delete-ui-');
    store = Store(getObjectBoxModel(), directory: dir.path);
    final time = DateTime.utc(2026, 10, 24, 9).millisecondsSinceEpoch;
    store.box<WorkoutSessionEntity>().put(
      WorkoutSessionEntity(
        uuid: workout,
        name: 'Back training',
        status: 'completed',
        startedAtMs: time,
        completedAtMs: time + 1800000,
        originalOffsetMinutes: 330,
        updatedAtMs: time,
      ),
    );
    api = FakeAuthApi();
    auth = controller(api, FakeBoundAccountStore());
    worker = WorkoutUploadCoordinator(
      accountId: accountA,
      auth: auth,
      outbox: ObjectBoxWorkoutOutbox(store),
      transport: OfflineUpload(),
    );
  });

  tearDown(() async {
    worker.dispose();
    auth.dispose();
    await api.dispose();
    store.close();
    dir.deleteSync(recursive: true);
  });

  Future<void> mountDetail(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1450);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          workoutHistoryRepositoryProvider.overrideWithValue(
            ImmediateHistory(store),
          ),
          workoutUploadCoordinatorProvider.overrideWithValue(worker),
        ],
        child: MaterialApp(
          theme: NorthstarTheme.build(Brightness.light),
          home: const WorkoutHistoryDetailPage(sessionUuid: workout),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('never-uploaded deletion requires confirmation and stays local', (
    tester,
  ) async {
    await mountDetail(tester);
    await tester.ensureVisible(find.text('Delete workout'));
    await tester.tap(find.text('Delete workout'));
    await tester.pumpAndSettle();
    expect(find.text('Delete completed workout?'), findsOneWidget);
    expect(store.box<WorkoutSyncOutboxEntity>().count(), 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      store.box<WorkoutSessionEntity>().getAll().single.deletedAtMs,
      isNull,
    );
    await tester.tap(find.text('Delete workout'));
    await tester.pumpAndSettle();
    // The dialog adds a second matching label to the page's button.
    await tester.tap(find.text('Delete workout').last);
    await tester.pumpAndSettle();
    expect(
      store.box<WorkoutSessionEntity>().getAll().single.deletedAtMs,
      isNotNull,
    );
    expect(store.box<WorkoutSyncOutboxEntity>().count(), 0);
    expect(find.text('This completed workout is unavailable.'), findsOneWidget);
  });

  testWidgets('known pending upload queues a dependent cloud tombstone', (
    tester,
  ) async {
    final outbox = ObjectBoxWorkoutOutbox(store);
    store.runInTransaction(TxMode.write, () {
      outbox.enqueueCompletedInTransaction(workout);
    });
    await mountDetail(tester);
    await tester.ensureVisible(find.text('Delete workout'));
    await tester.tap(find.text('Delete workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete workout').last);
    await tester.pumpAndSettle();

    final operations = store.box<WorkoutSyncOutboxEntity>().getAll()
      ..sort((a, b) => a.localRevision.compareTo(b.localRevision));
    expect(operations.map((op) => op.action), ['upsert', 'delete']);
    expect(operations.last.payloadJson, 'null');
    expect(store.box<WorkoutSessionEntity>().getAll().single.deletedAtMs, isNotNull);
    expect(find.text('This completed workout is unavailable.'), findsOneWidget);
  });
}
