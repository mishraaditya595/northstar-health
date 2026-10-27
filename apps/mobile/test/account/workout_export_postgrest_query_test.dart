import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:northstar_health/features/account/workout_history_export.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fake_account_auth.dart';
import '../support/workout_export_fakes.dart';

/// Exercises the real SupabaseWorkoutExportReader -> PostgREST query builder;
/// the HTTP handler records the exact URL sent over the wire. This is NOT a
/// hosted signed-JWT/RLS test, which is a separate P2-08 release gate.
void main() {
  test(
    'real reader queries owner, completion, tombstones, cap and keyset',
    () async {
      final requests = <Uri>[];
      final client = SupabaseClient(
        'https://northstar.invalid',
        'test-publishable-key',
        httpClient: MockClient((req) async {
          requests.add(req.url);
          return http.Response(
            jsonEncode([exportRow(1)]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);

      final reader = SupabaseWorkoutExportReader(client, accountA);
      final result = await reader.page(
        throughSeq: 1200,
        afterId: workoutId(0),
        limit: 100,
      );
      expect(result.single['user_id'], accountA);
      expect(requests, hasLength(1));
      final req = requests.single;
      expect(req.path, endsWith('/rest/v1/workout_records'));
      expect(req.queryParameters['user_id'], 'eq.$accountA');
      expect(req.queryParameters['status'], 'eq.completed');
      expect(req.queryParameters['deleted_at'], 'is.null');
      expect(req.queryParameters['server_change_seq'], 'lte.1200');
      expect(req.queryParameters['workout_id'], 'gt.${workoutId(0)}');
      expect(req.queryParameters['order'], 'workout_id.asc');
      expect(req.queryParameters['limit'], '100');
      expect(req.queryParameters['select'], contains('payload'));
      expect(req.queryParameters['select'], contains('server_revision'));
      expect(req.queryParameters['select'], contains('user_id'));
    },
  );

  test('real head query includes tombstones and is owner scoped', () async {
    final requests = <Uri>[];
    final client = SupabaseClient(
      'https://northstar.invalid',
      'test-publishable-key',
      httpClient: MockClient((req) async {
        requests.add(req.url);
        return http.Response(
          '[{"server_change_seq":142}]',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    expect(
      await SupabaseWorkoutExportReader(client, accountA).highWatermark(),
      142,
    );
    final req = requests.single;
    expect(req.queryParameters['user_id'], 'eq.$accountA');
    expect(req.queryParameters.containsKey('deleted_at'), false);
    expect(req.queryParameters.containsKey('status'), false);
    expect(req.queryParameters['order'], 'server_change_seq.desc');
    expect(req.queryParameters['limit'], '1');
    expect(req.queryParameters['select'], 'server_change_seq');
  });
}
