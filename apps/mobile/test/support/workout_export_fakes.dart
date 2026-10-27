import 'dart:async';

import 'package:northstar_health/features/account/workout_history_export.dart';

import 'fake_account_auth.dart';

String workoutId(int index) =>
    '10000000-0000-4000-8000-${index.toRadixString(16).padLeft(12, '0')}';

Map<String, dynamic> exportRow(int index, {String owner = accountA}) {
  final id = workoutId(index);
  return {
    'user_id': owner,
    'workout_id': id,
    'server_revision': 1,
    'server_change_seq': index + 1,
    'status': 'completed',
    'deleted_at': null,
    'payload': {
      'schema_version': 1,
      'workout_id': id,
      'origin': 'northstar_phone',
      'status': 'completed',
      'name': 'Test workout',
      'started_at_utc': '2026-10-27T10:00:00Z',
      'completed_at_utc': '2026-10-27T10:35:00Z',
      'original_offset_minutes': 330,
      'exercises': [
        {
          'id': workoutId(index + 20000),
          'name': 'Row',
          'position': 0,
          'sets': [
            {
              'id': workoutId(index + 30000),
              'position': 0,
              'kind': 'working',
              'status': 'completed',
              'reps': 8,
              'load_grams': null,
              'input_unit': 'kg',
              'rpe': null,
              'completed_at_utc': '2026-10-27T10:30:00Z',
            },
          ],
        },
      ],
    },
  };
}

class FakeExportReader implements WorkoutExportReader {
  FakeExportReader(this.rows);
  final List<Map<String, dynamic>> rows;
  int highReads = 0;
  int pageReads = 0;
  int? finalHead;
  int? serverPageCap;
  Completer<void>? pausePage;
  int maxRequestedPageSize = 0;

  @override
  Future<int> highWatermark() async {
    highReads++;
    return highReads > 1 && finalHead != null
        ? finalHead!
        : rows.fold<int>(
            0,
            (a, b) => a > (b['server_change_seq'] as int)
                ? a
                : b['server_change_seq'] as int,
          );
  }

  @override
  Future<List<Map<String, dynamic>>> page({
    required int throughSeq,
    required String? afterId,
    required int limit,
  }) async {
    pageReads++;
    if (limit > maxRequestedPageSize) maxRequestedPageSize = limit;
    if (pausePage != null) await pausePage!.future;
    return rows
        .where(
          (r) =>
              (r['server_change_seq'] as int) <= throughSeq &&
              (afterId == null ||
                  (r['workout_id'] as String).compareTo(afterId) > 0),
        )
        .take(serverPageCap ?? limit)
        .toList();
  }
}

CompletedWorkoutHistoryExporter makeExporter(
  WorkoutExportReader reader, {
  bool Function()? authorized,
  int pageSize = 5,
  int maxExportBytes = 64 * 1024 * 1024,
}) => CompletedWorkoutHistoryExporter(
  accountId: accountA,
  reader: reader,
  authorized: authorized ?? () => true,
  pageSize: pageSize,
  maxExportBytes: maxExportBytes,
  now: () => DateTime.utc(2026, 10, 27, 10),
);
