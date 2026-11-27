import 'dart:io';

import 'package:beyondrep/features/watch/data/watch_workout_receipt_entity.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workouts/fixtures/objectbox_pre_watch_receipts.g.dart' as legacy;

void main() {
  test('pre-receipt database upgrades and keeps sessions', () {
    final dir = Directory.systemTemp.createTempSync('beyondrep-receipts-');
    try {
      final old = Store(legacy.getObjectBoxModel(), directory: dir.path);
      old.box<WorkoutSessionEntity>().put(
        WorkoutSessionEntity(
          uuid: '00000000-0000-4000-8000-000000000101',
          name: 'Old session',
          startedAtMs: 1,
          originalOffsetMinutes: 0,
          updatedAtMs: 1,
        ),
      );
      old.close();

      final upgraded = Store(getObjectBoxModel(), directory: dir.path);
      try {
        final session = upgraded.box<WorkoutSessionEntity>().getAll().single;
        expect(session.name, 'Old session');
        final receipts = upgraded.box<WatchWorkoutReceiptEntity>();
        expect(receipts.isEmpty(), isTrue);
        receipts.put(
          WatchWorkoutReceiptEntity(
            workoutUuid: '00000000-0000-4000-8000-000000000101',
            messageId: '00000000-0000-4000-8000-000000000a01',
            platformWorkoutUuid: '11111111-2222-4333-8444-555555555555',
            receivedAtMs: 5,
          ),
        );
        final row = receipts.getAll().single;
        expect(row.platformWorkoutUuid, '11111111-2222-4333-8444-555555555555');
        expect(row.receivedAtMs, 5);
      } finally {
        upgraded.close();
      }
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('receipt workout and message ids are unique', () {
    final dir = Directory.systemTemp.createTempSync('beyondrep-receipts-');
    final store = Store(getObjectBoxModel(), directory: dir.path);
    try {
      final box = store.box<WatchWorkoutReceiptEntity>();
      box.put(
        WatchWorkoutReceiptEntity(
          workoutUuid: 'w1',
          messageId: 'm1',
          receivedAtMs: 1,
        ),
      );
      expect(
        () => box.put(
          WatchWorkoutReceiptEntity(
            workoutUuid: 'w1',
            messageId: 'm2',
            receivedAtMs: 2,
          ),
        ),
        throwsA(isA<UniqueViolationException>()),
      );
      expect(
        () => box.put(
          WatchWorkoutReceiptEntity(
            workoutUuid: 'w2',
            messageId: 'm1',
            receivedAtMs: 2,
          ),
        ),
        throwsA(isA<UniqueViolationException>()),
      );
    } finally {
      store.close();
      dir.deleteSync(recursive: true);
    }
  });
}
