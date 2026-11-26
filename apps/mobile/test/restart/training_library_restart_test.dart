import 'dart:convert';
import 'dart:io';

import 'package:beyondrep/core/ids/uuid_factory.dart';
import 'package:beyondrep/core/storage/account_store.dart';
import 'package:beyondrep/features/catalog/data/catalog_file_store.dart';
import 'package:beyondrep/features/catalog/data/catalog_repository.dart';
import 'package:beyondrep/features/catalog/domain/canonical_json.dart';
import 'package:beyondrep/features/catalog/domain/catalog_models.dart';
import 'package:beyondrep/features/catalog/domain/catalog_parser.dart';
import 'package:beyondrep/features/programs/data/objectbox_program_repository.dart';
import 'package:beyondrep/features/programs/domain/program_models.dart';
import 'package:beyondrep/features/programs/domain/program_schedule.dart';
import 'package:beyondrep/features/programs/domain/program_status.dart';
import 'package:beyondrep/features/train/active_workout_state.dart';
import 'package:beyondrep/features/workouts/data/objectbox_live_workout_engine.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_library_repository.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_repository.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/catalog_fixtures.dart';
import '../programs/objectbox_program_repository_test.dart'
    show catalogProgram, row;

/// Restart and process-death cases for the training library, each with a real
/// ObjectBox store that is closed and reopened. A closed store stands in for a
/// killed process: ObjectBox keeps only committed transactions.
void main() {
  late Directory root;
  late Directory dbDir;
  late Store store;

  Store reopen() {
    store.close();
    return store = Store(getObjectBoxModel(), directory: dbDir.path);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('beyondrep-restart-');
    dbDir = Directory('${root.path}/db')..createSync();
    store = Store(getObjectBoxModel(), directory: dbDir.path);
  });

  tearDown(() {
    store.close();
    root.deleteSync(recursive: true);
  });

  final week = <String?>['tpl.a', 'tpl.b', null, 'tpl.a', null, null, null];

  TrainingProgramRecord importProgram(
    Store target,
    String request, {
    void Function(String)? hook,
    bool makeActive = true,
  }) {
    final programs = ObjectBoxProgramRepository(target)..debugImportHook = hook;
    return programs.importProgram(
      requestUuid: request,
      program: catalogProgram('prog.synthetic', week),
      templateRows: {
        'tpl.a': [row('builtin.v1.synthetic-press')],
        'tpl.b': [row('builtin.v1.synthetic-row')],
      },
      templateNames: const {'tpl.a': 'Day A', 'tpl.b': 'Day B'},
      release: 4,
      firstDayWeekday: 1,
      makeActive: makeActive,
      localToday: DateTime(2026, 11, 23),
    );
  }

  RepositoryWorkoutActions actionsFor(Store target, DateTime now) =>
      RepositoryWorkoutActions(
        ObjectBoxLiveWorkoutEngine(target),
        ObjectBoxWorkoutRepository(target),
        ObjectBoxWorkoutLibraryRepository(target),
        SecureUuidFactory(),
        programs: ObjectBoxProgramRepository(target),
        clock: () => now,
      );

  group('1 and 2: a program day survives a restart', () {
    test('today: both fields persist and finishing marks the day done', () {
      final program = importProgram(store, 'prog-1');
      // Monday A, Tuesday B, Wednesday rest: train on Tuesday.
      final tuesday = DateTime(2026, 11, 24, 10);
      final planUuid = dayFor(program, tuesday).planUuid!;
      final started = actionsFor(
        store,
        tuesday,
      ).startProgramDay(program, expectedPlanUuid: planUuid);
      expect(started.programDayLocalDate, '2026-11-24');

      reopen();

      final engine = ObjectBoxLiveWorkoutEngine(store);
      final recovered = engine.recoverActiveWorkout()!;
      expect(recovered.uuid, started.uuid);
      expect(recovered.programUuid, program.uuid);
      expect(recovered.programDayLocalDate, '2026-11-24');
      engine.finishWorkout(
        recovered.uuid,
        expectedRevision: recovered.revision,
        finishedAtUtc: tuesday.toUtc(),
      );
      final fresh = ObjectBoxProgramRepository(store).getProgram(program.uuid)!;
      final rows = programWeekStatus(
        program: fresh,
        localToday: tuesday,
        sessions: ObjectBoxWorkoutRepository(store)
            .listProgramSessions(program.uuid),
        availablePlanUuids: {
          for (final d in fresh.days)
            if (d.planUuid != null) d.planUuid!,
        },
      );
      expect(rows[1].status, ProgramDayStatus.done);
    });

    test('a missed day keeps the missed date, not today', () {
      final program = importProgram(store, 'prog-1');
      final thursday = DateTime(2026, 11, 26, 18, 30);
      // Activated Monday: Monday (A) is missed by Thursday.
      final started = actionsFor(store, thursday).startProgramDay(
        program,
        expectedPlanUuid: dayFor(program, DateTime(2026, 11, 23)).planUuid,
        missedDate: DateTime(2026, 11, 23),
      );
      expect(started.programDayLocalDate, '2026-11-23');

      reopen();

      final recovered = ObjectBoxLiveWorkoutEngine(store)
          .recoverActiveWorkout()!;
      expect(recovered.programDayLocalDate, '2026-11-23');
      expect(recovered.programUuid, program.uuid);
    });
  });

  group('3: an interrupted program import', () {
    for (final step in ['exercises', 'plans', 'rows', 'program', 'days']) {
      test('stopped after "$step": nothing after reopen, one after retry', () {
        expect(
          () => importProgram(
            store,
            'prog-1',
            hook: (s) {
              if (s == step) throw StateError('killed');
            },
          ),
          throwsStateError,
        );
        reopen();
        expect(store.box<TrainingProgramEntity>().count(), 0);
        expect(store.box<ProgramDayEntity>().count(), 0);
        expect(store.box<WorkoutPlanEntity>().count(), 0);
        expect(store.box<PlanExerciseEntity>().count(), 0);
        expect(store.box<ExerciseDefinitionEntity>().count(), 0);

        importProgram(store, 'prog-1');
        // The same request after another restart is a replay, not a copy.
        reopen();
        importProgram(store, 'prog-1');
        expect(store.box<TrainingProgramEntity>().count(), 1);
        expect(store.box<WorkoutPlanEntity>().count(), 2);
      });
    }

    test('killed after commit: the retry returns the same program', () {
      final first = importProgram(store, 'prog-1');
      reopen();
      final again = importProgram(store, 'prog-1');
      expect(again.uuid, first.uuid);
      expect(store.box<TrainingProgramEntity>().count(), 1);
    });
  });

  group('4: copying a template to My Plans', () {
    ObjectBoxWorkoutLibraryRepository library() =>
        ObjectBoxWorkoutLibraryRepository(store);

    copy(String request, {void Function(String)? hook}) {
      final repo = library()..debugCopyHook = hook;
      return repo.copyCatalogTemplate(
        requestUuid: request,
        name: 'Push day',
        description: 'Synthetic description.',
        rows: [row('builtin.v1.synthetic-press')],
        release: 4,
      );
    }

    for (final step in ['exercises', 'plan', 'rows']) {
      test('stopped after "$step": no plan after reopen, one after retry', () {
        expect(
          () => copy(
            'req-1',
            hook: (s) {
              if (s == step) throw StateError('killed');
            },
          ),
          throwsStateError,
        );
        reopen();
        expect(store.box<WorkoutPlanEntity>().count(), 0);
        expect(store.box<PlanExerciseEntity>().count(), 0);

        copy('req-1');
        reopen();
        copy('req-1');
        expect(store.box<WorkoutPlanEntity>().count(), 1);
        expect(store.box<PlanExerciseEntity>().count(), 1);
      });
    }

    test('killed after commit: the same request id gives the one plan', () {
      copy('req-1');
      reopen();
      expect(copy('req-1').uuid, 'req-1');
      expect(store.box<WorkoutPlanEntity>().count(), 1);
    });
  });

  group('5: catalogue cache on launch', () {
    late Directory cache;
    final r1 = snapshotJson();

    Future<CatalogSnapshot?> parse(String text) async {
      try {
        return parseCatalogSnapshot(jsonDecode(text));
      } on Object {
        return null;
      }
    }

    CatalogRepository offline() => CatalogRepository(
      transport: FakeCatalogTransport(
        manifest: () async => throw const SocketException('offline'),
        snapshot: (_) async => throw const SocketException('offline'),
      ),
      store: CatalogFileStore(cache),
      clock: () => DateTime.utc(2026, 11, 26, 12),
      parseInBackground: parse,
    );

    setUp(() {
      cache = Directory('${root.path}/cache');
    });

    Future<void> seedGood() async {
      final seed = CatalogFileStore(cache);
      await seed.prepare();
      await seed.writeSnapshotText(utf8.decode(canonicalJsonBytes(r1)));
      await seed.writeLastCheckedAtMs(1);
    }

    test('a stale snapshot.json.tmp and a corrupt meta.json: the last good '
        'snapshot loads', () async {
      await seedGood();
      File('${cache.path}/snapshot.json.tmp').writeAsStringSync('{"release"');
      File('${cache.path}/meta.json').writeAsStringSync('{not json');
      // A killed write leaves a temp file with the store's real pattern.
      File('${cache.path}/snapshot.json.killed.tmp')
        ..writeAsStringSync('{"release"')
        ..setLastModifiedSync(
          DateTime.now().subtract(const Duration(minutes: 11)),
        );
      final repository = offline();
      await repository.load();
      expect(
        File('${cache.path}/snapshot.json.killed.tmp').existsSync(),
        isFalse,
      );
      expect(repository.state.status, CatalogStatus.ready);
      expect(repository.state.snapshot?.release, 1);
      // An offline refresh on top of it does not throw or drop the cache.
      await repository.refresh(force: true);
      expect(repository.state.snapshot?.release, 1);
    });

    test(
      'a corrupt meta.json and no snapshot: the empty state, no crash',
      () async {
        cache.createSync(recursive: true);
        File('${cache.path}/meta.json').writeAsStringSync('\u0000\u0000');
        File('${cache.path}/snapshot.json.tmp').writeAsStringSync('partial');
        final repository = offline();
        await repository.load();
        expect(repository.state.status, CatalogStatus.unavailable);
        expect(repository.state.snapshot, isNull);
        await repository.refresh(force: true);
        expect(repository.state.snapshot, isNull);
      },
    );
  });

  group('6: account switch after a restart', () {
    const accountA = '11111111-1111-4111-8111-111111111111';
    const accountB = '22222222-2222-4222-8222-222222222222';

    Directory dirFor(String id) => Directory(
      '${root.path}/${accountStoreRelativePath(id, projectHost: 'example.test')}',
    )..createSync(recursive: true);

    test('B sees none of A\'s programs, sessions or week; the catalogue cache '
        'is shared', () async {
      final dirA = dirFor(accountA);
      final dirB = dirFor(accountB);
      var a = Store(getObjectBoxModel(), directory: dirA.path);
      var b = Store(getObjectBoxModel(), directory: dirB.path);
      final program = importProgram(a, 'prog-1');
      final tuesday = DateTime(2026, 11, 24, 10);
      actionsFor(a, tuesday).startProgramDay(
        program,
        expectedPlanUuid: dayFor(program, tuesday).planUuid,
      );
      importProgram(b, 'prog-b', makeActive: false);

      // Restart: close both and open them again, in the other order.
      a.close();
      b.close();
      b = Store(getObjectBoxModel(), directory: dirB.path);
      a = Store(getObjectBoxModel(), directory: dirA.path);
      addTearDown(() {
        a.close();
        b.close();
      });

      final programsB = ObjectBoxProgramRepository(b);
      expect(programsB.getProgram(program.uuid), isNull);
      expect(b.box<WorkoutSessionEntity>().count(), 0);
      expect(ObjectBoxLiveWorkoutEngine(b).recoverActiveWorkout(), isNull);
      expect(
        ObjectBoxWorkoutRepository(b).listProgramSessions(program.uuid),
        isEmpty,
      );
      expect(a.box<WorkoutSessionEntity>().count(), 1);
      expect(
        ObjectBoxLiveWorkoutEngine(a).recoverActiveWorkout()?.programUuid,
        program.uuid,
      );

      // One catalogue cache per host serves both accounts.
      final cache = Directory('${root.path}/catalog')..createSync();
      final seed = CatalogFileStore(cache);
      await seed.prepare();
      await seed.writeSnapshotText(
        utf8.decode(canonicalJsonBytes(snapshotJson())),
      );
      for (final _ in [accountA, accountB]) {
        final repository = CatalogRepository(
          transport: FakeCatalogTransport(
            manifest: () async => throw const SocketException('offline'),
          ),
          store: CatalogFileStore(cache),
          clock: () => DateTime.utc(2026, 11, 26, 12),
          parseInBackground: (text) async =>
              parseCatalogSnapshot(jsonDecode(text)),
        );
        await repository.load();
        expect(repository.state.status, CatalogStatus.ready);
      }
    });
  });
}
