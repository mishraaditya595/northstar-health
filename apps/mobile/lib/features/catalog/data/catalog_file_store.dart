import 'dart:convert';
import 'dart:io';

/// Cache directory below the app store directory, per backend host and shared
/// by every account on that host. Mirrors the host validation of
/// `accountStoreRelativePath`, and also rejects dot segments.
String catalogCacheRelativePath(String projectHost) {
  final host = projectHost.toLowerCase();
  if (!RegExp(r'^[a-z0-9.-]+$').hasMatch(host) ||
      host.startsWith('.') ||
      host.contains('..')) {
    throw const FormatException('Invalid backend host');
  }
  return 'northstar_catalog/$host';
}

/// Atomic file cache: the snapshot file is the canonical snapshot bytes and
/// is only ever replaced by renaming a fully written temp file over it.
class CatalogFileStore {
  CatalogFileStore(this._directory);

  final Directory _directory;

  File get _snapshot => File('${_directory.path}/snapshot.json');
  File get _snapshotTmp => File('${_directory.path}/snapshot.json.tmp');
  File get _meta => File('${_directory.path}/meta.json');
  File get _metaTmp => File('${_directory.path}/meta.json.tmp');

  Future<void> prepare() async {
    await _directory.create(recursive: true);
    for (final stale in [_snapshotTmp, _metaTmp]) {
      if (await stale.exists()) await stale.delete();
    }
  }

  Future<String?> readSnapshotText() async {
    try {
      return await _snapshot.readAsString();
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<void> writeSnapshotText(String text) =>
      _writeAtomically(_snapshotTmp, _snapshot, text);

  Future<void> deleteSnapshot() async {
    if (await _snapshot.exists()) await _snapshot.delete();
  }

  Future<int?> readLastCheckedAtMs() async {
    try {
      final decoded = jsonDecode(await _meta.readAsString());
      if (decoded is Map && decoded['lastCheckedAtMs'] is int) {
        return decoded['lastCheckedAtMs'] as int;
      }
      return null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<void> writeLastCheckedAtMs(int value) =>
      _writeAtomically(_metaTmp, _meta, jsonEncode({'lastCheckedAtMs': value}));

  Future<void> _writeAtomically(File tmp, File target, String text) async {
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(target.path);
  }
}
