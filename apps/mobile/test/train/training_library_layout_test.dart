import 'dart:io';

import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../today/today_program_test_support.dart';
import 'training_library_harness.dart';

/// The app shell caps page width at this (AdaptiveShell).
const _shellMaxWidth = 1120.0;

void main() {
  late Directory directory;
  late Store store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-layout-');
    store = Store(getObjectBoxModel(), directory: directory.path);
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  // Each screen: where it is, and its primary action (if any).
  final screens = <String, ({String location, String? action, String? tip})>{
    'exercise catalogue': (
      location: '/train/exercises',
      action: null,
      tip: null,
    ),
    'exercise detail': (
      location: '/train/exercises/builtin.v1.synthetic-move-1',
      action: null,
      tip: null,
    ),
    'workouts list': (
      location: '/train/workouts',
      action: null,
      tip: 'Filters',
    ),
    'template detail': (
      location: '/train/workouts/tpl.push',
      action: 'Copy to My Plans',
      tip: null,
    ),
    'programs list': (
      location: '/train/programs',
      action: null,
      tip: 'Filters',
    ),
    'program detail': (
      location: '/train/programs/prog.three',
      action: 'Add program',
      tip: null,
    ),
    'retired detail': (
      location: '/train/workouts/tpl.old',
      action: null,
      tip: null,
    ),
  };

  Future<void> reachable(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(finder.hitTestable(), findsOneWidget);
  }

  Future<void> checkScreen(
    WidgetTester tester,
    String name,
    Size size,
    Brightness brightness,
    double textScale,
  ) async {
    final screen = screens[name]!;
    await pumpLibraryScreen(
      tester,
      store: store,
      directory: directory,
      location: screen.location,
      size: size,
      brightness: brightness,
      textScale: textScale,
    );
    expect(tester.takeException(), isNull, reason: '$name overflowed');
    if (screen.tip != null) {
      await tester.tap(find.byTooltip(screen.tip!));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$name sheet overflowed');
      final sheetList = find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      // Scroll the sheet to its end: its last buttons must not sit under the
      // shell's floating nav bar.
      await tester.drag(sheetList, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(
        find.text('Show results').hitTestable(),
        findsOneWidget,
        reason: '$name: Show results is covered',
      );
      expect(
        find.text('Clear').hitTestable(),
        findsOneWidget,
        reason: '$name: Clear is covered',
      );
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();
    }
    if (screen.action != null) {
      await reachable(tester, find.text(screen.action!));
    }
    expect(tester.takeException(), isNull, reason: '$name overflowed');
    final list = find.byType(ListView);
    if (list.evaluate().isNotEmpty) {
      expect(
        tester.getSize(list.first).width,
        lessThanOrEqualTo(_shellMaxWidth),
        reason: '$name is wider than the shell maximum',
      );
    }
  }

  for (final entry in librarySizes.entries) {
    for (final brightness in Brightness.values) {
      group('${entry.key} ${brightness.name}', () {
        for (final name in screens.keys) {
          testWidgets(name, (tester) async {
            await checkScreen(tester, name, entry.value, brightness, 1);
          });
        }

        testWidgets('your program', (tester) async {
          final uuid = seedStatusProgram(store);
          await pumpLibraryScreen(
            tester,
            store: store,
            directory: directory,
            location: '/train/program/$uuid',
            size: entry.value,
            brightness: brightness,
            now: DateTime(2026, 11, 26, 10),
          );
          expect(tester.takeException(), isNull);
          await reachable(tester, find.text('Start for Wednesday'));
          expect(tester.takeException(), isNull);
        });

        testWidgets('Today program card', (tester) async {
          await pumpTodayProgram(
            tester,
            week: programWeekFixture(),
            size: entry.value,
            brightness: brightness,
            shell: true,
          );
          expect(tester.takeException(), isNull);
          await reachable(tester, find.text('Open program'));
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(
            find.text('Start'),
            -200,
            scrollable: find.byType(Scrollable).first,
          );
          // The Today screen is built for a phone; Start must stay reachable.
          expect(find.text('Start').hitTestable(), findsOneWidget);
        });
      });
    }
  }

  const split = Size(507, 1024);
  for (final brightness in Brightness.values) {
    group('split view text scale 2.0 ${brightness.name}', () {
      for (final name in screens.keys) {
        testWidgets(name, (tester) async {
          await checkScreen(tester, name, split, brightness, 2);
        });
      }

      testWidgets('your program', (tester) async {
        final uuid = seedStatusProgram(store);
        await pumpLibraryScreen(
          tester,
          store: store,
          directory: directory,
          location: '/train/program/$uuid',
          size: split,
          brightness: brightness,
          textScale: 2,
          now: DateTime(2026, 11, 26, 10),
        );
        await reachable(tester, find.text('Start for Wednesday'));
        expect(tester.takeException(), isNull);
      });

      testWidgets('Today program card', (tester) async {
        await pumpTodayProgram(
          tester,
          week: programWeekFixture(),
          size: split,
          brightness: brightness,
          textScale: 2,
          shell: true,
        );
        await reachable(tester, find.text('Open program'));
        expect(tester.takeException(), isNull);
      });
    });
  }
}
