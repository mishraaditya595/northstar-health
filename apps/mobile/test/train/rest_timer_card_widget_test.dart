import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/features/train/rest_timer_card.dart';
import 'package:northstar_health/features/workouts/domain/live_workout_engine.dart';

void main() {
  testWidgets(
    'replacing a running rest deadline keeps ticking past the old one',
    (tester) async {
      final origin = DateTime.utc(2026, 10, 24, 8);
      var clock = origin;
      var checkpoint = WorkoutRecoveryCheckpoint(
        sessionUuid: 'session-a',
        checkpointRevision: 2,
        restState: 'running',
        restDeadlineUtcMs: origin
            .add(const Duration(seconds: 60))
            .millisecondsSinceEpoch,
      );
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, rebuild) {
                update = rebuild;
                return RestTimerCard(
                  checkpoint: checkpoint,
                  runningWorkout: true,
                  nowUtc: () => clock,
                  onStart: (_) {},
                  onClear: () {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('1:00'), findsOneWidget);

      clock = origin.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('0:30'), findsOneWidget);

      update(
        () => checkpoint = WorkoutRecoveryCheckpoint(
          sessionUuid: 'session-a',
          checkpointRevision: 3,
          restState: 'running',
          restDeadlineUtcMs: clock
              .add(const Duration(seconds: 120))
              .millisecondsSinceEpoch,
        ),
      );
      await tester.pump();
      expect(find.text('2:00'), findsOneWidget);

      // Advance BEYOND the original 60-second deadline: the old ticker
      // used to cancel here and freeze the new timer.
      clock = origin.add(const Duration(seconds: 61));
      await tester.pump(const Duration(seconds: 31));
      expect(find.text('1:29'), findsOneWidget);

      clock = origin.add(const Duration(seconds: 71));
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('1:19'), findsOneWidget);
    },
  );
}
