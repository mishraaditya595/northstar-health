import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/features/progress/muscle_map.dart';
import 'package:northstar_health/features/progress/muscle_recovery.dart';

void main() {
  test('sample data is flagged and clamps unknown muscles to recovered', () {
    expect(MuscleRecovery.sample.isSample, isTrue);
    expect(MuscleRecovery.sample.loadOf(Muscle.chest), greaterThan(.5));
    expect(MuscleRecovery.sample.loadOf(Muscle.calves), 0);
    expect(
      const MuscleRecovery({Muscle.abs: 4}, isSample: false).loadOf(Muscle.abs),
      1,
    );
  });

  testWidgets('card draws front and back figures and says it is sample data', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: MuscleRecoveryCard())),
      ),
    );
    expect(find.text('Muscle Recovery'), findsOneWidget);
    expect(find.text('Sample data'), findsOneWidget);
    expect(find.byType(MuscleMap), findsNWidgets(2));
    expect(find.textContaining('not from your workouts'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Body map, sample data')),
      findsOneWidget,
    );
  });

  testWidgets('real data replaces the sample label through the provider', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          muscleRecoveryProvider.overrideWithValue(
            const MuscleRecovery({Muscle.quads: 1}, isSample: false),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: MuscleRecoveryCard())),
      ),
    );
    expect(find.text('Sample data'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('Recently trained: quads')),
      findsOneWidget,
    );
  });

  testWidgets('figures are labelled front and back', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: MuscleRecoveryCard())),
      ),
    );
    expect(find.text('FRONT'), findsOneWidget);
    expect(find.text('BACK'), findsOneWidget);
  });

  testWidgets('lists the recently trained muscles in plain words', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          muscleRecoveryProvider.overrideWithValue(
            const MuscleRecovery({
              Muscle.lowerBack: 1,
              Muscle.chest: .8,
              Muscle.abs: .2,
            }, isSample: false),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: MuscleRecoveryCard())),
      ),
    );
    // Hardest-trained first; lightly worked muscles stay off the list.
    expect(find.text('Lower back · Chest'), findsOneWidget);
    expect(find.textContaining('Abs'), findsNothing);
  });

  testWidgets('says so when nothing was trained recently', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          muscleRecoveryProvider.overrideWithValue(
            const MuscleRecovery({}, isSample: false),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: MuscleRecoveryCard())),
      ),
    );
    expect(find.text('No muscle group trained recently'), findsOneWidget);
  });
}
