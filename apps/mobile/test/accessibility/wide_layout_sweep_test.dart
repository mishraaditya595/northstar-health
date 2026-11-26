import 'dart:io';

import 'package:beyondrep/app/beyondrep_app.dart';
import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/design/layout.dart';
import 'package:beyondrep/core/storage/objectbox_store_provider.dart';
import 'package:beyondrep/features/account/account_auth_controller.dart';
import 'package:beyondrep/features/account/account_auth_provider.dart';
import 'package:beyondrep/features/catalog/application/catalog_providers.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/progress/data/objectbox_workout_history_repository.dart';
import 'package:beyondrep/features/progress/domain/workout_history_models.dart';
import 'package:beyondrep/features/train/active_workout_state.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_library_repository.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../catalog/catalog_fixtures.dart';
import '../support/fake_account_auth.dart';
import '../support/fake_health_overview.dart';
import '../support/fake_health_reader.dart';
import '../support/fake_health_summary.dart';
import '../support/health_overview_fixtures.dart';
import '../train/program_test_support.dart';
import '../train/training_library_harness.dart';

/// Widget tests read the same ObjectBox Store immediately; the worker-isolate
/// read is covered by the native suite.
class _ImmediateHistory implements WorkoutHistoryRepository {
  _ImmediateHistory(Store store)
    : _native = ObjectBoxWorkoutHistoryRepository(store);
  final ObjectBoxWorkoutHistoryRepository _native;

  @override
  WorkoutHistorySnapshot readCompleted() => _native.readCompleted();

  @override
  Future<WorkoutHistorySnapshot> readCompletedAsync() async => readCompleted();
}

/// Every screen that got a wide layout, at phone, portrait tablet, split
/// view, landscape tablet and large landscape tablet, in both themes, at
/// normal and 200 % text: nothing overflows or throws.
const _locations = [
  '/today',
  '/train',
  '/train/exercises',
  '/train/workouts',
  '/train/programs',
  '/progress',
  '/health',
  '/health/readiness',
  '/health/sleep',
  '/health/heart',
  '/health/activity',
  '/health/body',
];

const _sizes = <Size>[
  Size(390, 844),
  Size(820, 1180),
  Size(507, 1024),
  Size(1194, 834),
  Size(1366, 1024),
];

void main() {
  late Directory directory;
  late Store store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-sweep-');
    store = Store(getObjectBoxModel(), directory: directory.path);
    seedStatusProgram(store);
    final library = ObjectBoxWorkoutLibraryRepository(store);
    for (final name in ['Plan A', 'Plan B', 'Plan C']) {
      library.savePlan(
        uuid: name,
        name: name,
        description: '',
        exercises: const [],
      );
    }
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  Future<void> pumpApp(WidgetTester tester, String location) async {
    final auth = AccountAuthController(
      FakeAuthApi(),
      FakeBoundAccountStore(),
      FakeDeletionRecoveryStore(),
      cleanupStore: FakeConfirmedDeletionCleanupStore(),
      localCleaner: FakeLocalAccountDataCleaner(),
    );
    addTearDown(auth.dispose);
    final clock = DateTime(2026, 11, 25, 10);
    await tester.pumpWidget(
      ProviderScope(
        // A fresh scope per pump so each size starts from clean state.
        key: UniqueKey(),
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          workoutHistoryRepositoryProvider.overrideWithValue(
            _ImmediateHistory(store),
          ),
          accountAuthControllerProvider.overrideWithValue(auth),
          fakeHealthSummary(
            FakeHealthSummaryController(
              HealthConnected(
                readAt: overviewReadAt,
                platform: HealthPlatformKind.appleHealth,
              ),
            ),
          ),
          fakeHealthOverview(FakeHealthOverviewController(overview())),
          healthReaderProvider.overrideWithValue(FakeHealthReader()),
          healthOwnerIdProvider.overrideWithValue('synthetic-owner'),
          healthClockProvider.overrideWithValue(() => overviewReadAt),
          localNowProvider.overrideWithValue(clock),
          workoutClockProvider.overrideWithValue(() => clock),
          catalogRepositoryProvider.overrideWithValue(
            StubCatalogRepository(readyPrograms(), directory),
          ),
        ],
        child: const BeyondRepApp(),
      ),
    );
    await tester.pumpAndSettle();
    if (location != '/today') {
      GoRouter.of(tester.element(find.byType(AdaptiveShell))).go(location);
      await tester.pumpAndSettle();
    }
  }

  for (final location in _locations) {
    testWidgets('$location renders without overflow at every size', (
      tester,
    ) async {
      for (final size in _sizes) {
        for (final brightness in Brightness.values) {
          for (final scale in [1.0, 2.0]) {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.platformBrightnessTestValue = brightness;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.reset);
            addTearDown(tester.platformDispatcher.clearAllTestValues);
            await pumpApp(tester, location);
            expect(
              tester.takeException(),
              isNull,
              reason: '$location at $size, $brightness, x$scale',
            );
          }
        }
      }
    });
  }

  testWidgets('phone sizes never show a detail pane', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final location in ['/progress', '/train/exercises']) {
      await pumpApp(tester, location);
      expect(
        find.descendant(
          of: find.byType(NsListDetail),
          matching: find.byType(VerticalDivider),
        ),
        findsNothing,
        reason: location,
      );
    }
  });
}
