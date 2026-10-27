import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/storage/account_store.dart';
import '../sync/cloud_session_guard.dart';
import 'account_auth_provider.dart';

/// Never send an unverified file to the OS share/save bridge.
class WorkoutExportException implements Exception {
  const WorkoutExportException(this.code);
  final String code;
  @override
  String toString() => 'Workout export unavailable: $code';
}

abstract class WorkoutExportReader {
  /// The highest change sequence among this owner's live rows AND tombstones.
  Future<int> highWatermark();
  Future<List<Map<String, dynamic>>> page({
    required int throughSeq,
    required String? afterId,
    required int limit,
  });
}

/// RLS-protected public.workout_records SELECT. No SECURITY DEFINER or
/// client-supplied owner argument. PostgreSQL policy remains authoritative.
class SupabaseWorkoutExportReader implements WorkoutExportReader {
  SupabaseWorkoutExportReader(this.client, this.ownerId);
  final SupabaseClient client;
  final String ownerId;

  @override
  Future<int> highWatermark() async {
    final rows = await client
        .from('workout_records')
        .select('server_change_seq')
        .eq('user_id', ownerId)
        .order('server_change_seq', ascending: false)
        .limit(1);
    if (rows.isEmpty) return 0;
    if (rows.length != 1 ||
        rows.first['server_change_seq'] is! int ||
        (rows.first['server_change_seq'] as int) <= 0) {
      throw const WorkoutExportException('invalid_head');
    }
    return rows.first['server_change_seq'] as int;
  }

  @override
  Future<List<Map<String, dynamic>>> page({
    required int throughSeq,
    required String? afterId,
    required int limit,
  }) async {
    // Never OFFSET paginate: concurrent inserts may shift later pages.
    // UUID keyset + fixed high watermark gives deterministic page boundaries.
    final base = client
        .from('workout_records')
        .select(
          'user_id,workout_id,server_revision,server_change_seq,'
          'status,deleted_at,payload',
        )
        .eq('user_id', ownerId)
        .eq('status', 'completed')
        .isFilter('deleted_at', null)
        .lte('server_change_seq', throughSeq);
    final filtered = afterId == null ? base : base.gt('workout_id', afterId);
    final data = await filtered.order('workout_id', ascending: true).limit(limit);
    return data.map((row) => Map<String, dynamic>.from(row)).toList();
  }
}

/// A fail-closed, explicit export of *cloud* completed phone workouts only.
///
/// Snapshot guarantee: if any owner workout changes during pagination,
/// the final owner high-watermark differs and no bytes may be handed to the
/// native file picker. PostgreSQL owner change_seq is commit-serialized; all
/// deletion tombstones remain in workout_records. A database point-in-time
/// restore requires the existing epoch-rotation runbook and P2-08 testing.
///
/// This materializes only a bounded JSON document, never an OS file. A
/// separate user-triggered native picker must receive it after authorization.
class CompletedWorkoutHistoryExporter {
  CompletedWorkoutHistoryExporter({
    required String accountId,
    required this.reader,
    required this.authorized,
    DateTime Function()? now,
    this.pageSize = 100,
    // Conservative temporary cap until low-memory device profiling is done.
    this.maxExportBytes = 4 * 1024 * 1024,
  }) : accountId = validAccountId(accountId),
       _now = now ?? DateTime.now {
    if (pageSize < 1 || pageSize > 100 || maxExportBytes < 1024) {
      throw ArgumentError('Invalid export bounds');
    }
  }

  final String accountId;
  final WorkoutExportReader reader;
  final bool Function() authorized;
  final DateTime Function() _now;
  final int pageSize;
  final int maxExportBytes;

  void _checkOwner() {
    if (!authorized()) throw const WorkoutExportException('session_changed');
  }

  bool _validWorkoutId(String id) {
    try {
      return validAccountId(id) == id;
    } on FormatException {
      return false;
    }
  }

