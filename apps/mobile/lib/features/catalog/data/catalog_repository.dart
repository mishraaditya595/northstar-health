import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../domain/canonical_json.dart';
import '../domain/catalog_models.dart';
import '../domain/catalog_parser.dart';
import 'catalog_file_store.dart';
import 'catalog_transport.dart';

enum CatalogStatus { loading, ready, unavailable, outdatedApp }

enum CatalogRefreshOutcome {
  skippedFresh,
  upToDate,
  updated,
  noLiveRelease,
  outdatedApp,
  unauthorized,
  notLive,
  invalid,
  failed,
}

@immutable
class CatalogState {
  const CatalogState({
    this.snapshot,
    this.status = CatalogStatus.loading,
    this.lastFailureKind,
  });

  final CatalogSnapshot? snapshot;
  final CatalogStatus status;

  /// `timeout`, `network`, `server` or `storage`; never a response body.
  final String? lastFailureKind;
}

const _freshWindow = Duration(hours: 24);
const maxCatalogBytes = 2 * 1024 * 1024;

/// Room above the manifest's size_bytes while canonicalising, so a size lie is
/// measured and rejected instead of aborting mid-write.
const _sizeSlack = 1024;

typedef _Canonical = ({String text, String sha256, int length});

/// Canonical bytes, checksum and size, off the main isolate and never past
/// [maxBytes]. Throws on anything canonicalisation rejects.
Future<_Canonical> _canonicalizeInIsolate(Object? json, int maxBytes) =>
    Isolate.run(() {
      final bytes = canonicalJsonBytes(json, maxBytes: maxBytes);
      return (
        text: utf8.decode(bytes),
        sha256: sha256Hex(bytes),
        length: bytes.length,
      );
    });

Future<CatalogSnapshot?> _parseInIsolate(String text) => Isolate.run(() {
  try {
    return parseCatalogSnapshot(jsonDecode(text));
  } on Object {
    return null;
  }
});

/// Holds the validated catalogue in memory over an atomically swapped file.
/// Nothing here touches ObjectBox or any account data.
class CatalogRepository extends ChangeNotifier {
  CatalogRepository({
    required this.transport,
    required this.store,
    DateTime Function()? clock,
    Future<CatalogSnapshot?> Function(String text)? parseInBackground,
  }) : _clock = clock ?? DateTime.now,
       _parse = parseInBackground ?? _parseInIsolate;

  final CatalogTransport transport;
  final CatalogFileStore store;
  final DateTime Function() _clock;
  final Future<CatalogSnapshot?> Function(String text) _parse;

  CatalogState _state = const CatalogState();
  Future<void>? _loading;
  Future<CatalogRefreshOutcome>? _refreshing;
  bool _refreshingForced = false;
  bool _disposed = false;
  bool _recheckDespiteFresh = false;
  ({int release, String sha256, DateTime at})? _rejected;

