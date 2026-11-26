import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/health_reader.dart';
import '../domain/health_types.dart';
import 'health_summary_controller.dart';

typedef WorkoutWindow = ({DateTime start, DateTime end});

/// Mean of the real heart rate samples inside [WorkoutWindow], bpm; null when
/// there are none, the read is not allowed or fails, or the account changed
/// during the read. Read on demand and held in memory only.
final workoutAverageHrProvider = FutureProvider.autoDispose
    .family<double?, WorkoutWindow>((ref, window) async {
      final owner = ref.watch(healthOwnerIdProvider);
      if (owner == null) return null;
      final SeriesResult<List<HealthSample>> result;
      try {
        result = await ref
            .read(healthReaderProvider)
            .readSeries(HealthSeriesType.heartRate, window.start, window.end);
      } catch (_) {
        return null;
      }
      if (!ref.mounted || ref.read(healthOwnerIdProvider) != owner) return null;
      if (result is! SeriesData<List<HealthSample>> || result.data.isEmpty) {
        return null;
      }
      final values = result.data.map((s) => s.value);
      return values.reduce((a, b) => a + b) / result.data.length;
    });
