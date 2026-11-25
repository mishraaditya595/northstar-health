import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

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
  bool _disposed = false;

  CatalogState get state => _state;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    CatalogSnapshot? snapshot;
    try {
      await store.prepare();
      final text = await store.readSnapshotText();
      if (text != null) {
        snapshot = await _parse(text);
        if (snapshot == null) await store.deleteSnapshot();
      }
    } on FileSystemException {
      snapshot = null;
    }
    _set(
      CatalogState(
        snapshot: snapshot,
        status: snapshot == null
            ? CatalogStatus.unavailable
            : CatalogStatus.ready,
      ),
    );
  }

  Future<CatalogRefreshOutcome> refresh({bool force = false}) {
    if (_disposed) return Future.value(CatalogRefreshOutcome.failed);
    final running = _refreshing;
    if (running != null) return running;
    final next = _refresh(force).whenComplete(() => _refreshing = null);
    return _refreshing = next;
  }

  Future<CatalogRefreshOutcome> _refresh(bool force) async {
    await load();
    try {
      if (!force && await _isFresh()) return CatalogRefreshOutcome.skippedFresh;

      final manifest = await transport.fetchManifest();
      if (manifest == null) {
        await _markChecked();
        _clearTransient();
        return CatalogRefreshOutcome.noLiveRelease;
      }
      if (manifest.minAppCatalogSchema > supportedCatalogSchema) {
        await _markChecked();
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

      final json = await transport.fetchSnapshot(manifest.release);
      final text = utf8.decode(canonicalJsonBytes(json));
      final parsed = await _parse(text);
      if (parsed == null ||
          parsed.sha256 != manifest.sha256 ||
          parsed.release != manifest.release) {
        return CatalogRefreshOutcome.invalid;
      }
      await store.writeSnapshotText(text);
      await _markChecked();
      _set(CatalogState(snapshot: parsed, status: CatalogStatus.ready));
      return CatalogRefreshOutcome.updated;
    } on CatalogUnauthorized {
      return CatalogRefreshOutcome.unauthorized;
    } on CatalogNotLive {
      return CatalogRefreshOutcome.notLive;
    } on CatalogFormatException {
      return CatalogRefreshOutcome.invalid;
    } on ArgumentError {
      return CatalogRefreshOutcome.invalid;
    } on CatalogNetworkFailure catch (error) {
      _fail(error.kind);
      return CatalogRefreshOutcome.failed;
    } on FileSystemException {
      _fail('storage');
      return CatalogRefreshOutcome.failed;
    }
  }

  /// Fresh means checked less than 24 hours ago. A timestamp in the future
  /// (clock moved backwards) is never fresh.
  Future<bool> _isFresh() async {
    final last = await store.readLastCheckedAtMs();
    if (last == null) return false;
    final now = _clock().millisecondsSinceEpoch;
    return last <= now && now - last < _freshWindow.inMilliseconds;
  }

  Future<void> _markChecked() =>
      store.writeLastCheckedAtMs(_clock().millisecondsSinceEpoch);

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