  Future<String> exportJson() async {
    _checkOwner();
    final high = await reader.highWatermark();
    _checkOwner();
    if (high < 0) throw const WorkoutExportException('invalid_head');

    final json = StringBuffer();
    var encodedBytes = 0;
    void add(String text) {
      // Encode the exact UTF-8 output size, not the Dart UTF-16 length.
      encodedBytes += utf8.encode(text).length;
      if (encodedBytes > maxExportBytes) {
        throw const WorkoutExportException('export_too_large');
      }
      json.write(text);
    }

    add(
      '{"export_schema_version":1,'
      '"source":"northstar_completed_phone_workouts_cloud",'
      '"owner_id":${jsonEncode(accountId)},'
      '"exported_at_utc":${jsonEncode(_now().toUtc().toIso8601String())},'
      '"cloud_change_seq":$high,'
      '"excludes":["deleted_workouts","unfinished_sessions",'
      '"custom_plans","device_preferences","pending_local_uploads",'
      '"health_measurements"],'
      '"workouts":[',
    );

    String? lastId;
    var count = 0;
    while (true) {
      _checkOwner();
      final page = await reader.page(
        throughSeq: high,
        afterId: lastId,
        limit: pageSize,
      );
      _checkOwner();
      if (page.length > pageSize) {
        throw const WorkoutExportException('page_too_large');
      }
      for (final row in page) {
        if (row['user_id'] != accountId ||
            row['deleted_at'] != null ||
            row['status'] != 'completed' ||
            row['server_change_seq'] is! int ||
            row['server_revision'] is! int) {
          throw const WorkoutExportException('invalid_row');
        }
        final seq = row['server_change_seq'] as int;
        final revision = row['server_revision'] as int;
        if (seq < 1 || seq > high || revision < 1) {
          throw const WorkoutExportException('invalid_revision');
        }
        final id = row['workout_id'];
        if (id is! String ||
            !_validWorkoutId(id) ||
            (lastId != null && id.compareTo(lastId) <= 0)) {
          throw const WorkoutExportException('invalid_order');
        }
        final payload = row['payload'];
        if (payload is! Map<String, dynamic> ||
            payload['schema_version'] != 1 ||
            payload['status'] != 'completed' ||
            payload['origin'] != 'northstar_phone' ||
            payload['workout_id'] != id ||
            payload['exercises'] is! List) {
          throw const WorkoutExportException('invalid_payload');
        }
        if (count != 0) add(',');
        add(
          jsonEncode({
            'workout_id': id,
            'server_revision': revision,
            'server_change_seq': seq,
            'payload': payload,
          }),
        );
        count++;
        lastId = id;
      }
      // A PostgREST server may cap each result below the requested page
      // size; only an *empty* keyset page proves exhaustion.
      if (page.isEmpty) break;
    }
    add('],"workout_count":$count}');
    _checkOwner();
    final endHigh = await reader.highWatermark();
    _checkOwner();
    if (high != endHigh) {
      throw const WorkoutExportException('history_changed_retry');
    }
    return json.toString();
  }
}

final workoutHistoryExporterProvider =
    Provider<CompletedWorkoutHistoryExporter Function(String)>((ref) {
      final auth = ref.watch(accountAuthControllerProvider);
      return (owner) {
        if (auth == null || auth.userId != owner) {
          throw const WorkoutExportException('session_changed');
        }
        final client = Supabase.instance.client;
        return CompletedWorkoutHistoryExporter(
          accountId: owner,
          reader: SupabaseWorkoutExportReader(client, owner),
          authorized: () {
            final session = client.auth.currentSession;
            return auth.userId == owner &&
                auth.cloudBackupReady &&
                matchesCloudWorkoutSession(
                  sessionUserId: session?.user.id,
                  anonymous: session?.user.isAnonymous ?? true,
                  expiresAtSeconds: session?.expiresAt,
                  accountId: owner,
                  nowSeconds:
                      DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
                );
          },
        );
      };
    });
