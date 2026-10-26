import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/features/sync/workout_restore_feed.dart';
import 'package:northstar_health/features/sync/workout_restore_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const ownerA = '10000000-0000-4000-8000-0000000000a1';
const ownerB = '10000000-0000-4000-8000-0000000000b2';
const epochA = '20000000-0000-4000-8000-0000000000a1';

Map<String, dynamic> emptyPage({int next = 0, bool reset = false}) => {
  'schema_version': 1,
  'cursor_epoch': epochA,
  'cursor_reset': reset,
  'next_cursor': next,
  'has_more': false,
  'changes': <Object>[],
};

void main() {
  late RestoreSessionSnapshot session;
  late int now;
  late int rpcCalls;
  late String? rpcName;
  late Map<String, dynamic>? rpcParams;
  late Future<Object?> Function(String, Map<String, dynamic>) handler;

  SupabaseWorkoutRestoreTransport transport() =>
      SupabaseWorkoutRestoreTransport(
        accountId: ownerA,
        readSession: () => session,
        invokeRpc: (name, params) {
          rpcCalls++;
          rpcName = name;
          rpcParams = params;
          return handler(name, params);
        },
        clockSeconds: () => now,
      );

  setUp(() {
    session = const RestoreSessionSnapshot(
      userId: ownerA,
      anonymous: false,
      expiresAtSeconds: 200,
    );
    now = 100;
    rpcCalls = 0;
    rpcName = null;
    rpcParams = null;
    handler = (_, _) async => emptyPage();
  });

  test('passes exact RPC function and params, decodes first page', () async {
    final response = await transport().fetchPage(
      afterSeq: 0,
      cursorEpoch: null,
    );
    expect(rpcCalls, 1);
    expect(rpcName, 'get_workout_changes');
    expect(rpcParams, {
      'p_after_seq': 0,
      'p_limit': 100,
      'p_cursor_epoch': null,
    });
    expect(response.nextCursor, 0);
    expect(response.cursorEpoch, epochA);

    handler = (_, _) async => emptyPage(next: 8);
    final after = await transport().fetchPage(
      afterSeq: 8,
      cursorEpoch: epochA,
      limit: 200,
    );
    expect(after.nextCursor, 8);
    expect(rpcParams, {
      'p_after_seq': 8,
      'p_limit': 200,
      'p_cursor_epoch': epochA,
    });
  });

  test(
    'rejects cursor, epoch and limit arguments before calling RPC',
    () async {
      final service = transport();
      for (final invalid in [-1]) {
        await expectLater(
          service.fetchPage(afterSeq: invalid, cursorEpoch: epochA),
          throwsFormatException,
        );
      }
      for (final invalid in [0, -1, 201]) {
        await expectLater(
          service.fetchPage(afterSeq: 0, cursorEpoch: null, limit: invalid),
          throwsFormatException,
        );
      }
      await expectLater(
        service.fetchPage(afterSeq: 1, cursorEpoch: null),
        throwsFormatException,
      );
      await expectLater(
        service.fetchPage(afterSeq: 0, cursorEpoch: 'invalid'),
        throwsFormatException,
      );
      expect(rpcCalls, 0);
      const maxCursor = 9223372036854775807;
      handler = (_, _) async => emptyPage(next: maxCursor);
      final highest = await service.fetchPage(
        afterSeq: maxCursor,
        cursorEpoch: epochA,
        limit: 200,
      );
      expect(highest.nextCursor, maxCursor);
      expect(rpcParams!['p_after_seq'], maxCursor);
    },
  );

  test(
    'blocks other account, anonymous, missing and expired sessions',
    () async {
      final service = transport();
      for (final blocked in [
        const RestoreSessionSnapshot(
          userId: ownerB,
          anonymous: false,
          expiresAtSeconds: 200,
        ),
        const RestoreSessionSnapshot(
          userId: ownerA,
          anonymous: true,
          expiresAtSeconds: 200,
        ),
        const RestoreSessionSnapshot(
          userId: null,
          anonymous: false,
          expiresAtSeconds: 200,
        ),
        const RestoreSessionSnapshot(
          userId: ownerA,
          anonymous: false,
          expiresAtSeconds: 100,
        ),
      ]) {
        session = blocked;
        await expectLater(
          service.fetchPage(afterSeq: 0, cursorEpoch: null),
          throwsA(isA<AuthException>()),
        );
      }
      expect(rpcCalls, 0);
    },
  );

  test('account switch while HTTP is in flight discards response', () async {
    final pendingRpc = Completer<Object?>();
    handler = (_, _) => pendingRpc.future;
    final service = transport();
    final request = service.fetchPage(afterSeq: 0, cursorEpoch: null);
    expect(rpcCalls, 1);
    session = const RestoreSessionSnapshot(
      userId: ownerB,
      anonymous: false,
      expiresAtSeconds: 200,
    );
    pendingRpc.complete(emptyPage());
    await expectLater(request, throwsA(isA<AuthException>()));
    expect(rpcCalls, 1);
  });

  test('token expiration during RPC fails retryably after request', () async {
    final pendingRpc = Completer<Object?>();
    handler = (_, _) => pendingRpc.future;
    session = const RestoreSessionSnapshot(
      userId: ownerA,
      anonymous: false,
      expiresAtSeconds: 110,
    );
    final request = transport().fetchPage(afterSeq: 0, cursorEpoch: null);
    expect(rpcCalls, 1);
    now = 110;
    pendingRpc.complete(emptyPage());
    await expectLater(request, throwsA(isA<AuthException>()));
  });

  test(
    'rejects invalid RPC page after network without mutating any cursor',
    () async {
      handler = (_, _) async => {...emptyPage(), 'schema_version': 2};
      await expectLater(
        transport().fetchPage(afterSeq: 0, cursorEpoch: null),
        throwsFormatException,
      );
      expect(rpcCalls, 1);
    },
  );
  test(
    'fromClient production wiring fails closed without a signed-in session',
    () async {
      final client = SupabaseClient(
        'https://localhost.supabase.co',
        'sb_publishable_test',
      );
      final wired = SupabaseWorkoutRestoreTransport.fromClient(client, ownerA);
      // No authenticated session: this must not attempt a real network RPC.
      await expectLater(
        wired.fetchPage(afterSeq: 0, cursorEpoch: null),
        throwsA(isA<AuthException>()),
      );
    },
  );

  test(
    'request argument failures have request-specific safe diagnostics',
    () async {
      final service = transport();
      await expectLater(
        service.fetchPage(afterSeq: -1, cursorEpoch: null),
        throwsA(
          isA<RestoreContractException>()
              .having((error) => error.code, 'code', 'invalid_request')
              .having((error) => error.request, 'request', true)
              .having(
                (error) => error.message,
                'message',
                'Invalid workout restore request',
              ),
        ),
      );
      await expectLater(
        service.fetchPage(afterSeq: 1, cursorEpoch: null),
        throwsA(
          isA<RestoreContractException>().having(
            (error) => error.code,
            'code',
            'invalid_request',
          ),
        ),
      );
      await expectLater(
        service.fetchPage(afterSeq: 0, cursorEpoch: 'not-a-uuid'),
        throwsA(
          isA<RestoreContractException>().having(
            (error) => error.code,
            'code',
            'invalid_request',
          ),
        ),
      );
      expect(rpcCalls, 0);
    },
  );
}
