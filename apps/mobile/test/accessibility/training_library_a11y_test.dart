import 'dart:io';

import 'package:beyondrep/features/catalog/data/catalog_repository.dart';

import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../today/today_program_test_support.dart';
import '../train/training_library_harness.dart';

void main() {
  late Directory directory;
  late Store store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-a11y-');
    store = Store(getObjectBoxModel(), directory: directory.path);
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  Future<void> expectAccessible(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  }

  Future<void> open(
    WidgetTester tester,
    String location,
    Brightness brightness, {
    DateTime? now,
    CatalogState? state,
  }) => pumpLibraryScreen(
    tester,
    store: store,
    directory: directory,
    location: location,
    brightness: brightness,
    now: now,
    state: state,
  );

  for (final brightness in Brightness.values) {
    group(brightness.name, () {
      late SemanticsHandle semantics;
      setUp(
        () => semantics = TestWidgetsFlutterBinding.instance.ensureSemantics(),
      );
      tearDown(() => semantics.dispose());

      testWidgets('exercise catalogue', (tester) async {
        await open(tester, '/train/exercises', brightness);
        await expectAccessible(tester);
      });

      testWidgets('exercise detail', (tester) async {
        await open(
          tester,
          '/train/exercises/builtin.v1.synthetic-move-1',
          brightness,
        );
        await expectAccessible(tester);
      });

      testWidgets('workouts list with the filter sheet open', (tester) async {
        await open(tester, '/train/workouts', brightness);
        await expectAccessible(tester);
        await tester.tap(find.byTooltip('Filters'));
        await tester.pumpAndSettle();
        await expectAccessible(tester);
      });

      testWidgets('template detail', (tester) async {
        await open(tester, '/train/workouts/tpl.push', brightness);
        await expectAccessible(tester);
      });

      testWidgets('programs list with the filter sheet open', (tester) async {
        await open(tester, '/train/programs', brightness);
        await expectAccessible(tester);
        await tester.tap(find.byTooltip('Filters'));
        await tester.pumpAndSettle();
        await expectAccessible(tester);
      });

      testWidgets('program detail with a day expanded', (tester) async {
        await open(tester, '/train/programs/prog.three', brightness);
        await tester.tap(find.textContaining('Day 1 · Synthetic push'));
        await tester.pumpAndSettle();
        await expectAccessible(tester);
      });

      testWidgets('your program with done, missed and upcoming days', (
        tester,
      ) async {
        final uuid = seedStatusProgram(store);
        await open(
          tester,
          '/train/program/$uuid',
          brightness,
          now: DateTime(2026, 11, 26, 10),
        );
        expect(find.text('Done'), findsOneWidget);
        expect(find.text('Missed'), findsOneWidget);
        expect(find.text('Upcoming'), findsOneWidget);
        await expectAccessible(tester);
      });

      testWidgets('retired template and program detail', (tester) async {
        await open(tester, '/train/workouts/tpl.old', brightness);
        expect(find.text('This workout is no longer available.'), findsOne);
        await expectAccessible(tester);
        await open(tester, '/train/programs/prog.old', brightness);
        expect(find.text('This program is no longer available.'), findsOne);
        await expectAccessible(tester);
      });

      group('Today program card', () {
        testWidgets('training day', (tester) async {
          await pumpTodayProgram(
            tester,
            week: programWeekFixture(),
            brightness: brightness,
          );
          await expectAccessible(tester);
        });

        testWidgets('rest day', (tester) async {
          await pumpTodayProgram(
            tester,
            week: programWeekFixture(now: DateTime(2026, 11, 24, 10)),
            brightness: brightness,
          );
          expect(find.text('Rest day'), findsOneWidget);
          await expectAccessible(tester);
        });

        testWidgets('done for today', (tester) async {
          await pumpTodayProgram(
            tester,
            week: programWeekFixture(
              sessions: [
                programFinished('2026-11-23'),
                programFinished('2026-11-25'),
              ],
            ),
            brightness: brightness,
          );
          expect(find.text('Done for today'), findsOneWidget);
          await expectAccessible(tester);
        });

        testWidgets('missed line', (tester) async {
          await pumpTodayProgram(
            tester,
            week: programWeekFixture(),
            brightness: brightness,
          );
          expect(find.text('Missed Monday: Push day'), findsOneWidget);
          await expectAccessible(tester);
        });
      });
    });
  }

  group('semantics', () {
    late SemanticsHandle semantics;
    setUp(
      () => semantics = TestWidgetsFlutterBinding.instance.ensureSemantics(),
    );
    tearDown(() => semantics.dispose());

    testWidgets('the missed line is announced with its action', (tester) async {
      await pumpTodayProgram(tester, week: programWeekFixture());
      expect(
        find.bySemanticsLabel('Missed Monday: Push day. Start it now'),
        findsOneWidget,
      );
    });

    testWidgets('Your program day tags are announced in words', (tester) async {
      final uuid = seedStatusProgram(store);
      await open(
        tester,
        '/train/program/$uuid',
        Brightness.light,
        now: DateTime(2026, 11, 26, 10),
      );
      // The tag text is merged into the day card's label, so each day is
      // read with its status in words and not only shown by colour.
      expect(
        find.bySemanticsLabel(RegExp(r'Monday[\s\S]*Done')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Wednesday[\s\S]*Missed')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Friday[\s\S]*Upcoming')),
        findsOneWidget,
      );
    });

    testWidgets('the filter button and count are announced', (tester) async {
      await open(tester, '/train/programs', Brightness.light);
      expect(
        find.semantics.byPredicate((node) => node.tooltip == 'Filters'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hypertrophy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Filters (1)'), findsOneWidget);
      expect(find.bySemanticsLabel('Clear'), findsOneWidget);
    });
  });
}