  CatalogState get state => _state;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    CatalogSnapshot? snapshot;
    var outdated = false;
    try {
      await store.prepare();
      final text = await store.readSnapshotText();
      if (text != null) {
        snapshot = await _parse(text);
        if (snapshot == null) await store.deleteSnapshot();
      }
      final mark = await store.readOutdated();
      if (mark != null) {
        // A mark written by an app with another schema is stale: the app was
        // updated, so look again even inside the freshness window.
        if (mark.schema == supportedCatalogSchema) {
          outdated = true;
        } else {
          _recheckDespiteFresh = true;
        }
      }
    } on Object {
      snapshot = null;
    }
    _set(
      CatalogState(
        snapshot: snapshot,
        status: outdated
            ? CatalogStatus.outdatedApp
            : snapshot == null
            ? CatalogStatus.unavailable
            : CatalogStatus.ready,
      ),
    );
  }

  Future<CatalogRefreshOutcome> refresh({bool force = false}) {
    if (_disposed) return Future.value(CatalogRefreshOutcome.failed);
    final running = _refreshing;
    if (running != null) {
      if (!force || _refreshingForced) return running;
      // A forced call must not be answered by a check that was skipped as
      // fresh: run a real one once the shared check is done.
      return running.then(
        (outcome) => outcome == CatalogRefreshOutcome.skippedFresh
            ? refresh(force: true)
            : outcome,
      );
    }
    _refreshingForced = force;
    final next = _refresh(force).whenComplete(() => _refreshing = null);
    return _refreshing = next;
  }

  Future<CatalogRefreshOutcome> _refresh(bool force) async {
    await load();
    CatalogManifest? manifest;
    try {
      if (!force && !_recheckDespiteFresh && await _isFresh()) {
        return CatalogRefreshOutcome.skippedFresh;
      }
      _recheckDespiteFresh = false;

      manifest = await transport.fetchManifest();
      if (manifest == null) {
        await _markChecked();
        _clearTransient();
        return CatalogRefreshOutcome.noLiveRelease;
      }
      if (manifest.minAppCatalogSchema > supportedCatalogSchema) {
        await _markChecked(
          outdated: CatalogOutdatedMark(
            release: manifest.release,
            schema: supportedCatalogSchema,
          ),
        );
        _set(
          CatalogState(
            snapshot: _state.snapshot,
            status: CatalogStatus.outdatedApp,
          ),
        );
        return CatalogRefreshOutcome.outdatedApp;
      }
      final current = _state.snapshot;
      if (current != null &&
          current.release == manifest.release &&
          current.sha256 == manifest.sha256) {
        await _markChecked();
        _clearTransient();
        return CatalogRefreshOutcome.upToDate;
      }
      if (manifest.sizeBytes > maxCatalogBytes ||
          _isBackedOff(manifest, force)) {
        _reject(manifest);
        return CatalogRefreshOutcome.invalid;
      }

      final json = await transport.fetchSnapshot(manifest.release);
      final cap = min(manifest.sizeBytes + _sizeSlack, maxCatalogBytes);
      final _Canonical canonical;
      try {
        canonical = await _canonicalizeInIsolate(json, cap);
      } on Object {
        // Any error from canonicalisation (too deep, too big, a double, a bad
        // key, unsendable) is hostile or broken content: invalid with backoff,
        // not "unexpected".
        _reject(manifest);
        return CatalogRefreshOutcome.invalid;
      }
      // Size and checksum are settled before any structural parse.
      if (canonical.length != manifest.sizeBytes ||
          canonical.sha256 != manifest.sha256) {
        _reject(manifest);
        return CatalogRefreshOutcome.invalid;
      }
      final text = canonical.text;
      final parsed = await _parse(text);
      if (parsed == null ||
          parsed.sha256 != manifest.sha256 ||
          parsed.release != manifest.release) {
        _reject(manifest);
        return CatalogRefreshOutcome.invalid;
      }
      await store.writeSnapshotText(text);
      // Active as soon as the rename succeeded, even if the metadata write
      // below fails; the next start loads the same file.
      _rejected = null;
      _set(CatalogState(snapshot: parsed, status: CatalogStatus.ready));
      await _markChecked();
      return CatalogRefreshOutcome.updated;
    } on CatalogUnauthorized {
      return CatalogRefreshOutcome.unauthorized;
    } on CatalogNotLive {
      return CatalogRefreshOutcome.notLive;
    } on CatalogFormatException {
      return CatalogRefreshOutcome.invalid;
    } on CatalogNetworkFailure catch (error) {
      _fail(error.kind);
      return CatalogRefreshOutcome.failed;
    } on FileSystemException {
      _fail('storage');
      return CatalogRefreshOutcome.failed;
    } on Object {
      // Nothing thrown from here may become an unhandled async error.
      _fail('unexpected');
      return CatalogRefreshOutcome.failed;
    }
  }

  bool _isBackedOff(CatalogManifest manifest, bool force) {
    final rejected = _rejected;
    if (force || rejected == null) return false;
    if (rejected.release != manifest.release ||
        rejected.sha256 != manifest.sha256) {
      return false;
    }
    final age = _clock().difference(rejected.at);
    return !age.isNegative && age < _freshWindow;
  }

  void _reject(CatalogManifest manifest) => _rejected = (
    release: manifest.release,
    sha256: manifest.sha256,
    at: _clock(),
  );

  /// Fresh means checked less than 24 hours ago. A timestamp in the future
  /// (clock moved backwards) is never fresh.
  Future<bool> _isFresh() async {
    final last = await store.readLastCheckedAtMs();
    if (last == null) return false;
    final now = _clock().millisecondsSinceEpoch;
    return last <= now && now - last < _freshWindow.inMilliseconds;
  }

  Future<void> _markChecked({CatalogOutdatedMark? outdated}) =>
      store.writeLastCheckedAtMs(
        _clock().millisecondsSinceEpoch,
        outdated: outdated,
      );

  /// A successful check ends an earlier outdated-app or failure display.
  void _clearTransient() {
    final snapshot = _state.snapshot;
    _set(
      CatalogState(
        snapshot: snapshot,
        status: snapshot == null
            ? CatalogStatus.unavailable
            : CatalogStatus.ready,
      ),
    );
  }

  void _fail(String kind) => _set(
    CatalogState(
      snapshot: _state.snapshot,
      status: _state.status,
      lastFailureKind: kind,
    ),
  );

  void _set(CatalogState next) {
    _state = next;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
