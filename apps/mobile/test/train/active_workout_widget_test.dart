import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:northstar_health/core/design/northstar_theme.dart';
import 'package:northstar_health/core/storage/objectbox_store_provider.dart';
import 'package:northstar_health/features/train/active_workout_page.dart';
import 'package:northstar_health/features/train/train_page.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_repository.dart';
import 'package:northstar_health/features/workouts/domain/workout_models.dart';
import 'package:northstar_health/objectbox.g.dart';

void main() {
  late Directory directory;
  late Store store;
  late GoRouter router;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('northstar-workout-ui-');
    store = Store(getObjectBoxModel(), directory: directory.path);
    router = GoRouter(initialLocation: '/train', routes: [
      GoRoute(path: '/train', builder: (_, _) => const TrainPage()),
      GoRoute(path: '/train/workout',
          builder: (_, _) => const ActiveWorkoutPage()),
    ]);
  });

  tearDown(() {
    router.dispose();
    store.close();
    directory.deleteSync(recursive: true);
  });

  Future<void> showApp(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [objectBoxStoreProvider.overrideWithValue(store)],
      child: MaterialApp.router(
        theme: NorthstarTheme.build(Brightness.light),
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('quick workout records real sets and finishes locally',
      (tester) async {
    await showApp(tester);
    await tester.tap(find.text('Quick workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
    expect(find.text('Workout in progress'), findsOneWidget);

    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Barbell bench press').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add set'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(
        const ValueKey('unused-reps-key')), '8');
  });
}
