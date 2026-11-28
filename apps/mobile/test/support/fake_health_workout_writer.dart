import 'package:beyondrep/features/health/data/health_workout_writer.dart';

/// Scripted [HealthWorkoutWriter] with an in-memory store, for exporter and
/// controller tests. Records every call; never touches a platform.
class FakeHealthWorkoutWriter implements HealthWorkoutWriter {
  FakeHealthWorkoutWriter({this.isIos = true});

  @override
  final bool isIos;

  @override
  String get platform => isIos ? 'healthkit' : 'health_connect';

  bool available = true;
  bool writeAccess = true;

  /// Exercise, heart rate and total calories write (Android watch workouts).
  bool watchHealthAccess = true;
  bool accessGrantedByRequest = true;

  /// Results returned by `write`, consumed in order; when empty a write
  /// succeeds with a generated id.
  final List<HealthWriteResult> writeResults = [];
  HealthWriteResult deleteResult = const HealthWriteOk('');

  /// When non-null, `beyondRepWorkoutsIn` returns null (a failed read).
  bool readFails = false;

  /// What the health store holds from BeyondRep sources.
  final List<OwnStoredWorkout> store = [];

  final writes = <HealthWorkoutRecord>[];
  final deletes = <({String workoutUuid, String? platformRecordId})>[];
  final deleteWindows = <({DateTime? start, DateTime? end})>[];
  final lookups = <({DateTime start, DateTime end})>[];
  int requestAccessCalls = 0;
  int watchHealthRequests = 0;

  /// Runs after each `write` call, for tests that flip state mid-pass.
  void Function()? onWrite;

  /// When set, `write` waits for it before it stores the workout.
  Future<void>? writeGate;

  var _next = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> requestAccess({bool watchHealth = false}) async {
    requestAccessCalls++;
    if (watchHealth) watchHealthRequests++;
    if (accessGrantedByRequest) {
      writeAccess = true;
      if (watchHealth) watchHealthAccess = true;
    }
    return watchHealth ? watchHealthAccess : writeAccess;
  }

  @override
  Future<bool> hasWatchHealthWriteAccess() async => watchHealthAccess;

  @override
  Future<bool> hasWriteAccess() async => writeAccess;

  @override
  Future<HealthWriteResult> write(HealthWorkoutRecord r) async {
    writes.add(r);
    await writeGate;
    final result = writeResults.isEmpty
        ? HealthWriteOk(isIos ? 'hk-${_next++}' : r.workoutUuid)
        : writeResults.removeAt(0);
    if (result is HealthWriteOk) {
      store.removeWhere((s) => s.platformRecordId == result.platformRecordId);
      store.add(
        OwnStoredWorkout(
          platformRecordId: result.platformRecordId,
          sourceId: 'in.beyondrep.app',
          start: r.start,
          end: r.end,
        ),
      );
    }
    onWrite?.call();
    return result;
  }

  @override
  Future<HealthWriteResult> delete(
    String workoutUuid,
    String? platformRecordId, {
    DateTime? start,
    DateTime? end,
  }) async {
    deleteWindows.add((start: start, end: end));
    deletes.add((workoutUuid: workoutUuid, platformRecordId: platformRecordId));
    if (deleteResult is HealthWriteOk) {
      store.removeWhere((s) => s.platformRecordId == platformRecordId);
    }
    return deleteResult;
  }

  @override
  Future<List<OwnStoredWorkout>?> beyondRepWorkoutsIn(
    DateTime start,
    DateTime end,
  ) async {
    lookups.add((start: start, end: end));
    if (readFails) return null;
    return [
      for (final s in store)
        if (s.start.isBefore(end) && s.end.isAfter(start)) s,
    ];
  }
}
