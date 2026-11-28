import 'dart:async';
import 'dart:io';

import 'package:beyondrep/core/storage/objectbox_store_provider.dart';
import 'package:beyondrep/features/account/account_auth_controller.dart';
import 'package:beyondrep/features/account/account_auth_provider.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/application/workout_health_export_controller.dart';
import 'package:beyondrep/features/health/data/health_export_repository.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/data/health_workout_writer.dart';
import 'package:beyondrep/features/watch/application/watch_status_provider.dart';
import 'package:beyondrep/features/watch/domain/watch_status.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_account_auth.dart';
import '../support/fake_health_reader.dart';
import '../support/fake_health_workout_writer.dart';

final _now = DateTime.utc(2026, 11, 27, 12);

void main() {
  late Directory dir;
  late Store store;
  late FakeAuthApi api;
  late AccountAuthController auth;
  late FakeHealthWorkoutWriter writer;
  late FakeHealthReader reader;
  late WatchStatus watch;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('beyondrep-hexport-ctl-');
    store = Store(getObjectBoxModel(), directory: dir.path);
    api = FakeAuthApi()..sessionId = accountA;
    auth = controller(api, FakeBoundAccountStore()..saved = accountA);
    await auth.restore();
    writer = FakeHealthWorkoutWriter();
    reader = FakeHealthReader();
    watch = const WatchHidden();
  });
  tearDown(() async {
    auth.dispose();
    await api.dispose();
    store.close();
    dir.deleteSync(recursive: true);
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        accountAuthControllerProvider.overrideWithValue(auth),
        objectBoxStoreProvider.overrideWithValue(store),
        healthWorkoutWriterProvider.overrideWithValue(writer),
        healthReaderProvider.overrideWithValue(reader),
        healthClockProvider.overrideWithValue(() => _now),
        watchStatusProvider.overrideWith((ref) => watch),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  void addWorkout(int i) {
    final end = _now.subtract(Duration(days: i));
    store.box<WorkoutSessionEntity>().put(
      WorkoutSessionEntity(
        uuid: '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
        name: 'W$i',
        status: 'completed',
        startedAtMs: end
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch,
        completedAtMs: end.millisecondsSinceEpoch,
        originalOffsetMinutes: 0,
        updatedAtMs: 10,
      ),
    );
  }

  test('is Off by default', () async {
    final c = container();
    expect(
      await c.read(healthExportControllerProvider.future),
      isA<HealthExportOff>(),
    );
  });

  test('is Unavailable when the store is unavailable or signed out', () async {
    writer.available = false;
    expect(
      await container().read(healthExportControllerProvider.future),
      isA<HealthExportUnavailable>(),
    );
  });

  test(
    'turnOn requests access once, runs a pass and shows the saved count',
    () async {
      addWorkout(1);
      addWorkout(2);
      final c = container();
      await c.read(healthExportControllerProvider.future);
      await c.read(healthExportControllerProvider.notifier).turnOn();
      expect(writer.requestAccessCalls, 1);
      expect(writer.writes, hasLength(2));
      final status =
          c.read(healthExportControllerProvider).requireValue as HealthExportOn;
      expect((status.saved, status.waiting, status.needsAccess), (2, 0, false));
      expect(
        ObjectBoxHealthExportRepository(store).isEnabled(accountA),
        isTrue,
      );
    },
  );

  group('watch heart rate and calories on Android', () {
    HealthExportOn on(ProviderContainer c) =>
        c.read(healthExportControllerProvider).requireValue as HealthExportOn;

    setUp(() {
      writer = FakeHealthWorkoutWriter(isIos: false);
      ObjectBoxHealthExportRepository(store).enable(accountA, _now);
    });

    test(
      'is offered when a Wear watch is paired and the write is missing',
      () async {
        watch = const WatchWaiting();
        writer.watchHealthAccess = false;
        final c = container();
        await c.read(healthExportControllerProvider.future);
        expect(on(c).offersWatchHealthAccess, isTrue);
      },
    );

    test('is not offered without a watch, with access, or on iOS', () async {
      writer.watchHealthAccess = false;
      var c = container();
      await c.read(healthExportControllerProvider.future);
      expect(on(c).offersWatchHealthAccess, isFalse);

      watch = const WatchWaiting();
      writer.watchHealthAccess = true;
      c = container();
      await c.read(healthExportControllerProvider.future);
      expect(on(c).offersWatchHealthAccess, isFalse);

      writer = FakeHealthWorkoutWriter()..watchHealthAccess = false;
      c = container();
      await c.read(healthExportControllerProvider.future);
      expect(on(c).offersWatchHealthAccess, isFalse);
    });

    test('allowWatchHealth asks for heart rate and calories and clears the '
        'offer', () async {
      watch = const WatchWaiting();
      writer.watchHealthAccess = false;
      final c = container();
      await c.read(healthExportControllerProvider.future);
      await c.read(healthExportControllerProvider.notifier).allowWatchHealth();
      expect(writer.watchHealthRequests, 1);
      expect(on(c).offersWatchHealthAccess, isFalse);
    });
  });

  test('turnOff stops later passes writing', () async {
    final c = container();
    await c.read(healthExportControllerProvider.future);
    final n = c.read(healthExportControllerProvider.notifier);
    await n.turnOn();
    await n.turnOff();
    expect(
      c.read(healthExportControllerProvider).requireValue,
      isA<HealthExportOff>(),
    );
    addWorkout(1);
    await n.runPass();
    expect(writer.writes, isEmpty);
    expect(
      c.read(healthExportControllerProvider).requireValue,
      isA<HealthExportOff>(),
    );
  });

  test(
    'turning off and on while a pass awaits a write saves the workout once',
    () async {
      addWorkout(1);
      final gate = Completer<void>();
      writer.writeGate = gate.future;
      final c = container();
      await c.read(healthExportControllerProvider.future);
      final n = c.read(healthExportControllerProvider.notifier);
      final first = n.turnOn();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(writer.writes, hasLength(1));
      await n.turnOff();
      final second = n.turnOn();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      gate.complete();
      await Future.wait([first, second]);
      expect(writer.writes, hasLength(1));
      final status =
          c.read(healthExportControllerProvider).requireValue as HealthExportOn;
      expect(status.saved, 1);
    },
  );

  test(
    'needsAccess is true after a denied pass and clears once access is granted',
    () async {
      addWorkout(1);
      writer
        ..writeAccess = false
        ..accessGrantedByRequest = false;
      final c = container();
      await c.read(healthExportControllerProvider.future);
      final n = c.read(healthExportControllerProvider.notifier);
      await n.turnOn();
      var status =
          c.read(healthExportControllerProvider).requireValue as HealthExportOn;
      expect(status.needsAccess, isTrue);
      expect(status.waiting, 1);
      writer.writeAccess = true;
      await n.runPass();
      status =
          c.read(healthExportControllerProvider).requireValue as HealthExportOn;
      expect((status.saved, status.needsAccess), (1, false));
    },
  );

  test('an already enabled account shows its saved count on build', () async {
    addWorkout(1);
    final c1 = container();
    await c1.read(healthExportControllerProvider.future);
    await c1.read(healthExportControllerProvider.notifier).turnOn();
    final c2 = container();
    final status =
        await c2.read(healthExportControllerProvider.future) as HealthExportOn;
    expect(status.saved, 1);
  });

  test('openSettings opens the health settings', () async {
    final c = container();
    await c.read(healthExportControllerProvider.future);
    await c.read(healthExportControllerProvider.notifier).openSettings();
    expect(reader.openSettingsCalls, 1);
  });

  test('a paired watch delays a fresh workout', () async {
    watch = const WatchWaiting();
    final end = _now.subtract(const Duration(minutes: 2));
    store.box<WorkoutSessionEntity>().put(
      WorkoutSessionEntity(
        uuid: '00000000-0000-4000-8000-0000000000aa',
        name: 'Fresh',
        status: 'completed',
        startedAtMs: end
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch,
        completedAtMs: end.millisecondsSinceEpoch,
        originalOffsetMinutes: 0,
        updatedAtMs: 10,
      ),
    );
    final c = container();
    await c.read(healthExportControllerProvider.future);
    await c.read(healthExportControllerProvider.notifier).turnOn();
    expect(writer.writes, isEmpty);
  });

  test('the kick provider runs a pass for an enabled account', () async {
    addWorkout(1);
    ObjectBoxHealthExportRepository(store).enable(accountA, _now);
    final c = container();
    await c.read(healthExportControllerProvider.future);
    c.read(healthExportKickProvider)();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(writer.writes, hasLength(1));
  });
}
