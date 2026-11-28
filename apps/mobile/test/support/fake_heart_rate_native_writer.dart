import 'package:beyondrep/features/health/data/health_workout_writer.dart';

/// Records the single native heart rate write and delete of a watch workout.
class FakeHeartRateNativeWriter implements HeartRateNativeWriter {
  HealthWriteResult writeResult = const HealthWriteOk('hr-record');
  HealthWriteResult deleteResult = const HealthWriteOk('');
  final writes =
      <
        ({
          String clientRecordId,
          int version,
          DateTime start,
          DateTime end,
          int offsetMinutes,
          List<HeartRateMinute> samples,
        })
      >[];
  final deletes = <String>[];

  @override
  Future<HealthWriteResult> write({
    required String clientRecordId,
    required int version,
    required DateTime start,
    required DateTime end,
    required int offsetMinutes,
    required List<HeartRateMinute> samples,
  }) async {
    writes.add((
      clientRecordId: clientRecordId,
      version: version,
      start: start,
      end: end,
      offsetMinutes: offsetMinutes,
      samples: samples,
    ));
    return writeResult;
  }

  @override
  Future<HealthWriteResult> delete(String clientRecordId) async {
    deletes.add(clientRecordId);
    return deleteResult;
  }
}
