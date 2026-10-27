import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/storage/account_store.dart';

const _owner = '00000000-0000-4000-8000-0000000000a1';
const _other = '00000000-0000-4000-8000-0000000000b2';

void main() {
  test('confirmed local cleanup erases only its owner partition', () async {
    final base = await Directory.systemTemp.createTemp('northstar-delete-');
    addTearDown(() => base.delete(recursive: true));

    Directory path(String id, String host) => Directory(
      '${base.path}/${accountStoreRelativePath(id, projectHost: host)}',
    );

    final a = path(_owner, 'dev.example.invalid');
    final b = path(_other, 'dev.example.invalid');
    final separateProject = path(_owner, 'prod.example.invalid');

    for (final dir in [a, b, separateProject]) {
      await dir.create(recursive: true);
      await File('${dir.path}/data.mdb').writeAsString('sample');
    }

    await deleteBoundAccountStoreAtRoot(
      base, _owner, projectHost: 'dev.example.invalid',
    );
    expect(await a.exists(), false);
    expect(await b.exists(), true);
    expect(await separateProject.exists(), true);
    expect(await File('${b.path}/data.mdb').readAsString(), 'sample');

    // Retrying a completed cleanup must be safe.
    await deleteBoundAccountStoreAtRoot(
      base, _owner, projectHost: 'dev.example.invalid',
    );
    expect(await b.exists(), true);
  });

  test('untrusted owner directory identifiers cannot cause traversal', () async {
    final base = await Directory.systemTemp.createTemp('northstar-safety-');
    addTearDown(() => base.delete(recursive: true));
    await expectLater(
      deleteBoundAccountStoreAtRoot(
        base, '../other-account', projectHost: 'dev.example.invalid',
      ),
      throwsFormatException,
    );
    expect(await base.exists(), true);
  });
}
