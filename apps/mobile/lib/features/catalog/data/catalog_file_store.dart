import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

/// The last check found a release this app cannot read. [schema] is the
/// catalogue schema the app supported then, so an app update clears it.
class CatalogOutdatedMark {
  const CatalogOutdatedMark({required this.release, required this.schema});

  final int release;
  final int schema;
}

String _randomSuffix() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '${Random.secure().nextInt(1 << 32).toRadixString(36)}';

/// Atomic file cache: the snapshot file is the canonical snapshot bytes and
/// is only ever replaced by renaming a fully written, uniquely named temp
/// file over it.
class CatalogFileStore {
  CatalogFileStore(this._directory, {String Function()? tempSuffix})
    : _tempSuffix = tempSuffix ?? _randomSuffix;

  static const _staleTempAge = Duration(minutes: 10);
  static final _tempName = RegExp(r'^(snapshot|meta)\.json\..+\.tmp$');

  final Directory _directory;
  final String Function() _tempSuffix;

  File get _snapshot => File('${_directory.path}/snapshot.json');
  File get _meta => File('${_directory.path}/meta.json');

  /// Creates the directory and deletes temp files left by a killed write.
  /// Recent temp files may belong to a write in another scope; keep them.
  Future<void> prepare() async {
    await _directory.create(recursive: true);
    final now = DateTime.now();
    await for (final entity in _directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!_tempName.hasMatch(name)) continue;
      try {
        final age = now.difference(await entity.lastModified());
        if (age > _staleTempAge) await entity.delete();
      } on FileSystemException {
        // Removed by its writer meanwhile.
      }
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
      _writeAtomically(_snapshot, 'snapshot.json', text);

  Future<void> deleteSnapshot() async {
    if (await _snapshot.exists()) await _snapshot.delete();
  }

  Future<Map<String, Object?>?> _readMeta() async {
    try {
      final decoded = jsonDecode(await _meta.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<int?> readLastCheckedAtMs() async {
    final value = (await _readMeta())?['lastCheckedAtMs'];
    return value is int ? value : null;
  }

  Future<CatalogOutdatedMark?> readOutdated() async {
    final meta = await _readMeta();
    final release = meta?['outdatedRelease'];
    final schema = meta?['outdatedSchema'];
    if (release is int && schema is int) {
      return CatalogOutdatedMark(release: release, schema: schema);
    }
    return null;
  }

  /// Replaces the whole metadata file, so omitting [outdated] clears it.
  Future<void> writeLastCheckedAtMs(
    int value, {
    CatalogOutdatedMark? outdated,
  }) => _writeAtomically(
    _meta,
    'meta.json',
    jsonEncode({
      'lastCheckedAtMs': value,
      if (outdated != null) 'outdatedRelease': outdated.release,
      if (outdated != null) 'outdatedSchema': outdated.schema,
    }),
  );

  Future<void> _writeAtomically(File target, String name, String text) async {
    final tmp = File('${_directory.path}/$name.${_tempSuffix()}.tmp');
    try {
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(target.path);
    } on FileSystemException {
      try {
        if (await FileSystemEntity.type(tmp.path) ==
            FileSystemEntityType.file) {
          await tmp.delete();
        }
      } on FileSystemException {
        // Best effort; prepare() removes it later.
      }
      rethrow;
    }
  }
}
