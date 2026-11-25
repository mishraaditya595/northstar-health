import 'dart:async';
import 'dart:io';

import 'package:beyondrep/features/catalog/data/catalog_transport.dart';
import 'package:beyondrep/features/catalog/domain/catalog_models.dart';
import 'package:beyondrep/features/sync/workout_restore_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _account = '11111111-1111-4111-8111-111111111111';
const _nowSeconds = 1000000;

class FakeRpc {
  final calls = <String>[];
  final params = <Map<String, dynamic>>[];
  Future<Object?> Function(String, Map<String, dynamic>)? handler;

  Future<Object?> call(String name, Map<String, dynamic> args) {
    calls.add(name);
    params.add(args);
    return handler!(name, args);
  }
}

SupabaseCatalogTransport transport(
  FakeRpc rpc, {
  String? userId = _account,
  bool anonymous = false,
  int? expiresAt = _nowSeconds + 3600,
  String accountId = _account,
}) => SupabaseCatalogTransport(
  accountId: accountId,
  readSession: () => RestoreSessionSnapshot(
    userId: userId,
    anonymous: anonymous,
    expiresAtSeconds: expiresAt,
  ),
  invokeRpc: rpc.call,
  clockSeconds: () => _nowSeconds,
);

Map<String, Object?> manifestJson() => {
  'release': 2,
  'schemaVersion': 1,
  'minAppCatalogSchema': 1,
  'publishedAt': '2026-11-26T00:00:00Z',
  'sha256': 'ab' * 32,
  'sizeBytes': 10,
  'url': 'https://example.invalid/x',
};

void main() {
  group('session guard', () {
    test('anonymous session never calls the RPC', () async {
      final rpc = FakeRpc();
      final t = transport(rpc, anonymous: true);
      await expectLater(t.fetchManifest(), throwsA(isA<CatalogUnauthorized>()));
      await expectLater(
        t.fetchSnapshot(1),
        throwsA(isA<CatalogUnauthorized>()),
      );
      expect(rpc.calls, isEmpty);
    });

    test('expired session never calls the RPC', () async {
      final rpc = FakeRpc();
      final t = transport(rpc, expiresAt: _nowSeconds);
      await expectLater(t.fetchManifest(), throwsA(isA<CatalogUnauthorized>()));
      expect(rpc.calls, isEmpty);
    });

    test('signed out never calls the RPC', () async {
      final rpc = FakeRpc();
      final t = transport(rpc, userId: null, expiresAt: null);
      await expectLater(
        t.fetchSnapshot(1),
        throwsA(isA<CatalogUnauthorized>()),
      );
      expect(rpc.calls, isEmpty);
    });

    test('other account never calls the RPC', () async {
      final rpc = FakeRpc();
      final t = transport(rpc, userId: '22222222-2222-4222-8222-222222222222');
      await expectLater(t.fetchManifest(), throwsA(isA<CatalogUnauthorized>()));
      expect(rpc.calls, isEmpty);
    });
  });

  group('calls', () {
    test('manifest null maps to null', () async {
      final rpc = FakeRpc()..handler = (_, _) async => null;
      expect(await transport(rpc).fetchManifest(), isNull);
      expect(rpc.calls, ['catalog_manifest']);
      expect(rpc.params.single, isEmpty);
    });

    test('manifest parsed', () async {
      final rpc = FakeRpc()..handler = (_, _) async => manifestJson();
      final manifest = await transport(rpc).fetchManifest();
      expect(manifest?.release, 2);
      expect(manifest?.sha256, 'ab' * 32);
    });

    test('invalid manifest surfaces a format exception', () async {
      final rpc = FakeRpc()..handler = (_, _) async => {'release': 2};
      await expectLater(
        transport(rpc).fetchManifest(),
        throwsA(isA<CatalogFormatException>()),
      );
    });

    test('snapshot passes p_release', () async {
      final rpc = FakeRpc()..handler = (_, _) async => {'release': 7};
      final json = await transport(rpc).fetchSnapshot(7);
      expect(json, {'release': 7});
      expect(rpc.calls, ['catalog_snapshot']);
      expect(rpc.params.single, {'p_release': 7});
    });
  });

  group('failures', () {
    test('P0002 maps to CatalogNotLive', () async {
      final rpc = FakeRpc()
        ..handler = (_, _) async => throw const PostgrestException(
          message: 'secret body',
          code: 'P0002',
        );
      await expectLater(
        transport(rpc).fetchSnapshot(3),
        throwsA(isA<CatalogNotLive>()),
      );
    });

    test('other postgrest error maps to server', () async {
      final rpc = FakeRpc()
        ..handler = (_, _) async => throw const PostgrestException(
          message: 'secret body',
          code: '42501',
        );
      await expectLater(
        transport(rpc).fetchManifest(),
        throwsA(
          isA<CatalogNetworkFailure>()
              .having((e) => e.kind, 'kind', 'server')
              .having(
                (e) => e.toString(),
                'toString',
                isNot(contains('secret')),
              ),
        ),
      );
    });

    test('socket error maps to network', () async {
      final rpc = FakeRpc()
        ..handler = (_, _) async => throw const SocketException('offline');
      await expectLater(
        transport(rpc).fetchManifest(),
        throwsA(
          isA<CatalogNetworkFailure>().having((e) => e.kind, 'kind', 'network'),
        ),
      );
    });

    testWidgets('manifest timeout maps to timeout after 10 s', (tester) async {
      final rpc = FakeRpc()..handler = (_, _) => Completer<Object?>().future;
      final result = transport(rpc)
          .fetchManifest()
          .then<Object?>((_) => null, onError: (Object e) => e);
      await tester.pump(const Duration(seconds: 9));
      var done = false;
      unawaited(result.then((_) => done = true));
      await tester.pump();
      expect(done, isFalse);
      await tester.pump(const Duration(seconds: 2));
      final error = await result;
      expect(error, isA<CatalogNetworkFailure>());
      expect((error! as CatalogNetworkFailure).kind, 'timeout');
    });

    testWidgets('snapshot timeout maps to timeout after 20 s', (tester) async {
      final rpc = FakeRpc()..handler = (_, _) => Completer<Object?>().future;
      final result = transport(rpc)
          .fetchSnapshot(1)
          .then<Object?>((_) => null, onError: (Object e) => e);
      await tester.pump(const Duration(seconds: 15));
      var done = false;
      unawaited(result.then((_) => done = true));
      await tester.pump();
      expect(done, isFalse);
      await tester.pump(const Duration(seconds: 6));
      final error = await result;
      expect((error! as CatalogNetworkFailure).kind, 'timeout');
    });

    test('session lost while the call is pending releases nothing', () async {
      var signedIn = true;
      final rpc = FakeRpc()
        ..handler = (_, _) async {
          signedIn = false;
          return manifestJson();
        };
      final t = SupabaseCatalogTransport(
        accountId: _account,
        readSession: () => RestoreSessionSnapshot(
          userId: signedIn ? _account : null,
          anonymous: false,
          expiresAtSeconds: signedIn ? _nowSeconds + 3600 : null,
        ),
        invokeRpc: rpc.call,
        clockSeconds: () => _nowSeconds,
      );
      await expectLater(t.fetchManifest(), throwsA(isA<CatalogUnauthorized>()));
    });
  });
}
