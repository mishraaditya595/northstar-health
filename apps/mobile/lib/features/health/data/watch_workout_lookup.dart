import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/objectbox_store_provider.dart';
import '../../../objectbox.g.dart';
import '../../workouts/data/workout_entities.dart';
import '../domain/workout_health_export.dart';

/// The stored workout with this UUID as the export planner sees it, or null
/// when the phone holds none. No health values.
typedef WatchWorkoutLookup = ExportCandidate? Function(String uuid);

ExportCandidate? watchWorkoutCandidate(Store store, String uuid) {
  final query = store
      .box<WorkoutSessionEntity>()
      .query(WorkoutSessionEntity_.uuid.equals(uuid.toLowerCase()))
      .build();
  try {
    final s = query.findFirst();
    if (s == null) return null;
    return ExportCandidate(
      uuid: s.uuid.toLowerCase(),
      name: s.name,
      origin: s.origin,
      status: s.status,
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        s.startedAtMs,
        isUtc: true,
      ),
      completedAt: s.completedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(s.completedAtMs!, isUtc: true),
      deleted: s.deletedAtMs != null,
      version: s.updatedAtMs,
      offsetMinutes: s.originalOffsetMinutes,
    );
  } finally {
    query.close();
  }
}

/// Reads the signed-in account's store each time, so an account change never
/// leaves a lookup on the old one.
final watchWorkoutLookupProvider = Provider<WatchWorkoutLookup>(
  (ref) =>
      (uuid) => watchWorkoutCandidate(ref.read(objectBoxStoreProvider), uuid),
);
