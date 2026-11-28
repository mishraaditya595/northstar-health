import 'dart:io';

import 'package:beyondrep/features/health/data/health_export_entities.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workouts/fixtures/objectbox_pre_health_export.g.dart' as legacy;

void main() {
  test('pre-export database upgrades, keeps sessions, accepts new rows', () {
    final dir = Directory.systemTemp.createTempSync('beyondrep-hexport-mig-');
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
        expect(
          upgraded.box<WorkoutSessionEntity>().getAll().single.name,
          'Old session',
        );
        final settings = upgraded.box<HealthExportSettingEntity>();
        final receipts = upgraded.box<HealthExportReceiptEntity>();
        expect(settings.isEmpty(), isTrue);
        expect(receipts.isEmpty(), isTrue);
        settings.put(
          HealthExportSettingEntity(ownerAccountId: 'a', enabledAtMs: 3),
        );
        receipts.put(
          HealthExportReceiptEntity(
            workoutUuid: 'w',
            platform: 'healthkit',
            state: 'confirmed',
            updatedAtMs: 4,
          ),
        );
        expect(settings.count(), 1);
        expect(receipts.getAll().single.state, 'confirmed');
      } finally {
        upgraded.close();
      }
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
