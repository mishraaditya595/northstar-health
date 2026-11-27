import 'package:beyondrep/features/health/domain/health_export_state.dart';
import 'package:beyondrep/features/health/domain/workout_health_export.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 11, 27, 12);

ExportCandidate cand(
  String uuid, {
  String origin = 'northstar_phone',
  String status = 'completed',
  DateTime? completedAt,
  bool hasCompletedAt = true,
  bool deleted = false,
  int version = 1,
}) {
  final end = completedAt ?? _now.subtract(const Duration(days: 1));
  return ExportCandidate(
    uuid: uuid,
    name: 'Push day',
    origin: origin,
    status: status,
    startedAt: end.subtract(const Duration(hours: 1)),
    completedAt: hasCompletedAt ? end : null,
    deleted: deleted,
    version: version,
    offsetMinutes: 0,
  );
}

ExportReceiptView rec(
  String uuid,
  HealthExportState state, {
  int exportedVersion = 0,
  String? id,
  int attempts = 0,
  DateTime? lastAttemptAt,
}) => ExportReceiptView(
  workoutUuid: uuid,
  state: state,
  exportedVersion: exportedVersion,
  platformRecordId: id,
  attempts: attempts,
  lastAttemptAt: lastAttemptAt ?? _now,
);

List<ExportAction> plan(
  List<ExportCandidate> workouts, {
  List<ExportReceiptView> receipts = const [],
  Set<String> linked = const {},
  bool watchPaired = false,
  bool isIos = true,
  int maxWrites = 50,
}) => planHealthExport(
  workouts: workouts,
  receipts: {for (final r in receipts) r.workoutUuid: r},
  watchLinkedWorkoutUuids: linked,
  watchPaired: watchPaired,
  isIos: isIos,
  now: _now,
  maxWrites: maxWrites,
);

