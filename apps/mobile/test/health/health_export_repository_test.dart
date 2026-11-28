import 'dart:io';

import 'package:beyondrep/features/health/data/health_export_entities.dart';
import 'package:beyondrep/features/health/data/health_export_repository.dart';
import 'package:beyondrep/features/health/domain/health_export_state.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter_test/flutter_test.dart';

const _owner = '11111111-1111-4111-8111-111111111111';
const _uuid = 'abcdef00-0000-4000-8000-000000000001';

void main() {
  late Directory dir;
  late Store store;
  late ObjectBoxHealthExportRepository repo;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('beyondrep-health-export-');
    store = Store(getObjectBoxModel(), directory: dir.path);
    repo = ObjectBoxHealthExportRepository(store);
  });
  tearDown(() {
    store.close();
    dir.deleteSync(recursive: true);
  });

  HealthExportReceiptEntity receipt(String uuid, {String state = 'writing'}) =>
      HealthExportReceiptEntity(
        workoutUuid: uuid,
        platform: 'healthkit',
        state: state,
        updatedAtMs: 1,
      );

  test('confirmedPlatformRecordId is the id of a confirmed receipt only', () {
    expect(confirmedPlatformRecordId(repo, _uuid), isNull);
    repo.putReceipt(
      HealthExportReceiptEntity(
        workoutUuid: _uuid,
        platform: 'health_connect',
        state: 'writing',
        platformRecordId: 'rec-1',
        updatedAtMs: 1,
      ),
    );
    expect(confirmedPlatformRecordId(repo, _uuid), isNull);
    repo.putReceipt(
      HealthExportReceiptEntity(
        workoutUuid: _uuid,
        platform: 'health_connect',
        state: 'confirmed',
        platformRecordId: 'rec-1',
        updatedAtMs: 2,
      ),
    );
    expect(confirmedPlatformRecordId(repo, _uuid.toUpperCase()), 'rec-1');
    repo.putReceipt(
      HealthExportReceiptEntity(
        workoutUuid: _uuid,
        platform: 'health_connect',
        state: 'confirmed',
        platformRecordId: '',
        updatedAtMs: 3,
      ),
    );
    expect(confirmedPlatformRecordId(repo, _uuid), isNull);
  });

  test('enable then isEnabled is true; disable removes the row', () {
    expect(repo.isEnabled(_owner), isFalse);
    repo.enable(_owner, DateTime.fromMillisecondsSinceEpoch(5));
    expect(repo.isEnabled(_owner), isTrue);
    repo.disable(_owner);
    expect(repo.isEnabled(_owner), isFalse);
    expect(store.box<HealthExportSettingEntity>().count(), 0);
  });

  test('enable twice keeps one row', () {
    repo.enable(_owner, DateTime.fromMillisecondsSinceEpoch(5));
    repo.enable(_owner, DateTime.fromMillisecondsSinceEpoch(9));
    expect(store.box<HealthExportSettingEntity>().count(), 1);
  });

  test('putReceipt upserts by workoutUuid', () {
    repo.putReceipt(receipt(_uuid));
    repo.putReceipt(receipt(_uuid, state: 'confirmed'));
    expect(repo.allReceipts(), hasLength(1));
    expect(repo.receipt(_uuid)!.state, 'confirmed');
  });

  test('removeReceipt deletes and receipt returns null for unknown', () {
    expect(repo.receipt('nope'), isNull);
    repo.putReceipt(receipt(_uuid));
    repo.removeReceipt(_uuid);
    expect(repo.receipt(_uuid), isNull);
    expect(repo.allReceipts(), isEmpty);
  });

  test('workout uuid is stored lowercase', () {
    repo.putReceipt(receipt(_uuid.toUpperCase()));
    expect(repo.receipt(_uuid)!.workoutUuid, _uuid);
    expect(repo.receipt(_uuid.toUpperCase()), isNotNull);
  });

  test('HealthExportState wire names round trip', () {
    for (final s in HealthExportState.values) {
      expect(HealthExportState.fromWire(s.wire), s);
    }
    expect(HealthExportState.fromWire('bogus'), isNull);
    expect(HealthExportState.failedRetryable.wire, 'failedRetryable');
  });
}
