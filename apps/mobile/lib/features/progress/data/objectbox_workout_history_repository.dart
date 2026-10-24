import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/objectbox_store_provider.dart';
import '../../../objectbox.g.dart';
import '../../workouts/data/objectbox_workout_repository.dart';
import '../../workouts/data/workout_entities.dart';
import '../../workouts/domain/workout_models.dart';
import '../domain/workout_history_models.dart';

abstract interface class WorkoutHistoryRepository {
  WorkoutHistorySnapshot readCompleted();
}

final workoutHistoryRepositoryProvider = Provider<WorkoutHistoryRepository>(
  (ref) => ObjectBoxWorkoutHistoryRepository(
    ref.watch(objectBoxStoreProvider),
  ),
);

/// Read-only projection of the SAME local workout Store; never materialize
/// health imports, active drafts, discarded or unknown-status sessions.
class ObjectBoxWorkoutHistoryRepository implements WorkoutHistoryRepository {
  ObjectBoxWorkoutHistoryRepository(Store store)
      : _store = store,
        _sessions = store.box<WorkoutSessionEntity>(),
        _workouts = ObjectBoxWorkoutRepository(store);

  final Store _store;
  final Box<WorkoutSessionEntity> _sessions;
  final ObjectBoxWorkoutRepository _workouts;

  @override
  WorkoutHistorySnapshot readCompleted() {
    // Consistent across aggregate reads: a concurrent finish cannot leak a
    // half-completed session. Each aggregate is reused from the repository.
    return _store.runInTransaction(TxMode.read, () {
      final query = _sessions.query(
        WorkoutSessionEntity_.status.equals(WorkoutStatus.completed.name),
      ).build();
      try {
        final rows = query.find()
            .where((s) => s.deletedAtMs == null &&
                s.completedAtMs != null &&
                s.origin == 'northstar_phone')
            .toList()
          ..sort((a, b) {
            final descending = b.completedAtMs!.compareTo(a.completedAtMs!);
            return descending != 0
                ? descending
                : a.uuid.compareTo(b.uuid);
          });
        final completed = <WorkoutSessionRecord>[];
        for (final row in rows) {
          final session = _workouts.getSession(row.uuid);
          if (session != null &&
              session.status == WorkoutStatus.completed &&
              session.completedAtUtc != null) {
            completed.add(session);
          }
        }
        return WorkoutHistorySnapshot(sessions: List.unmodifiable(completed));
      } finally {
        query.close();
      }
    });
  }
}
