import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/objectbox_store_provider.dart';
import '../../../objectbox.g.dart';
import 'health_export_entities.dart';

abstract interface class HealthExportRepository {
  bool isEnabled(String ownerAccountId);
  void enable(String ownerAccountId, DateTime at);
  void disable(String ownerAccountId);

  HealthExportReceiptEntity? receipt(String workoutUuid);
  List<HealthExportReceiptEntity> allReceipts();

  /// Upserts by (lowercased) workout UUID.
  void putReceipt(HealthExportReceiptEntity receipt);
  void removeReceipt(String workoutUuid);
}

class ObjectBoxHealthExportRepository implements HealthExportRepository {
  ObjectBoxHealthExportRepository(Store store)
    : _settings = store.box<HealthExportSettingEntity>(),
      _receipts = store.box<HealthExportReceiptEntity>();

  final Box<HealthExportSettingEntity> _settings;
  final Box<HealthExportReceiptEntity> _receipts;

  Query<HealthExportSettingEntity> _byOwner(String owner) => _settings
      .query(HealthExportSettingEntity_.ownerAccountId.equals(owner))
      .build();

  Query<HealthExportReceiptEntity> _byWorkout(String uuid) => _receipts
      .query(HealthExportReceiptEntity_.workoutUuid.equals(uuid.toLowerCase()))
      .build();

  @override
  bool isEnabled(String ownerAccountId) {
    final query = _byOwner(ownerAccountId);
    try {
      return query.count() > 0;
    } finally {
      query.close();
    }
  }

  @override
  void enable(String ownerAccountId, DateTime at) {
    final query = _byOwner(ownerAccountId);
    try {
      final existing = query.findFirst();
      _settings.put(
        HealthExportSettingEntity(
          id: existing?.id ?? 0,
          ownerAccountId: ownerAccountId,
          enabledAtMs: existing?.enabledAtMs ?? at.millisecondsSinceEpoch,
        ),
      );
    } finally {
      query.close();
    }
  }

  @override
  void disable(String ownerAccountId) {
    final query = _byOwner(ownerAccountId);
    try {
      query.remove();
    } finally {
      query.close();
    }
  }

  @override
  HealthExportReceiptEntity? receipt(String workoutUuid) {
    final query = _byWorkout(workoutUuid);
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  List<HealthExportReceiptEntity> allReceipts() => _receipts.getAll();

  @override
  void putReceipt(HealthExportReceiptEntity receipt) {
    final uuid = receipt.workoutUuid.toLowerCase();
    final existing = this.receipt(uuid);
    receipt
      ..workoutUuid = uuid
      ..id = existing?.id ?? 0;
    _receipts.put(receipt);
  }

  @override
  void removeReceipt(String workoutUuid) {
    final query = _byWorkout(workoutUuid);
    try {
      query.remove();
    } finally {
      query.close();
    }
  }
}

/// The platform record id of a confirmed receipt, else null. Android reads a
/// watch workout's heart rate and calories back through it.
String? confirmedPlatformRecordId(
  HealthExportRepository repository,
  String workoutUuid,
) {
  final r = repository.receipt(workoutUuid);
  final id = r?.platformRecordId;
  return r != null && r.state == 'confirmed' && id != null && id.isNotEmpty
      ? id
      : null;
}

final healthExportRepositoryProvider = Provider<HealthExportRepository>(
  (ref) => ObjectBoxHealthExportRepository(ref.watch(objectBoxStoreProvider)),
);
