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

  test('prepare creates the directory and deletes stale temp files', () async {
    dir.createSync(recursive: true);
    file('snapshot.json.tmp').writeAsStringSync('partial');
    file('meta.json.tmp').writeAsStringSync('partial');
    file('snapshot.json').writeAsStringSync('kept');

    await store.prepare();

    expect(file('snapshot.json.tmp').existsSync(), isFalse);
    expect(file('meta.json.tmp').existsSync(), isFalse);
    expect(file('snapshot.json').readAsStringSync(), 'kept');

    final fresh = CatalogFileStore(Directory('${root.path}/new/deep'));
    await fresh.prepare();
    expect(Directory('${root.path}/new/deep').existsSync(), isTrue);
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

  test('write leaves the old file when the temp write fails', () async {
    await store.prepare();
    await store.writeSnapshotText('A');
    Directory('${dir.path}/snapshot.json.tmp').createSync();

    await expectLater(
      store.writeSnapshotText('B'),
      throwsA(isA<FileSystemException>()),
    );
    expect(file('snapshot.json').readAsStringSync(), 'A');
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
}
