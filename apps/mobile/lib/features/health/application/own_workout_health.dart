import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/health_connection_repository.dart';
import '../data/health_reader.dart';
import '../domain/own_workout_health.dart';
import 'health_summary_controller.dart';

/// Lowercase HKWorkout UUID of an imported Apple Watch workout, from its
/// receipt; null without one. Overridden by the signed-in scope; the health
/// layer never reads storage itself.
final watchWorkoutPlatformIdProvider = Provider.family<String?, String>(
  (ref, workoutUuid) => null,
);

typedef OwnWorkoutKey = ({String workoutUuid, DateTime start, DateTime end});

/// Heart rate and active energy Apple Health holds for one watch workout,
/// read fresh and held in memory only. Null when there is no receipt, health
/// is not connected for the signed-in account, the read is anything but data,
/// or no value exists, so nothing is shown instead of a zero.
final ownWorkoutHealthProvider = FutureProvider.autoDispose
    .family<OwnWorkoutHealth?, OwnWorkoutKey>((ref, key) async {
      final owner = ref.watch(healthOwnerIdProvider);
      if (owner == null) return null;
      final platformId = ref.watch(
        watchWorkoutPlatformIdProvider(key.workoutUuid),
      );
      if (platformId == null) return null;
      if (!ref.read(healthConnectionRepositoryProvider).isConnected(owner)) {
        return null;
      }
      final SeriesResult<OwnWorkoutHealth?> result;
      try {
        result = await ref
            .read(healthReaderProvider)
            .readOwnWorkout(platformId, key.start, key.end);
      } catch (_) {
        return null;
      }
      if (!ref.mounted || ref.read(healthOwnerIdProvider) != owner) return null;
      if (result is! SeriesData<OwnWorkoutHealth?>) return null;
      final data = result.data;
      return data == null || data.isEmpty ? null : data;
    });