void main() {
  test('writes a completed phone workout without a receipt', () {
    final actions = plan([cand('a')]);
    expect(actions, hasLength(1));
    final w = actions.single as WriteWorkout;
    expect(w.candidate.uuid, 'a');
    expect(w.resumeUncertain, isFalse);
  });

  test('watch-origin workout is never written even with no receipts', () {
    expect(plan([cand('a', origin: 'beyondrep_watch')]), isEmpty);
  });

  test('a workout that is not completed is never written', () {
    expect(plan([cand('a', status: 'active')]), isEmpty);
    expect(plan([cand('b', hasCompletedAt: false)]), isEmpty);
  });

  test('a workout the watch linked is superseded when we saved it', () {
    for (final s in [HealthExportState.confirmed, HealthExportState.writing]) {
      final actions = plan(
        [cand('a')],
        receipts: [rec('a', s, id: 'hk1')],
        linked: {'a'},
      );
      final sup = actions.single as SupersedeByWatch;
      expect(sup.workoutUuid, 'a');
      expect(sup.platformRecordId, 'hk1');
    }
  });

  test('a workout the watch linked with no receipt plans nothing', () {
    expect(plan([cand('a')], linked: {'a'}), isEmpty);
  });

  test('a linked workout with an unfinished receipt is superseded too', () {
    for (final s in [
      HealthExportState.failedRetryable,
      HealthExportState.blocked,
    ]) {
      final actions = plan([cand('a')], receipts: [rec('a', s)], linked: {'a'});
      expect((actions.single as SupersedeByWatch).platformRecordId, isNull);
    }
    expect(
      plan(
        [cand('a')],
        receipts: [rec('a', HealthExportState.supersededByWatch)],
        linked: {'a'},
      ),
      isEmpty,
    );
  });

  test('deleted workout with a receipt deletes our copy', () {
    for (final s in [
      HealthExportState.confirmed,
      HealthExportState.writing,
      HealthExportState.deleting,
    ]) {
      final actions = plan(
        [cand('a', deleted: true)],
        receipts: [rec('a', s, id: 'hk1')],
      );
      final d = actions.single as DeleteOwnCopy;
      expect(d.workoutUuid, 'a');
      expect(d.platformRecordId, 'hk1');
    }
  });

  test('deleted workout with a blocked or failed receipt still deletes', () {
    for (final s in [
      HealthExportState.blocked,
      HealthExportState.failedRetryable,
    ]) {
      final actions = plan([cand('a', deleted: true)], receipts: [rec('a', s)]);
      expect(actions.single, isA<DeleteOwnCopy>());
    }
  });

  test('iOS deleted workout without receipt looks up an own copy', () {
    final actions = plan([cand('a', deleted: true)]);
    expect((actions.single as LookupDeletedCopy).candidate.uuid, 'a');
  });

  test('Android deleted workout without receipt plans nothing', () {
    expect(plan([cand('a', deleted: true)], isIos: false), isEmpty);
  });

  test('deleted workout with a failed or skipped receipt plans nothing', () {
    expect(
      plan(
        [cand('a', deleted: true)],
        receipts: [rec('a', HealthExportState.skippedWatch)],
      ),
      isEmpty,
    );
  });

  test('skippedWatch and supersededByWatch are final', () {
    expect(
      plan(
        [cand('a', version: 9), cand('b', version: 9)],
        receipts: [
          rec('a', HealthExportState.skippedWatch),
          rec('b', HealthExportState.supersededByWatch),
        ],
      ),
      isEmpty,
    );
  });

  test('confirmed at the current version plans nothing', () {
    expect(
      plan(
        [cand('a', version: 5)],
        receipts: [rec('a', HealthExportState.confirmed, exportedVersion: 5)],
      ),
      isEmpty,
    );
  });

  test('version bump on a confirmed workout rewrites', () {
    final actions = plan(
      [cand('a', version: 6)],
      receipts: [rec('a', HealthExportState.confirmed, exportedVersion: 5)],
    );
    expect(actions.single, isA<WriteWorkout>());
  });

  test(
    'failedRetryable with attempts 3 waits 4 minutes, attempts 10 waits 60',
    () {
      ExportReceiptView failed(int attempts, int minutesAgo) => rec(
        'a',
        HealthExportState.failedRetryable,
        attempts: attempts,
        lastAttemptAt: _now.subtract(Duration(minutes: minutesAgo)),
      );
      expect(plan([cand('a')], receipts: [failed(3, 3)]), isEmpty);
      expect(plan([cand('a')], receipts: [failed(3, 4)]), hasLength(1));
      expect(plan([cand('a')], receipts: [failed(10, 59)]), isEmpty);
      expect(plan([cand('a')], receipts: [failed(10, 60)]), hasLength(1));
    },
  );

  test('blocked receipts are planned for a write', () {
    final actions = plan(
      [cand('a')],
      receipts: [rec('a', HealthExportState.blocked)],
    );
    expect(actions.single, isA<WriteWorkout>());
  });

  test('waits 10 minutes on iOS with a paired watch', () {
    final fresh = cand(
      'a',
      completedAt: _now.subtract(const Duration(minutes: 9)),
    );
    expect(plan([fresh], watchPaired: true), isEmpty);
    expect(plan([fresh], watchPaired: true, isIos: false), hasLength(1));
    expect(plan([fresh]), hasLength(1));
    final old = cand(
      'b',
      completedAt: _now.subtract(const Duration(minutes: 10)),
    );
    expect(plan([old], watchPaired: true), hasLength(1));
  });

  test('a writing receipt resumes uncertain', () {
    final actions = plan(
      [cand('a')],
      receipts: [rec('a', HealthExportState.writing)],
    );
    expect((actions.single as WriteWorkout).resumeUncertain, isTrue);
  });

  test('orders writes oldest first and caps at 50', () {
    final workouts = [
      for (var i = 0; i < 60; i++)
        cand('w$i', completedAt: _now.subtract(Duration(days: i + 1))),
    ];
    final writes = plan(workouts).cast<WriteWorkout>();
    expect(writes, hasLength(50));
    expect(writes.first.candidate.uuid, 'w59');
    expect(writes.last.candidate.uuid, 'w10');
  });

  test('deletes and supersedes come before writes and are not capped', () {
    final workouts = [
      cand('new', completedAt: _now.subtract(const Duration(days: 1))),
      for (var i = 0; i < 3; i++) cand('d$i', deleted: true),
      cand('s', completedAt: _now.subtract(const Duration(days: 2))),
    ];
    final actions = plan(
      workouts,
      receipts: [
        for (var i = 0; i < 3; i++)
          rec('d$i', HealthExportState.confirmed, id: 'x$i'),
        rec('s', HealthExportState.confirmed, id: 'xs'),
      ],
      linked: {'s'},
      maxWrites: 1,
    );
    expect(actions, hasLength(5));
    expect(actions.take(4).every((a) => a is! WriteWorkout), isTrue);
    expect(actions.last, isA<WriteWorkout>());
  });
}
