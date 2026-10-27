import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/features/account/workout_history_export.dart';

import '../support/fake_account_auth.dart';
import '../support/workout_export_fakes.dart';

void main() {
  test(
    'empty account is valid but does not imply local data were exported',
    () async {
      final reader = FakeExportReader([]);
      final json = jsonDecode(
        await makeExporter(reader).exportJson(),
      ) as Map<String, dynamic>;
      expect(json['workout_count'], 0);
      expect(json['workouts'], isEmpty);
      expect(json['cloud_change_seq'], 0);
      expect(json['source'], 'northstar_completed_phone_workouts_cloud');
      expect(json['excludes'], contains('custom_plans'));
      expect(reader.highReads, 2);
    },
  );

  test(
    'keyset pages export thousands without dropping records or null fields',
    () async {
      final reader = FakeExportReader(
        List.generate(1201, (index) => exportRow(index)),
      );
      final data = jsonDecode(
        await makeExporter(reader, pageSize: 100).exportJson(),
      ) as Map<String, dynamic>;
      final rows = data['workouts'] as List<dynamic>;
      expect(rows.length, 1201);
      expect(data['workout_count'], 1201);
      expect((rows.first as Map)['workout_id'], workoutId(0));
      expect((rows.last as Map)['workout_id'], workoutId(1200));
      expect(
        ((((rows.first as Map)['payload'] as Map)['exercises'] as List).first
            as Map)['sets'],
        isNotEmpty,
      );
      final set =
          (((rows.first as Map)['payload'] as Map)['exercises'] as List)
                  .first['sets'][0]
              as Map;
      expect(set.containsKey('load_grams'), true);
      expect(set['load_grams'], isNull);
      expect(set['rpe'], isNull);
      expect(reader.maxRequestedPageSize, 100);
      expect(reader.pageReads, 14);
    },
  );

  test('short server pages still export every workout until empty page', () async {
    final reader = FakeExportReader(
      List.generate(43, (index) => exportRow(index)),
    )..serverPageCap = 7;
    final data = jsonDecode(
      await makeExporter(reader, pageSize: 100).exportJson(),
    ) as Map<String, dynamic>;
    final workouts = data['workouts'] as List<dynamic>;
    expect(workouts.length, 43);
    expect(workouts.last['workout_id'], workoutId(42));
    expect(reader.pageReads, 8); // seven non-empty pages plus empty page
    expect(reader.highReads, 2);
  });

  test('invalid workout UUID is a typed export error', () async {
    final row = exportRow(0)..['workout_id'] = 'not-a-uuid';
    await expectLater(
      makeExporter(FakeExportReader([row])).exportJson(),
      throwsA(
        isA<WorkoutExportException>().having(
          (e) => e.code, 'code', 'invalid_order',
        ),
      ),
    );
  });

  test('request page size above 100 is rejected', () {
    expect(
      () => makeExporter(FakeExportReader([]), pageSize: 101),
      throwsArgumentError,
    );
  });

  test(
    'concurrent owner write aborts instead of releasing inconsistent JSON',
    () async {
      final reader = FakeExportReader([exportRow(0)])..finalHead = 100;
      await expectLater(
        makeExporter(reader).exportJson(),
        throwsA(
          isA<WorkoutExportException>().having(
            (e) => e.code,
            'code',
            'history_changed_retry',
          ),
        ),
      );
    },
  );

  test('sign-out while page is in flight discards all data', () async {
    final hold = Completer<void>();
    final reader = FakeExportReader([exportRow(0)])..pausePage = hold;
    var ownerAuthorized = true;
    final work = makeExporter(
      reader,
      authorized: () => ownerAuthorized,
    ).exportJson();
    await Future<void>.delayed(Duration.zero);
    ownerAuthorized = false;
    hold.complete();
    await expectLater(
      work,
      throwsA(
        isA<WorkoutExportException>().having(
          (e) => e.code,
          'code',
          'session_changed',
        ),
      ),
    );
  });

  test('unauthorized session never makes a network call', () async {
    final reader = FakeExportReader([exportRow(0)]);
    await expectLater(
      makeExporter(reader, authorized: () => false).exportJson(),
      throwsA(isA<WorkoutExportException>()),
    );
    expect(reader.highReads, 0);
    expect(reader.pageReads, 0);
  });

  test('wrong-owner row fails closed even if service returned it', () async {
    final reader = FakeExportReader([exportRow(0, owner: accountB)]);
    await expectLater(
      makeExporter(reader).exportJson(),
      throwsA(isA<WorkoutExportException>()),
    );
  });

  test('deletion tombstone and corrupt payload are never exported', () async {
    final deleted = exportRow(0)..['deleted_at'] = '2026-10-27T10:00:00Z';
    await expectLater(
      makeExporter(FakeExportReader([deleted])).exportJson(),
      throwsA(isA<WorkoutExportException>()),
    );
    final corrupt = exportRow(0);
    (corrupt['payload'] as Map<String, dynamic>)['origin'] = 'health_connect';
    await expectLater(
      makeExporter(FakeExportReader([corrupt])).exportJson(),
      throwsA(isA<WorkoutExportException>()),
    );
  });

  test('out-of-order and duplicated keys fail closed', () async {
    final reader = FakeExportReader([exportRow(2), exportRow(1)]);
    await expectLater(
      makeExporter(reader, pageSize: 5).exportJson(),
      throwsA(
        isA<WorkoutExportException>().having(
          (e) => e.code,
          'code',
          'invalid_order',
        ),
      ),
    );
    final dup = FakeExportReader([exportRow(0), exportRow(0)]);
    await expectLater(
      makeExporter(dup).exportJson(),
      throwsA(isA<WorkoutExportException>()),
    );
  });

  test(
    'excessive export fails instead of returning a truncated document',
    () async {
      final reader = FakeExportReader([exportRow(0), exportRow(1)]);
      await expectLater(
        makeExporter(reader, maxExportBytes: 1024).exportJson(),
        throwsA(
          isA<WorkoutExportException>().having(
            (e) => e.code,
            'code',
            'export_too_large',
          ),
        ),
      );
    },
  );

  test('network error propagates; no file delivery can occur', () async {
    final reader = _FailingReader();
    await expectLater(
      makeExporter(reader).exportJson(),
      throwsA(isA<StateError>()),
    );
  });
}

class _FailingReader implements WorkoutExportReader {
  @override
  Future<int> highWatermark() async => 1;
  @override
  Future<List<Map<String, dynamic>>> page({
    required int throughSeq,
    required String? afterId,
    required int limit,
  }) async => throw StateError('Offline');
}
