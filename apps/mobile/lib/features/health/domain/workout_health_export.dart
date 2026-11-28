import 'health_export_state.dart';

/// A BeyondRep workout as the export planner sees it. No health values.
class ExportCandidate {
  const ExportCandidate({
    required this.uuid,
    required this.name,
    required this.origin,
    required this.status,
    required this.startedAt,
    required this.completedAt,
    required this.deleted,
    required this.version,
    required this.offsetMinutes,
  });

  /// Lowercase workout UUID.
  final String uuid;
  final String name;
  final String origin;
  final String status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final bool deleted;

  /// The workout `updatedAtMs`: grows on every edit, restore or conflict
  /// recovery, and is used as the platform record version.
  final int version;
  final int offsetMinutes;
}

/// What this phone last did for one workout (a local receipt row).
class ExportReceiptView {
  const ExportReceiptView({
    required this.workoutUuid,
    required this.state,
    required this.exportedVersion,
    required this.platformRecordId,
    required this.attempts,
    required this.lastAttemptAt,
  });

  final String workoutUuid;
  final HealthExportState state;
  final int exportedVersion;
  final String? platformRecordId;
  final int attempts;
  final DateTime lastAttemptAt;
}

sealed class ExportAction {
  const ExportAction();
}

class WriteWorkout extends ExportAction {
  const WriteWorkout(this.candidate, {required this.resumeUncertain});
  final ExportCandidate candidate;

  /// A previous attempt may have reached the platform without a receipt.
  final bool resumeUncertain;
}

class DeleteOwnCopy extends ExportAction {
  const DeleteOwnCopy(this.workoutUuid, this.platformRecordId);
  final String workoutUuid;
  final String? platformRecordId;
}

class SupersedeByWatch extends ExportAction {
  const SupersedeByWatch(this.workoutUuid, this.platformRecordId);
  final String workoutUuid;
  final String? platformRecordId;
}

/// iOS only: a deleted workout with no receipt may still have an own copy
/// written by another iPhone on the same Apple ID.
class LookupDeletedCopy extends ExportAction {
  const LookupDeletedCopy(this.candidate);
  final ExportCandidate candidate;
}

const _watchSettleDelay = Duration(minutes: 10);
const _maxBackoff = Duration(minutes: 60);

/// How long a receipt with [attempts] failed tries waits before the next one.
Duration healthExportBackoff(int attempts) {
  final exponent = (attempts < 1 ? 1 : attempts) - 1;
  if (exponent >= 6) return _maxBackoff;
  final d = Duration(minutes: 1 << exponent);
  return d > _maxBackoff ? _maxBackoff : d;
}

/// Decides what the exporter must do. Pure: no platform or storage access.
/// Deletes and supersedes come first and are not capped; writes are oldest
/// first and cut at [maxWrites].
List<ExportAction> planHealthExport({
  required List<ExportCandidate> workouts,
  required Map<String, ExportReceiptView> receipts,
  required Set<String> watchLinkedWorkoutUuids,
  required bool watchPaired,
  required bool isIos,
  required DateTime now,
  int maxWrites = 50,
}) {
  final removals = <ExportAction>[];
  final writes = <WriteWorkout>[];

  for (final w in workouts) {
    final completedAt = w.completedAt;
    if (w.status != 'completed' || completedAt == null) continue;
    final receipt = receipts[w.uuid];
    final state = receipt?.state;
    // A watch workout is written by the watch health inbox, never here; this
    // pass only removes its copy once the workout is deleted (Wear OS 3b).
    // On iOS the HealthKit entry belongs to the Apple Watch: never touched.
    if (w.origin == 'beyondrep_watch') {
      if (!isIos &&
          w.deleted &&
          receipt != null &&
          state != HealthExportState.deleted &&
          !(state == HealthExportState.deleting &&
              receipt.attempts > 0 &&
              now.difference(receipt.lastAttemptAt) <
                  healthExportBackoff(receipt.attempts))) {
        removals.add(DeleteOwnCopy(w.uuid, receipt.platformRecordId));
      }
      continue;
    }
    if (w.origin != 'northstar_phone') continue;
    // Any receipt other than the final states may stand for a copy in the
    // health store (a failed or blocked rewrite keeps the earlier one).
    final mayHaveCopy =
        receipt != null &&
        state != HealthExportState.skippedWatch &&
        state != HealthExportState.supersededByWatch &&
        state != HealthExportState.deleted;

    if (watchLinkedWorkoutUuids.contains(w.uuid)) {
      if (mayHaveCopy) {
        removals.add(SupersedeByWatch(w.uuid, receipt.platformRecordId));
      }
      continue;
    }
    if (w.deleted) {
      if (mayHaveCopy) {
        if (state == HealthExportState.deleting &&
            receipt.attempts > 0 &&
            now.difference(receipt.lastAttemptAt) <
                healthExportBackoff(receipt.attempts)) {
          continue;
        }
        removals.add(DeleteOwnCopy(w.uuid, receipt.platformRecordId));
      } else if (receipt == null && isIos) {
        removals.add(LookupDeletedCopy(w));
      }
      continue;
    }
    if (state == HealthExportState.skippedWatch ||
        state == HealthExportState.supersededByWatch) {
      continue;
    }
    if (state == HealthExportState.confirmed &&
        receipt!.exportedVersion >= w.version) {
      continue;
    }
    if (state == HealthExportState.failedRetryable &&
        now.difference(receipt!.lastAttemptAt) <
            healthExportBackoff(receipt.attempts)) {
      continue;
    }
    if (isIos &&
        watchPaired &&
        now.difference(completedAt) < _watchSettleDelay) {
      continue;
    }
    writes.add(
      WriteWorkout(w, resumeUncertain: state == HealthExportState.writing),
    );
  }

  writes.sort(
    (a, b) => a.candidate.completedAt!.compareTo(b.candidate.completedAt!),
  );
  return [...removals, ...writes.take(maxWrites)];
}
