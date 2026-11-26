import 'dart:io';

import 'package:beyondrep/core/storage/account_store.dart';
import 'package:beyondrep/features/health/data/health_connection_entity.dart';
import 'package:beyondrep/features/health/data/health_connection_repository.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/objectbox_pre_health_connection.g.dart' as pre;
import 'fixtures/objectbox_pre_health_scope.g.dart' as pre_scope;

const _accountA = '11111111-1111-4111-8111-111111111111';
const _accountB = '22222222-2222-4222-8222-222222222222';

void main() {
  test('the current access scope includes workouts', () {
    expect(currentHealthAccessScope, 3);
  });

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('beyondrep-health-conn-');
  });
  tearDown(() {
    root.deleteSync(recursive: true);
  });

  Store openAt(String relative) {
    final dir = Directory('${root.path}/$relative')
      ..createSync(recursive: true);
    return Store(getObjectBoxModel(), directory: dir.path);
  }

  String pathFor(String id) =>
      accountStoreRelativePath(id, projectHost: 'example.test');

  test('new store is not connected', () {
    final store = openAt('single');
    addTearDown(store.close);
    expect(
      ObjectBoxHealthConnectionRepository(store).isConnected('owner-a'),
      false,
    );
  });

  test('connect then disconnect', () {
    final store = openAt('single');
    addTearDown(store.close);
    final repo = ObjectBoxHealthConnectionRepository(store);
    repo.connect('owner-a', DateTime.fromMillisecondsSinceEpoch(1000));
    expect(repo.isConnected('owner-a'), true);
    repo.connect('owner-a', DateTime.fromMillisecondsSinceEpoch(2000));
    final box = store.box<HealthConnectionEntity>();
    expect(box.count(), 1);
    expect(box.getAll().single.connectedAtMs, 2000);
    repo.disconnect('owner-a');
    expect(repo.isConnected('owner-a'), false);
    expect(box.count(), 0);
  });

  test(
    'connectedAt returns the grant time, per owner, null after disconnect',
    () {
      final store = openAt('single');
      addTearDown(store.close);
      final repo = ObjectBoxHealthConnectionRepository(store);
      final at = DateTime(2026, 11, 20, 9);
      expect(repo.connectedAt('owner-a'), isNull);
      repo.connect('owner-a', at);
      expect(repo.connectedAt('owner-a'), at);
      expect(repo.connectedAt('owner-b'), isNull);
      repo.disconnect('owner-a');
      expect(repo.connectedAt('owner-a'), isNull);
    },
  );

  test('flag is per account directory', () {
    final a = openAt(pathFor(_accountA));
    final b = openAt(pathFor(_accountB));
    addTearDown(a.close);
    addTearDown(b.close);
    ObjectBoxHealthConnectionRepository(a)
        .connect(_accountA, DateTime.fromMillisecondsSinceEpoch(1));
    expect(ObjectBoxHealthConnectionRepository(a).isConnected(_accountA), true);
    expect(
      ObjectBoxHealthConnectionRepository(b).isConnected(_accountB),
      false,
    );
  });

  test('account deletion removes flag', () async {
    final a = openAt(pathFor(_accountA));
    ObjectBoxHealthConnectionRepository(a)
        .connect(_accountA, DateTime.fromMillisecondsSinceEpoch(1));
    a.close();
    await deleteBoundAccountStoreAtRoot(
      root,
      _accountA,
      projectHost: 'example.test',
    );
    final reopened = openAt(pathFor(_accountA));
    addTearDown(reopened.close);
    expect(
      ObjectBoxHealthConnectionRepository(reopened).isConnected(_accountA),
      false,
    );
  });

  test('pre-health DB upgrades', () {
    final dir = Directory('${root.path}/upgrade')..createSync();
    final old = Store(pre.getObjectBoxModel(), directory: dir.path);
    old.box<WorkoutSessionEntity>().put(
      WorkoutSessionEntity(
        uuid: 'session-1',
        name: 'Synthetic',
        status: 'completed',
        startedAtMs: 1,
        originalOffsetMinutes: 0,
        updatedAtMs: 1,
      ),
    );
    old.close();
    final upgraded = Store(getObjectBoxModel(), directory: dir.path);
    addTearDown(upgraded.close);
    expect(upgraded.box<WorkoutSessionEntity>().count(), 1);
    expect(upgraded.box<HealthConnectionEntity>().count(), 0);
  });

  test('connect records the current access scope; a request updates it', () {
    final store = openAt('single');
    addTearDown(store.close);
    final repo = ObjectBoxHealthConnectionRepository(store);
    expect(repo.accessScope('owner-a'), 0);
    repo.connect('owner-a', DateTime(2026, 11, 20));
    expect(repo.accessScope('owner-a'), currentHealthAccessScope);
    repo.recordAccessScope('owner-a', 0);
    expect(repo.accessScope('owner-a'), 0);
    expect(repo.connectedAt('owner-a'), DateTime(2026, 11, 20));
    repo.recordAccessScope('owner-b', currentHealthAccessScope);
    expect(repo.isConnected('owner-b'), false, reason: 'never connects');
  });

  test('a Phase 3 connection from an older store reads as scope 0', () {
    final dir = Directory('${root.path}/scope-upgrade')..createSync();
    final old = Store(pre_scope.getObjectBoxModel(), directory: dir.path);
    old.box<HealthConnectionEntity>().put(
      HealthConnectionEntity(ownerAccountId: _accountA, connectedAtMs: 1000),
    );
    old.close();
    final upgraded = Store(getObjectBoxModel(), directory: dir.path);
    addTearDown(upgraded.close);
    final repo = ObjectBoxHealthConnectionRepository(upgraded);
    expect(repo.isConnected(_accountA), true);
    expect(repo.connectedAt(_accountA)!.millisecondsSinceEpoch, 1000);
    expect(repo.accessScope(_accountA), 0);
  });
}
