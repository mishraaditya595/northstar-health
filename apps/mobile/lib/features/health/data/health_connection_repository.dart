import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/objectbox_store_provider.dart';
import '../../../objectbox.g.dart';
import 'health_connection_entity.dart';

abstract interface class HealthConnectionRepository {
  bool isConnected(String ownerAccountId);
  void connect(String ownerAccountId, DateTime at);
  void disconnect(String ownerAccountId);
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
  void connect(String ownerAccountId, DateTime at) {
    final query = _byOwner(ownerAccountId);
    try {
      final existing = query.findFirst();
      _box.put(
        HealthConnectionEntity(
          id: existing?.id ?? 0,
          ownerAccountId: ownerAccountId,
          connectedAtMs: at.millisecondsSinceEpoch,
        ),
      );
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
