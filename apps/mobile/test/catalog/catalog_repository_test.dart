import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beyondrep/features/catalog/data/catalog_file_store.dart';
import 'package:beyondrep/features/catalog/data/catalog_repository.dart';
import 'package:beyondrep/features/catalog/data/catalog_transport.dart';
import 'package:beyondrep/features/catalog/domain/canonical_json.dart';
import 'package:beyondrep/features/catalog/domain/catalog_models.dart';
import 'package:beyondrep/features/catalog/domain/catalog_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_fixtures.dart';

class _FailingWriteStore extends CatalogFileStore {
  _FailingWriteStore(super.directory);

  @override
  Future<void> writeSnapshotText(String text) async {
    throw const FileSystemException('disk full');
  }
}

class _FailingMetaStore extends CatalogFileStore {
  _FailingMetaStore(super.directory);

  @override
  Future<void> writeLastCheckedAtMs(
    int value, {
    CatalogOutdatedMark? outdated,
  }) async {
    throw const FileSystemException('meta write failed');
  }
}

/// Throws something that is not an Exception.
class _ThrowingStore extends CatalogFileStore {
  _ThrowingStore(super.directory);

  @override
  Future<void> prepare() async => throw TypeError();

  @override
  Future<int?> readLastCheckedAtMs() async => throw TypeError();
}

Future<CatalogSnapshot?> _parse(String text) async {
  try {
    return parseCatalogSnapshot(jsonDecode(text));
  } on Object {
    return null;
  }
}

String _canonical(Map<String, Object?> json) =>
    utf8.decode(canonicalJsonBytes(json));

