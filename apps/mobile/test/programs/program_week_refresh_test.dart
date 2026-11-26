import 'dart:io';

import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/storage/objectbox_store_provider.dart';
import 'package:beyondrep/features/catalog/domain/catalog_programs.dart';
import 'package:beyondrep/features/catalog/domain/catalog_templates.dart';
import 'package:beyondrep/features/programs/application/program_providers.dart';
import 'package:beyondrep/features/programs/data/objectbox_program_repository.dart';
import 'package:beyondrep/features/programs/domain/program_models.dart';
import 'package:beyondrep/features/programs/domain/program_schedule.dart';
import 'package:beyondrep/features/programs/domain/program_status.dart';
import 'package:beyondrep/features/train/active_workout_page.dart';
import 'package:beyondrep/features/train/active_workout_state.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../train/program_test_support.dart';

/// Finishing or discarding through the real active workout page refreshes the
/// cached program week without anything watching the workout provider.
void main() {
  late Directory directory;
  late Store store;
  late ProviderContainer container;
  final now = DateTime(2026, 11, 25, 10); // Wednesday, day 0 below

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-week-page-');
    store = Store(getObjectBoxModel(), directory: directory.path);
    container = ProviderContainer(
      overrides: [
        objectBoxStoreProvider.overrideWithValue(store),
        localNowProvider.overrideWith((ref) => now),
        workoutClockProvider.overrideWithValue(() => now),
      ],
    );
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  TrainingProgramRecord seed() {
    final snapshot = programsSnapshot();
    final program = browsablePrograms(snapshot)
        .firstWhere((p) => p.id == 'prog.three');
    final ids = program.week.whereType<String>().toSet();
    return ObjectBoxProgramRepository(store).importProgram(
      requestUuid: 'req',
      program: program,
      templateRows: {
        for (final id in ids)
          id: templateRowInputs(programTemplate(snapshot, id)!, snapshot),
      },
      templateNames: {
        for (final id in ids) id: programTemplate(snapshot, id)!.name,
      },
      release: 4,
      firstDayWeekday: 3,
      makeActive: true,
      localToday: now,
    );
  }

  Future<void> run(
    WidgetTester tester, {
    required String tapFirst,
    required String confirm,
    required ProgramDayStatus expected,
  }) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final program = seed();
    final planUuid = dayFor(program, now).planUuid;
    container
        .read(workoutActionsProvider)
        .startProgramDay(program, expectedPlanUuid: planUuid);
    // Cached while the workout runs, like Today or Your program would.
    final sub = container.listen(programWeekProvider, (_, _) {});
    expect(sub.read()!.todayRow!.status, ProgramDayStatus.today);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: BeyondRepTheme.build(Brightness.light),
          home: const ActiveWorkoutPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      tapFirst == 'Discard workout'
          ? find.byTooltip('Discard workout')
          : find.text(tapFirst),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(confirm));
    await tester.pumpAndSettle();
    expect(sub.read()!.todayRow!.status, expected);

    sub.close();
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  }

  testWidgets('finishing marks the day done', (tester) async {
    await run(
      tester,
      tapFirst: 'Finish',
      confirm: 'Finish workout',
      expected: ProgramDayStatus.done,
    );
  });

  testWidgets('discarding leaves the day as today', (tester) async {
    await run(
      tester,
      tapFirst: 'Discard workout',
      confirm: 'Discard workout',
      expected: ProgramDayStatus.today,
    );
  });
}
