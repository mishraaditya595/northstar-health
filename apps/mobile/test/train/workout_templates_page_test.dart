import 'dart:io';

import 'package:beyondrep/core/design/beyondrep_theme.dart';
import 'package:beyondrep/core/design/page_header.dart';
import 'package:beyondrep/features/catalog/application/catalog_providers.dart';
import 'package:beyondrep/features/catalog/data/catalog_repository.dart';
import 'package:beyondrep/features/train/workout_templates_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../catalog/catalog_fixtures.dart';
import 'template_test_support.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('beyondrep-tpl-list-');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  Future<(StubCatalogRepository, List<String>)> open(
    WidgetTester tester,
    CatalogState state, {
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = StubCatalogRepository(state, directory);
    final pushed = <String>[];
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const WorkoutTemplatesPage(),
          routes: [
            GoRoute(
              path: 'train/workouts/:id',
              builder: (_, s) {
                pushed.add(s.pathParameters['id']!);
                return const Text('DETAIL');
              },
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [catalogRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(
          theme: BeyondRepTheme.build(brightness),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (repository, pushed);
  }

  testWidgets('lists standalone templates with level, minutes and equipment', (
    tester,
  ) async {
    await open(tester, readyTemplates());
    expect(find.text('Synthetic push'), findsOneWidget);
    expect(find.text('Synthetic pull'), findsOneWidget);
    expect(find.text('Synthetic hidden'), findsNothing);
    expect(find.textContaining('Beginner · 40 min · 2 exercises'), findsOne);
    expect(find.textContaining('Barbell'), findsWidgets);
  });

  testWidgets('search and level chips narrow the list', (tester) async {
    await open(tester, readyTemplates());
    await tester.enterText(find.byType(TextField), 'pull');
    await tester.pumpAndSettle();
    expect(find.text('Synthetic push'), findsNothing);
    expect(find.text('Synthetic pull'), findsOneWidget);
    // The description is searched as well.
    await tester.enterText(
      find.byType(TextField),
      'description for synthetic push',
    );
    await tester.pumpAndSettle();
    expect(find.text('Synthetic push'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Intermediate'));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic pull'), findsOneWidget);
    expect(find.text('Synthetic push'), findsNothing);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Advanced'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Advanced'));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic seven'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('No matching workouts.'), findsOneWidget);
  });

  testWidgets('tapping a template opens its detail route', (tester) async {
    final (_, pushed) = await open(tester, readyTemplates());
    await tester.tap(find.byType(NsListCard).first);
    await tester.pumpAndSettle();
    expect(find.text('DETAIL'), findsOneWidget);
    expect(pushed, ['tpl.pull']);
  });

  testWidgets('without a download it says so and Retry forces a refresh', (
    tester,
  ) async {
    final (repository, _) = await open(
      tester,
      const CatalogState(status: CatalogStatus.unavailable),
    );
    expect(find.textContaining("hasn't downloaded yet"), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(repository.forceCalls, [true]);
  });

  testWidgets('an outdated app says to update', (tester) async {
    await open(tester, const CatalogState(status: CatalogStatus.outdatedApp));
    expect(
      find.text('Update BeyondRep to get the latest exercises.'),
      findsOne,
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('text scale 2.0 does not overflow (${brightness.name})', (
      tester,
    ) async {
      await open(
        tester,
        readyTemplates(),
        brightness: brightness,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  }

  group('filters', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
    }

    Future<void> showResults(WidgetTester tester) async {
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();
    }

    testWidgets('goal narrows the list and shows the count; Clear restores '
        'it', (tester) async {
      await open(tester, readyTemplates());
      expect(find.text('Filters (1)'), findsNothing);
      await openSheet(tester);
      await tester.tap(find.text('Strength'));
      await tester.pumpAndSettle();
      await showResults(tester);
      expect(find.text('Synthetic pull'), findsOneWidget);
      expect(find.text('Synthetic push'), findsNothing);
      expect(find.text('Filters (1)'), findsOneWidget);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic push'), findsOneWidget);
      expect(find.text('Filters (1)'), findsNothing);
    });

    testWidgets('equipment I have, with bodyweight always counted', (
      tester,
    ) async {
      await open(tester, readyTemplates());
      await openSheet(tester);
      expect(find.text('Bodyweight'), findsNothing); // always available
      await tester.tap(find.text('Dumbbell'));
      await tester.pumpAndSettle();
      await showResults(tester);
      expect(find.text('Synthetic pull'), findsOneWidget);
      expect(find.text('Synthetic push'), findsNothing);
      expect(find.text('Synthetic seven'), findsNothing);
    });

    testWidgets('goal and equipment together, with no match', (tester) async {
      await open(tester, readyTemplates());
      await openSheet(tester);
      await tester.tap(find.text('Strength'));
      await tester.tap(find.text('Barbell'));
      await tester.pumpAndSettle();
      await showResults(tester);
      expect(find.text('Filters (2)'), findsOneWidget);
      expect(find.text('No matching workouts.'), findsOneWidget);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic push'), findsOneWidget);
    });

    testWidgets('closing the sheet without Show results changes nothing', (
      tester,
    ) async {
      await open(tester, readyTemplates());
      await openSheet(tester);
      await tester.tap(find.text('Strength'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic push'), findsOneWidget);
      expect(find.text('Filters (1)'), findsNothing);
    });

    testWidgets('the level chips still work with the filters', (tester) async {
      await open(tester, readyTemplates());
      await openSheet(tester);
      await tester.tap(find.text('Dumbbell'));
      await tester.pumpAndSettle();
      await showResults(tester);
      await tester.tap(find.text('Beginner'));
      await tester.pumpAndSettle();
      expect(find.text('No matching workouts.'), findsOneWidget);
    });

    for (final brightness in Brightness.values) {
      testWidgets('the sheet at text scale 2.0 (${brightness.name})', (
        tester,
      ) async {
        await open(
          tester,
          readyTemplates(),
          textScale: 2,
          brightness: brightness,
        );
        await openSheet(tester);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Show results'),
          100,
          scrollable: find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
