import 'dart:io';

import 'package:beyondrep/features/catalog/data/catalog_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory dir;
  late CatalogFileStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('catalog_store_test');
    dir = Directory('${root.path}/cache');
    store = CatalogFileStore(dir);
  });

  tearDown(() => root.deleteSync(recursive: true));

  File file(String name) => File('${dir.path}/$name');

  test('prepare creates the directory and keeps recent temp files', () async {
    dir.createSync(recursive: true);
    file('snapshot.json.abc.tmp').writeAsStringSync('in flight');
    file('snapshot.json').writeAsStringSync('kept');

    await store.prepare();

    expect(file('snapshot.json.abc.tmp').existsSync(), isTrue);
    expect(file('snapshot.json').readAsStringSync(), 'kept');

    final fresh = CatalogFileStore(Directory('${root.path}/new/deep'));
    await fresh.prepare();
    expect(Directory('${root.path}/new/deep').existsSync(), isTrue);
  });

  test('prepare deletes only temp files older than 10 minutes', () async {
    dir.createSync(recursive: true);
    final old = DateTime.now().subtract(const Duration(minutes: 11));
    file('snapshot.json.old.tmp')
      ..writeAsStringSync('partial')
      ..setLastModifiedSync(old);
    file('meta.json.old.tmp')
      ..writeAsStringSync('partial')
      ..setLastModifiedSync(old);
    file('snapshot.json.new.tmp').writeAsStringSync('partial');
    file('snapshot.json')
      ..writeAsStringSync('kept')
      ..setLastModifiedSync(old);
    file('unrelated.tmp')
      ..writeAsStringSync('x')
      ..setLastModifiedSync(old);

    await store.prepare();

    expect(file('snapshot.json.old.tmp').existsSync(), isFalse);
    expect(file('meta.json.old.tmp').existsSync(), isFalse);
    expect(file('snapshot.json.new.tmp').existsSync(), isTrue);
    expect(file('snapshot.json').readAsStringSync(), 'kept');
    expect(file('unrelated.tmp').existsSync(), isTrue);
  });

  test('write then read round-trips', () async {
    await store.prepare();
    await store.writeSnapshotText('{"a":"ü"}');
    await store.writeLastCheckedAtMs(1234);
    expect(await store.readSnapshotText(), '{"a":"ü"}');
    expect(await store.readLastCheckedAtMs(), 1234);
    expect(file('meta.json').readAsStringSync(), '{"lastCheckedAtMs":1234}');
  });

  test('write replaces atomically', () async {
    await store.prepare();
    await store.writeSnapshotText('A');
    await store.writeSnapshotText('B');
    expect(file('snapshot.json').readAsStringSync(), 'B');
    expect(file('snapshot.json.tmp').existsSync(), isFalse);
  });

  test('concurrent writes use distinct temp files', () async {
    await store.prepare();
    await Future.wait([
      store.writeSnapshotText('A' * 100000),
      store.writeSnapshotText('B' * 100000),
    ]);
    final text = file('snapshot.json').readAsStringSync();
    expect(text == 'A' * 100000 || text == 'B' * 100000, isTrue);
    expect(
      dir.listSync().whereType<File>().where((f) => f.path.endsWith('.tmp')),
      isEmpty,
    );
  });

  test('write leaves the old file when the temp write fails', () async {
    final failing = CatalogFileStore(dir, tempSuffix: () => 'x');
    await failing.prepare();
    await failing.writeSnapshotText('A');
    Directory('${dir.path}/snapshot.json.x.tmp').createSync();

    await expectLater(
      failing.writeSnapshotText('B'),
      throwsA(isA<FileSystemException>()),
    );
    expect(file('snapshot.json').readAsStringSync(), 'A');
  });

  test(
    'a failed rename removes its temp file and keeps the old file',
    () async {
      await store.prepare();
      await store.writeSnapshotText('A');
      // A directory at the target makes the final rename fail.
      final blocked = CatalogFileStore(dir, tempSuffix: () => 'y');
      file('snapshot.json').deleteSync();
      Directory('${dir.path}/snapshot.json').createSync();
      await expectLater(
        blocked.writeSnapshotText('B'),
        throwsA(isA<FileSystemException>()),
      );
      expect(file('snapshot.json.y.tmp').existsSync(), isFalse);
    },
  );

  test('outdated mark round-trips and is cleared by a plain write', () async {
    await store.prepare();
    expect(await store.readOutdated(), isNull);
    await store.writeLastCheckedAtMs(
      5,
      outdated: const CatalogOutdatedMark(release: 9, schema: 1),
    );
    final mark = await store.readOutdated();
    expect(mark?.release, 9);
    expect(mark?.schema, 1);
    expect(await store.readLastCheckedAtMs(), 5);
    await store.writeLastCheckedAtMs(6);
    expect(await store.readOutdated(), isNull);
    expect(await store.readLastCheckedAtMs(), 6);
  });

  test('corrupt outdated mark reads as null', () async {
    await store.prepare();
    file('meta.json').writeAsStringSync(
      '{"lastCheckedAtMs":1,"outdatedRelease":"x","outdatedSchema":1}',
    );
    expect(await store.readOutdated(), isNull);
    expect(await store.readLastCheckedAtMs(), 1);
  });

  test('deleteSnapshot removes the file and tolerates absence', () async {
    await store.prepare();
    await store.writeSnapshotText('A');
    await store.deleteSnapshot();
    expect(await store.readSnapshotText(), isNull);
    await store.deleteSnapshot();
  });

  test('corrupt meta reads as null', () async {
    await store.prepare();
    for (final bad in ['not json', '[]', '{"lastCheckedAtMs":"x"}', '{}']) {
      file('meta.json').writeAsStringSync(bad);
      expect(await store.readLastCheckedAtMs(), isNull, reason: bad);
    }
  });

  test('missing files read as null', () async {
    await store.prepare();
    expect(await store.readSnapshotText(), isNull);
    expect(await store.readLastCheckedAtMs(), isNull);
  });

  test('relative path rejects an invalid host', () {
    expect(
      catalogCacheRelativePath('Example.Supabase.co'),
      'northstar_catalog/example.supabase.co',
    );
    for (final bad in [
      'a/b',
      '..%2f',
      'host name',
      '',
      'a:b',
      '.',
      '..',
      'a..b',
    ]) {
      expect(
        () => catalogCacheRelativePath(bad),
        throwsA(isA<FormatException>()),
        reason: bad,
      );
    }
  });

  test(
    'snapshot identity round-trips and survives later meta writes',
    () async {
      await store.prepare();
      expect(await store.readSnapshotIdentity(), isNull);
      await store.writeSnapshotIdentity(release: 4, sha256: 'a' * 64);
      final identity = await store.readSnapshotIdentity();
      expect(identity?.release, 4);
      expect(identity?.sha256, 'a' * 64);
      await store.writeLastCheckedAtMs(
        9,
        outdated: const CatalogOutdatedMark(release: 5, schema: 1),
      );
      expect((await store.readSnapshotIdentity())?.sha256, 'a' * 64);
      expect(await store.readLastCheckedAtMs(), 9);
      // Writing the identity keeps the check time and the outdated mark.
      await store.writeSnapshotIdentity(release: 5, sha256: 'b' * 64);
      expect(await store.readLastCheckedAtMs(), 9);
      expect((await store.readOutdated())?.release, 5);
      expect((await store.readSnapshotIdentity())?.release, 5);
    },
  );

  test('a meta file from before identity reads as no identity', () async {
    await store.prepare();
    file('meta.json').writeAsStringSync('{"lastCheckedAtMs":3}');
    expect(await store.readSnapshotIdentity(), isNull);
    expect(await store.readLastCheckedAtMs(), 3);
    for (final bad in [
      '{"snapshotRelease":"x","snapshotSha256":"${'a' * 64}"}',
      '{"snapshotRelease":4,"snapshotSha256":"short"}',
      '{"snapshotRelease":4}',
    ]) {
      file('meta.json').writeAsStringSync(bad);
      expect(await store.readSnapshotIdentity(), isNull, reason: bad);
    }
  });
}
