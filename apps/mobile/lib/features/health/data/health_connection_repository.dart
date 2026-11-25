import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/objectbox_store_provider.dart';
import '../../../objectbox.g.dart';
import 'health_connection_entity.dart';

/// Version of the read-type list the app requests: 0 for Phase 3 (sleep,
/// steps, resting heart rate, weight), 2 for health insights stage 1. Bump it
/// when the requested types change.
const currentHealthAccessScope = 2;

abstract interface class HealthConnectionRepository {
  bool isConnected(String ownerAccountId);
  DateTime? connectedAt(String ownerAccountId);

  /// Records the connection with [currentHealthAccessScope].
  void connect(String ownerAccountId, DateTime at);
  void disconnect(String ownerAccountId);

  /// The scope last requested; 0 when unknown or not connected.
  int accessScope(String ownerAccountId);

  /// No-op when not connected.
  void recordAccessScope(String ownerAccountId, int scope);
}

class ObjectBoxHealthConnectionRepository
    implements HealthConnectionRepository {
  ObjectBoxHealthConnectionRepository(Store store)
    : _box = store.box<HealthConnectionEntity>();

  final Box<HealthConnectionEntity> _box;

  Query<HealthConnectionEntity> _byOwner(String ownerAccountId) => _box
      .query(HealthConnectionEntity_.ownerAccountId.equals(ownerAccountId))
      .build();

  @override
  bool isConnected(String ownerAccountId) {
    final query = _byOwner(ownerAccountId);
    try {
      return query.count() > 0;
    } finally {
      query.close();
    }
  }

  @override
  DateTime? connectedAt(String ownerAccountId) {
    final query = _byOwner(ownerAccountId);
    try {
      final ms = query.findFirst()?.connectedAtMs;
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } finally {
      query.close();
    }
  }

  @override
  void connect(String ownerAccountId, DateTime at) {
    final query = _byOwner(ownerAccountId);
    try {
      final existing = query.findFirst();
      _box.put(
        HealthConnectionEntity(
          id: existing?.id ?? 0,
          ownerAccountId: ownerAccountId,
          connectedAtMs: at.millisecondsSinceEpoch,
          accessScope: currentHealthAccessScope,
        ),
      );
    } finally {
      query.close();
    }
  }

  @override
  int accessScope(String ownerAccountId) {
    final query = _byOwner(ownerAccountId);
    try {
      return query.findFirst()?.accessScope ?? 0;
    } finally {
      query.close();
    }
  }

  @override
  void recordAccessScope(String ownerAccountId, int scope) {
    final query = _byOwner(ownerAccountId);
    try {
      final existing = query.findFirst();
      if (existing == null) return;
      _box.put(existing..accessScope = scope);
    } finally {
      query.close();
    }
  }

  @override
  void disconnect(String ownerAccountId) {
    final query = _byOwner(ownerAccountId);
    try {
      query.remove();
    } finally {
      query.close();
    }
  }
}

final healthConnectionRepositoryProvider = Provider<HealthConnectionRepository>(
  (ref) =>
      ObjectBoxHealthConnectionRepository(ref.watch(objectBoxStoreProvider)),
);