void main() {
  late Directory root;
  late Directory dir;
  late DateTime now;
  late CatalogFileStore store;

  final r1 = snapshotJson();
  final r2 = snapshotJson(
    release: 2,
    ids: ['builtin.v1.squat', 'builtin.v1.plank', 'builtin.v1.row'],
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('catalog_repo_test');
    dir = Directory('${root.path}/cache');
    store = CatalogFileStore(dir);
    now = DateTime.utc(2026, 11, 26, 12);
  });

  tearDown(() => root.deleteSync(recursive: true));

  File snapshotFile() => File('${dir.path}/snapshot.json');

  CatalogRepository repo(
    FakeCatalogTransport transport, {
    CatalogFileStore? withStore,
  }) => CatalogRepository(
    transport: transport,
    store: withStore ?? store,
    clock: () => now,
    parseInBackground: _parse,
  );

  FakeCatalogTransport serving(Map<String, Object?> live) =>
      FakeCatalogTransport(
        manifest: () async => manifestFor(live),
        snapshot: (_) async => live,
      );

  Future<void> seed(Map<String, Object?> json, {int? checkedAtMs}) async {
    await store.prepare();
    await store.writeSnapshotText(_canonical(json));
    if (checkedAtMs != null) await store.writeLastCheckedAtMs(checkedAtMs);
  }

  group('load', () {
    test('no file means unavailable', () async {
      final r = repo(serving(r1));
      expect(r.state.status, CatalogStatus.loading);
      await r.load();
      expect(r.state.status, CatalogStatus.unavailable);
      expect(r.state.snapshot, isNull);
    });

    test('valid cached file is ready', () async {
      await seed(r1);
      final r = repo(serving(r1));
      await r.load();
      expect(r.state.status, CatalogStatus.ready);
      expect(r.state.snapshot?.release, 1);
    });

    test('load runs once', () async {
      await seed(r1);
      final r = repo(serving(r1));
      expect(identical(r.load(), r.load()), isTrue);
      await r.load();
    });

    test('corrupt cached file is deleted on load', () async {
      await seed(r1);
      snapshotFile().writeAsStringSync('{"release":');
      final r = repo(serving(r1));
      await r.load();
      expect(r.state.status, CatalogStatus.unavailable);
      expect(r.state.snapshot, isNull);
      expect(snapshotFile().existsSync(), isFalse);
    });

    test('truncated valid snapshot is deleted on load', () async {
      final text = _canonical(r1);
      await seed(r1);
      snapshotFile().writeAsStringSync(text.substring(0, text.length ~/ 2));
      final r = repo(serving(r1));
      await r.load();
      expect(r.state.status, CatalogStatus.unavailable);
      expect(snapshotFile().existsSync(), isFalse);
    });

    test('structurally invalid cached file is deleted on load', () async {
      await seed(r1);
      snapshotFile().writeAsStringSync('{"release":1}');
      final r = repo(serving(r1));
      await r.load();
      expect(r.state.status, CatalogStatus.unavailable);
      expect(snapshotFile().existsSync(), isFalse);
    });

    test('stale temp file is removed on load', () async {
      await seed(r1);
      File('${dir.path}/snapshot.json.old.tmp')
        ..writeAsStringSync('partial')
        ..setLastModifiedSync(
          DateTime.now().subtract(const Duration(minutes: 11)),
        );
      final r = repo(serving(r1));
      await r.load();
      expect(File('${dir.path}/snapshot.json.old.tmp').existsSync(), isFalse);
      expect(r.state.status, CatalogStatus.ready);
    });

    test('the default parser works off the main isolate', () async {
      await seed(r1);
      final r = CatalogRepository(
        transport: serving(r1),
        store: store,
        clock: () => now,
      );
      await r.load();
      expect(r.state.status, CatalogStatus.ready);
      expect(r.state.snapshot?.exercises, hasLength(2));
      snapshotFile().writeAsStringSync('garbage');
      final again = CatalogRepository(
        transport: serving(r1),
        store: store,
        clock: () => now,
      );
      await again.load();
      expect(again.state.status, CatalogStatus.unavailable);
    });
  });

  group('refresh', () {
    test('first launch downloads and activates', () async {
      final t = serving(r1);
      final r = repo(t);
      var notified = 0;
      r.addListener(() => notified++);

      expect(await r.refresh(), CatalogRefreshOutcome.updated);

      expect(r.state.status, CatalogStatus.ready);
      expect(r.state.snapshot?.release, 1);
      expect(snapshotFile().readAsStringSync(), _canonical(r1));
      expect(await store.readLastCheckedAtMs(), now.millisecondsSinceEpoch);
      expect(t.snapshotRequests, [1]);
      expect(notified, greaterThan(0));
    });

    test('fresh check is skipped within 24 hours', () async {
      final t = serving(r1);
      final r = repo(t);
      await r.refresh();
      now = now.add(const Duration(hours: 23, minutes: 59));
      expect(await r.refresh(), CatalogRefreshOutcome.skippedFresh);
      expect(t.manifestCalls, 1);
    });

    test('check runs again after 24 hours', () async {
      final t = serving(r1);
      final r = repo(t);
      await r.refresh();
      now = now.add(const Duration(hours: 24));
      expect(await r.refresh(), CatalogRefreshOutcome.upToDate);
      expect(t.manifestCalls, 2);
    });

    test('force ignores the window', () async {
      final t = serving(r1);
      final r = repo(t);
      await r.refresh();
      expect(await r.refresh(force: true), CatalogRefreshOutcome.upToDate);
      expect(t.manifestCalls, 2);
    });

    test('clock moved backwards forces a check', () async {
      await seed(r1, checkedAtMs: now.millisecondsSinceEpoch + 3600 * 1000);
      final t = serving(r1);
      final r = repo(t);
      expect(await r.refresh(), CatalogRefreshOutcome.upToDate);
      expect(t.manifestCalls, 1);
      expect(await store.readLastCheckedAtMs(), now.millisecondsSinceEpoch);
    });

    test('same release is a no-op refresh', () async {
      final t = serving(r1);
      final r = repo(t);
      await r.refresh();
      final bytes = snapshotFile().readAsBytesSync();
      now = now.add(const Duration(hours: 25));

      expect(await r.refresh(), CatalogRefreshOutcome.upToDate);

      expect(t.snapshotRequests, [1]);
      expect(snapshotFile().readAsBytesSync(), bytes);
      expect(await store.readLastCheckedAtMs(), now.millisecondsSinceEpoch);
    });

    test('new release replaces the file and state', () async {
      await seed(r1);
      var live = r1;
      final t = FakeCatalogTransport(
        manifest: () async => manifestFor(live),
        snapshot: (_) async => live,
      );
      final r = repo(t);
      await r.load();
      live = r2;

      expect(await r.refresh(), CatalogRefreshOutcome.updated);

      expect(r.state.snapshot?.release, 2);
      expect(r.state.snapshot?.exercises, hasLength(3));
      expect(snapshotFile().readAsStringSync(), _canonical(r2));
      expect(dir.listSync().where((e) => e.path.endsWith('.tmp')), isEmpty);
    });

    test('checksum mismatch keeps the old cache', () async {
      await seed(r1, checkedAtMs: 5);
      final bytes = snapshotFile().readAsBytesSync();
      final t = FakeCatalogTransport(
        manifest: () async => manifestFor(r2, sha256: 'c' * 64),
        snapshot: (_) async => r2,
      );
      final r = repo(t);
      await r.load();

      expect(await r.refresh(force: true), CatalogRefreshOutcome.invalid);

      expect(snapshotFile().readAsBytesSync(), bytes);
      expect(await store.readLastCheckedAtMs(), 5);
      expect(r.state.snapshot?.release, 1);
      expect(r.state.status, CatalogStatus.ready);
    });

    test('release different from the manifest is invalid', () async {
      final t = FakeCatalogTransport(
        manifest: () async => manifestFor(r2, sha256: manifestFor(r1).sha256),
        snapshot: (_) async => r1,
      );
      final r = repo(t);
      expect(await r.refresh(), CatalogRefreshOutcome.invalid);
      expect(snapshotFile().existsSync(), isFalse);
      expect(r.state.status, CatalogStatus.unavailable);
    });

    test('structurally invalid snapshot is invalid', () async {
      final broken = {...r2}..remove('exercises');
      final t = FakeCatalogTransport(
        manifest: () async => manifestFor(r2),
        snapshot: (_) async => broken,
      );
      final r = repo(t);
      expect(await r.refresh(), CatalogRefreshOutcome.invalid);
      expect(snapshotFile().existsSync(), isFalse);
    });

    test('unsupported schema reports outdated app and keeps cache', () async {
      await seed(r1);
      final t = FakeCatalogTransport(
        manifest: () async => manifestFor(r2, minAppCatalogSchema: 2),
        snapshot: (_) async => r2,
      );
      final r = repo(t);
      await r.load();

      expect(await r.refresh(), CatalogRefreshOutcome.outdatedApp);

      expect(r.state.status, CatalogStatus.outdatedApp);
      expect(r.state.snapshot?.release, 1);
      expect(t.snapshotRequests, isEmpty);
      expect(await store.readLastCheckedAtMs(), now.millisecondsSinceEpoch);
    });

    test('outdated status clears once the app can read the release', () async {
      await seed(r1);
      var minApp = 2;
      final t = FakeCatalogTransport(
        manifest: () async => manifestFor(r1, minAppCatalogSchema: minApp),
        snapshot: (_) async => r1,
      );
      final r = repo(t);
      await r.load();
      await r.refresh();
      expect(r.state.status, CatalogStatus.outdatedApp);
      minApp = 1;
      expect(await r.refresh(force: true), CatalogRefreshOutcome.upToDate);
      expect(r.state.status, CatalogStatus.ready);
    });

    test('no live release is recorded and keeps state', () async {
      final t = FakeCatalogTransport(manifest: () async => null);
      final r = repo(t);
      expect(await r.refresh(), CatalogRefreshOutcome.noLiveRelease);
      expect(r.state.status, CatalogStatus.unavailable);
      expect(await store.readLastCheckedAtMs(), now.millisecondsSinceEpoch);
    });

    test('not live during rollback keeps cache', () async {
      await seed(r1, checkedAtMs: 7);
      final t = FakeCatalogTransport(
        manifest: () async => manifestFor(r2),
        snapshot: (_) async => throw const CatalogNotLive(),
      );
      final r = repo(t);
      await r.load();

      expect(await r.refresh(force: true), CatalogRefreshOutcome.notLive);

      expect(r.state.snapshot?.release, 1);
      expect(await store.readLastCheckedAtMs(), 7);
      expect(snapshotFile().readAsStringSync(), _canonical(r1));
    });

    test('timeout keeps cache and does not mark checked', () async {
      await seed(r1, checkedAtMs: 7);
      final t = FakeCatalogTransport(
        manifest: () async => throw const CatalogNetworkFailure('timeout'),
      );
      final r = repo(t);
      await r.load();

      expect(await r.refresh(force: true), CatalogRefreshOutcome.failed);

      expect(r.state.lastFailureKind, 'timeout');
      expect(r.state.status, CatalogStatus.ready);
      expect(r.state.snapshot?.release, 1);
      expect(await store.readLastCheckedAtMs(), 7);
    });

    test('success clears the failure kind', () async {
      var fail = true;
      final t = FakeCatalogTransport(
        manifest: () async => fail
            ? throw const CatalogNetworkFailure('network')
            : manifestFor(r1),
        snapshot: (_) async => r1,
      );
      final r = repo(t);
      await r.refresh();
      expect(r.state.lastFailureKind, 'network');
      fail = false;
      await r.refresh();
      expect(r.state.lastFailureKind, isNull);
    });

    test('unauthorized makes no snapshot call', () async {
      final t = FakeCatalogTransport(
        manifest: () async => throw const CatalogUnauthorized(),
        snapshot: (_) async => r1,
      );
      final r = repo(t);

      expect(await r.refresh(), CatalogRefreshOutcome.unauthorized);

      expect(t.snapshotRequests, isEmpty);
      expect(await store.readLastCheckedAtMs(), isNull);
      expect(r.state.status, CatalogStatus.unavailable);
    });

    test('concurrent refreshes share one request', () async {
      final gate = Completer<void>();
      final t = FakeCatalogTransport(
        manifest: () async {
          await gate.future;
          return manifestFor(r1);
        },
        snapshot: (_) async => r1,
      );
      final r = repo(t);

      final first = r.refresh();
      final second = r.refresh(force: true);
      gate.complete();

      expect(await first, CatalogRefreshOutcome.updated);
      expect(await second, CatalogRefreshOutcome.updated);
      expect(t.manifestCalls, 1);
      expect(t.snapshotRequests, [1]);
    });

    test('write failure keeps the old snapshot', () async {
      await seed(r1, checkedAtMs: 7);
      final failing = _FailingWriteStore(dir);
      final t = serving(r2);
      final r = repo(t, withStore: failing);
      await r.load();

      expect(await r.refresh(force: true), CatalogRefreshOutcome.failed);

      expect(r.state.snapshot?.release, 1);
      expect(r.state.lastFailureKind, isNotNull);
      expect(snapshotFile().readAsStringSync(), _canonical(r1));
      expect(await store.readLastCheckedAtMs(), 7);
    });

    test('dispose during refresh does not notify', () async {
      final gate = Completer<void>();
      final t = FakeCatalogTransport(
        manifest: () async {
          await gate.future;
          return manifestFor(r1);
        },
        snapshot: (_) async => r1,
      );
      final r = repo(t);
      await r.load();
      var notified = 0;
      r.addListener(() => notified++);

      final pending = r.refresh();
      await Future<void>.delayed(Duration.zero);
      r.dispose();
      gate.complete();
      await pending;

      expect(notified, 0);
      // The write still lands as a valid shared file for the next scope.
      expect(snapshotFile().readAsStringSync(), _canonical(r1));
    });

    test('refresh after dispose fails without calling the transport', () async {
      final t = serving(r1);
      final r = repo(t);
      r.dispose();
      expect(await r.refresh(), CatalogRefreshOutcome.failed);
      expect(t.manifestCalls, 0);
    });
  });

  group('invalid manifests back off', () {
    FakeCatalogTransport mismatching() => FakeCatalogTransport(
      manifest: () async => manifestFor(r2, sha256: 'c' * 64),
      snapshot: (_) async => r2,
    );

    test(
      'a rejected release is not downloaded again within 24 hours',
      () async {
        final t = mismatching();
        final r = repo(t);
        expect(await r.refresh(), CatalogRefreshOutcome.invalid);
        expect(t.snapshotRequests, [2]);

        now = now.add(const Duration(hours: 1));
        expect(await r.refresh(), CatalogRefreshOutcome.invalid);
        expect(t.manifestCalls, 2, reason: 'the manifest is still checked');
        expect(t.snapshotRequests, [2], reason: 'no second download');
      },
    );

    test('force ignores the backoff', () async {
      final t = mismatching();
      final r = repo(t);
      await r.refresh();
      expect(await r.refresh(force: true), CatalogRefreshOutcome.invalid);
      expect(t.snapshotRequests, [2, 2]);
    });

    test('backoff ends after 24 hours', () async {
      final t = mismatching();
      final r = repo(t);
      await r.refresh();
      now = now.add(const Duration(hours: 24));
      await r.refresh();
      expect(t.snapshotRequests, [2, 2]);
    });

    test('a different checksum for the same release is tried', () async {
      var sha = 'c' * 64;
      final t = FakeCatalogTransport(
        manifest: () async => manifestFor(r2, sha256: sha),
        snapshot: (_) async => r2,
      );
      final r = repo(t);
      await r.refresh();
      sha = 'd' * 64;
      await r.refresh();
      expect(t.snapshotRequests, [2, 2]);
    });

    test('a good release after a rejected one downloads normally', () async {
      var good = false;
      final t = FakeCatalogTransport(
        manifest: () async => manifestFor(r2, sha256: good ? null : 'c' * 64),
        snapshot: (_) async => r2,
      );
      final r = repo(t);
      await r.refresh();
      good = true;
      expect(await r.refresh(), CatalogRefreshOutcome.updated);
    });
  });

  group('forced refresh coalescing', () {
    test(
      'a forced call joining a skipped fresh check runs a real check',
      () async {
        await seed(r1, checkedAtMs: now.millisecondsSinceEpoch);
        final t = serving(r1);
        final r = repo(t);
        final plain = r.refresh();
        final forced = r.refresh(force: true);
        expect(await plain, CatalogRefreshOutcome.skippedFresh);
        expect(await forced, CatalogRefreshOutcome.upToDate);
        expect(t.manifestCalls, 1);
      },
    );
  });

  group('unexpected errors', () {
    test('a TypeError from the transport is a failed refresh', () async {
      final t = FakeCatalogTransport(manifest: () async => throw TypeError());
      final r = repo(t);
      expect(await r.refresh(), CatalogRefreshOutcome.failed);
      expect(r.state.lastFailureKind, 'unexpected');
      expect(await store.readLastCheckedAtMs(), isNull);
    });

    test('a TypeError from the parser is a failed refresh', () async {
      final t = serving(r1);
      final r = CatalogRepository(
        transport: t,
        store: store,
        clock: () => now,
        parseInBackground: (_) async => throw TypeError(),
      );
      expect(await r.refresh(), CatalogRefreshOutcome.failed);
      expect(r.state.lastFailureKind, 'unexpected');
    });

    test('a non-Exception from the store is a failed refresh', () async {
      final r = repo(serving(r1), withStore: _ThrowingStore(dir));
      expect(await r.refresh(), CatalogRefreshOutcome.failed);
      expect(r.state.lastFailureKind, 'unexpected');
    });

    test('load survives an unexpected store error', () async {
      final r = repo(serving(r1), withStore: _ThrowingStore(dir));
      await r.load();
      expect(r.state.status, CatalogStatus.unavailable);
    });
  });

  group('size limits', () {
    test(
      'a snapshot whose size differs from the manifest is invalid',
      () async {
        final t = FakeCatalogTransport(
          manifest: () async => manifestFor(r1, sizeBytes: 5),
          snapshot: (_) async => r1,
        );
        final r = repo(t);
        expect(await r.refresh(), CatalogRefreshOutcome.invalid);
        expect(snapshotFile().existsSync(), isFalse);
      },
    );

    test('a manifest over 2 MiB is rejected without downloading', () async {
      final t = FakeCatalogTransport(
        manifest: () async => manifestFor(r1, sizeBytes: 2 * 1024 * 1024 + 1),
        snapshot: (_) async => r1,
      );
      final r = repo(t);
      expect(await r.refresh(), CatalogRefreshOutcome.invalid);
      expect(t.snapshotRequests, isEmpty);
    });

    test(
      'a snapshot over 2 MiB is invalid even if the manifest agrees',
      () async {
        final big = snapshotJson();
        (big['provenance']! as Map<String, Object?>)['attribution'] =
            'x' * (2 * 1024 * 1024);
        final t = FakeCatalogTransport(
          manifest: () async => manifestFor(big),
          snapshot: (_) async => big,
        );
        final r = repo(t);
        expect(await r.refresh(), CatalogRefreshOutcome.invalid);
        expect(snapshotFile().existsSync(), isFalse);
      },
    );

    test(
      'hostile nesting is invalid, backs off and is not "unexpected"',
      () async {
        Object deep = 'x';
        for (var i = 0; i < 100000; i++) {
          deep = [deep];
        }
        final t = FakeCatalogTransport(
          manifest: () async => manifestFor(r1),
          snapshot: (_) async => deep,
        );
        final r = repo(t);
        expect(await r.refresh(), CatalogRefreshOutcome.invalid);
        expect(r.state.lastFailureKind, isNull);
        expect(t.snapshotRequests, hasLength(1));
        // Backoff: the same manifest is not downloaded again within 24 hours.
        expect(await r.refresh(), CatalogRefreshOutcome.invalid);
        expect(t.snapshotRequests, hasLength(1));
      },
    );

    test('a snapshot of exactly the manifest size is accepted', () async {
      final r = repo(serving(r1));
      expect(await r.refresh(), CatalogRefreshOutcome.updated);
    });
  });

  group('persisted outdated state', () {
    FakeCatalogTransport outdated() => FakeCatalogTransport(
      manifest: () async => manifestFor(r2, minAppCatalogSchema: 2),
    );

    test('survives a restart and keeps the cached snapshot usable', () async {
      await seed(r1);
      final first = repo(outdated());
      await first.load();
      expect(await first.refresh(), CatalogRefreshOutcome.outdatedApp);

      final restarted = repo(outdated());
      await restarted.load();
      expect(restarted.state.status, CatalogStatus.outdatedApp);
      expect(restarted.state.snapshot?.release, 1);
    });

    test('shows outdated with no cache after a restart', () async {
      final first = repo(outdated());
      await first.refresh();
      final restarted = repo(outdated());
      await restarted.load();
      expect(restarted.state.status, CatalogStatus.outdatedApp);
      expect(restarted.state.snapshot, isNull);
    });

    test('a later successful check clears it', () async {
      await seed(r1);
      final first = repo(outdated());
      await first.refresh();

      final t = serving(r1);
      final restarted = repo(t);
      await restarted.load();
      expect(
        await restarted.refresh(force: true),
        CatalogRefreshOutcome.upToDate,
      );
      expect(restarted.state.status, CatalogStatus.ready);
      expect(await store.readOutdated(), isNull);

      final again = repo(t);
      await again.load();
      expect(again.state.status, CatalogStatus.ready);
    });

    test('a mark from an older app schema is ignored and rechecked', () async {
      await seed(r1);
      await store.writeLastCheckedAtMs(
        now.millisecondsSinceEpoch,
        outdated: const CatalogOutdatedMark(release: 9, schema: 0),
      );
      final t = serving(r1);
      final r = repo(t);
      await r.load();
      expect(r.state.status, CatalogStatus.ready);
      expect(await r.refresh(), CatalogRefreshOutcome.upToDate);
      expect(t.manifestCalls, 1, reason: 'not skipped as fresh');
      expect(await store.readOutdated(), isNull);
    });
  });

  group('activation order', () {
    test('a meta write failure still leaves the new snapshot active', () async {
      await seed(r1, checkedAtMs: 7);
      var live = r1;
      final t = FakeCatalogTransport(
        manifest: () async => manifestFor(live),
        snapshot: (_) async => live,
      );
      final r = repo(t, withStore: _FailingMetaStore(dir));
      await r.load();
      live = r2;

      expect(await r.refresh(force: true), CatalogRefreshOutcome.failed);

      expect(r.state.snapshot?.release, 2);
      expect(r.state.status, CatalogStatus.ready);
      expect(r.state.lastFailureKind, 'storage');
      expect(snapshotFile().readAsStringSync(), _canonical(r2));
    });
  });
}
