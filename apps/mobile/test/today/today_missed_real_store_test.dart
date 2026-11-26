import 'dart:io';

import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/dialogs.dart';
import 'package:beyondrep/core/storage/objectbox_store_provider.dart';
import 'package:beyondrep/features/account/account_auth_controller.dart';
import 'package:beyondrep/features/account/account_auth_provider.dart';
import 'package:beyondrep/features/catalog/domain/catalog_programs.dart';
import 'package:beyondrep/features/catalog/domain/catalog_templates.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/programs/data/objectbox_program_repository.dart';
import 'package:beyondrep/features/today/today_page.dart';
import 'package:beyondrep/features/train/active_workout_state.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fake_account_auth.dart';
import '../support/fake_health_summary.dart';
import '../train/program_test_support.dart';

/// Today's missed line, with a real account store, down to the stored date.
void main() {
  late Directory directory;
  late Store store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-missed-');
    store = Store(getObjectBoxModel(), directory: directory.path);
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  testWidgets('tapping the missed line stores the missed date on the session', (
    tester,
  ) async {
    // Monday-first prog.three: push Mon, pull Wed, legs-ish Fri. Activated
    // Monday 2026-11-23, now Tuesday: Monday's push is missed.
    final snapshot = programsSnapshot();
    final program = browsablePrograms(snapshot)
        .firstWhere((p) => p.id == 'prog.three');
    final ids = program.week.whereType<String>().toSet();
    final created = ObjectBoxProgramRepository(store).importProgram(
      requestUuid: 'real-store-program',
      program: program,
      templateRows: {
        for (final id in ids)
          id: templateRowInputs(programTemplate(snapshot, id)!, snapshot),
      },
      templateNames: {
        for (final id in ids) id: programTemplate(snapshot, id)!.name,
      },
      release: 4,
      firstDayWeekday: 1,
      makeActive: true,
      localToday: DateTime(2026, 11, 23),
    );
    final now = DateTime(2026, 11, 24, 18);

    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        GoRoute(
          path: '/today',
          builder: (_, _) => const Scaffold(body: TodayPage()),
        ),
        GoRoute(
          path: '/train/workout',
          builder: (_, _) => const Scaffold(body: Text('LOGGER')),
        ),
      ],
    );
    addTearDown(router.dispose);
    final auth = AccountAuthController(
      FakeAuthApi(),
      FakeBoundAccountStore(),
      FakeDeletionRecoveryStore(),
      cleanupStore: FakeConfirmedDeletionCleanupStore(),
      localCleaner: FakeLocalAccountDataCleaner(),
    );
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          localNowProvider.overrideWithValue(now),
          workoutClockProvider.overrideWithValue(() => now),
          accountAuthControllerProvider.overrideWithValue(auth),
          fakeHealthSummary(
            FakeHealthSummaryController(
              const HealthNotConnected(
                availability: HealthAvailability.available,
                platform: HealthPlatformKind.appleHealth,
              ),
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: BeyondRepTheme.build(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Missed Monday'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(NsDialog), matching: find.text('Start')),
    );
    await tester.pumpAndSettle();

    expect(find.text('LOGGER'), findsOneWidget);
    final stored = store.box<WorkoutSessionEntity>().getAll().single;
    expect(stored.programUuid, created.uuid);
    expect(stored.programDayLocalDate, '2026-11-23');
    expect(stored.status, 'inProgress');

    await tester.pumpWidget(const SizedBox());
  });
}
