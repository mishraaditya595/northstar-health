import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ids/uuid_factory.dart';
import '../../../core/storage/objectbox_store_provider.dart';
import '../../../objectbox.g.dart';
import '../../catalog/domain/catalog_models.dart';
import '../../workouts/data/objectbox_workout_library_repository.dart';
import '../../workouts/data/workout_entities.dart';
import '../../workouts/domain/workout_library_models.dart';
import '../domain/program_models.dart';
import '../domain/program_repository.dart';
import '../domain/program_schedule.dart';

final programRepositoryProvider = Provider<ProgramRepository>((ref) {
  return ObjectBoxProgramRepository(ref.watch(objectBoxStoreProvider));
});

class ObjectBoxProgramRepository implements ProgramRepository {
  ObjectBoxProgramRepository(this._store, {UuidFactory? uuidFactory})
    : _ids = uuidFactory ?? SecureUuidFactory(),
      _library = ObjectBoxWorkoutLibraryRepository(
        _store,
        uuidFactory: uuidFactory,
      ),
      _programs = _store.box<TrainingProgramEntity>(),
      _days = _store.box<ProgramDayEntity>(),
      _plans = _store.box<WorkoutPlanEntity>(),
      _items = _store.box<PlanExerciseEntity>();

  final Store _store;
  final UuidFactory _ids;
  final ObjectBoxWorkoutLibraryRepository _library;
  final Box<TrainingProgramEntity> _programs;
  final Box<ProgramDayEntity> _days;
  final Box<WorkoutPlanEntity> _plans;
  final Box<PlanExerciseEntity> _items;

  /// Called after each import step: `exercises`, `plans`, `rows`, `program`,
  /// `days`. A throw rolls the whole import back.
  @visibleForTesting
  void Function(String step)? debugImportHook;

  TrainingProgramEntity? _byUuid(String uuid) {
    final query = _programs
        .query(TrainingProgramEntity_.uuid.equals(uuid))
        .build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  List<ProgramDayEntity> _daysOf(String programUuid) {
    final query = _days
        .query(ProgramDayEntity_.programUuid.equals(programUuid))
        .build();
    try {
      return query.find()..sort((a, b) => a.dayIndex.compareTo(b.dayIndex));
    } finally {
      query.close();
    }
  }

  List<WorkoutPlanEntity> _plansOf(String programUuid) {
    final query = _plans
        .query(WorkoutPlanEntity_.programUuid.equals(programUuid))
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  TrainingProgramRecord _record(TrainingProgramEntity p) =>
      TrainingProgramRecord(
        uuid: p.uuid,
        name: p.name,
        description: p.description,
        sourceId: p.sourceId,
        sourceRelease: p.sourceRelease,
        firstDayWeekday: p.firstDayWeekday,
        isActive: p.isActive,
        activatedLocalDate: p.activatedLocalDate,
        updatedAtMs: p.updatedAtMs,
        archivedAtMs: p.archivedAtMs,
        days: List.unmodifiable([
          for (final d in _daysOf(p.uuid))
            ProgramDayRecord(
              uuid: d.uuid,
              dayIndex: d.dayIndex,
              planUuid: d.planUuid,
            ),
        ]),
      );

  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  TrainingProgramEntity _live(String programUuid) {
    final program = _byUuid(programUuid);
    if (program == null || program.archivedAtMs != null) {
      throw StateError('Unknown or archived program');
    }
    return program;
  }

  @override
  TrainingProgramRecord importProgram({
    required String requestUuid,
    required CatalogProgram program,
    required Map<String, List<TemplateRowInput>> templateRows,
    required Map<String, String> templateNames,
    required int release,
    required int firstDayWeekday,
    required bool makeActive,
    required DateTime localToday,
  }) {
    final label = program.name.trim();
    if (requestUuid.isEmpty ||
        label.isEmpty ||
        label.length > 100 ||
        program.week.length != 7 ||
        firstDayWeekday < 1 ||
        firstDayWeekday > 7) {
      throw ArgumentError('Invalid program import');
    }
    final templateIds = <String>{
      for (final id in program.week)
        ?id,
    }.toList();
    final items = <String, List<PlanExerciseRecord>>{};
    for (final id in templateIds) {
      final rows = templateRows[id];
      final name = templateNames[id]?.trim();
      if (rows == null ||
          rows.isEmpty ||
          rows.length > 100 ||
          name == null ||
          name.isEmpty ||
          name.length > 100) {
        throw ArgumentError('Program template is missing');
      }
      items[id] = _library.planItemsFromRows(rows);
    }
    return _store.runInTransaction(TxMode.write, () {
      final existing = _byUuid(requestUuid);
      if (existing != null) return _record(existing);
      for (final id in templateIds) {
        for (final row in templateRows[id]!) {
          _library.materializeInTransaction(row.exercise, release);
        }
      }
      debugImportHook?.call('exercises');
      final now = _now();
      final planUuids = {for (final id in templateIds) id: _ids.newId()};
      for (final id in templateIds) {
        _plans.put(
          WorkoutPlanEntity(
            uuid: planUuids[id]!,
            name: templateNames[id]!.trim(),
            createdAtMs: now,
            updatedAtMs: now,
            programUuid: requestUuid,
          ),
        );
      }
      debugImportHook?.call('plans');
      for (final id in templateIds) {
        for (final item in items[id]!) {
          _items.put(
            PlanExerciseEntity(
              uuid: item.uuid,
              planUuid: planUuids[id]!,
              exerciseUuid: item.exerciseUuid,
              position: item.position,
              targetSets: item.targetSets,
              targetRepsMin: item.targetRepsMin,
              targetRepsMax: item.targetRepsMax,
              targetDurationSeconds: item.targetDurationSeconds,
              restSeconds: item.restSeconds,
              notes: item.notes.trim(),
            ),
          );
        }
      }
      debugImportHook?.call('rows');
      final taken = {
        for (final p in _programs.getAll())
          if (p.archivedAtMs == null) p.name.trim().toLowerCase(),
      };
      var unique = label;
      for (var n = 2; taken.contains(unique.toLowerCase()); n++) {
        final suffix = ' ($n)';
        final room = 100 - suffix.length;
        unique =
            '${label.length > room ? label.substring(0, room).trimRight() : label}$suffix';
      }
      if (makeActive) _deactivateAll(now);
      final entity = TrainingProgramEntity(
        uuid: requestUuid,
        name: unique,
        description: program.description,
        sourceId: program.id,
        sourceRelease: release,
        firstDayWeekday: firstDayWeekday,
        isActive: makeActive,
        activatedLocalDate: makeActive ? localDateKey(localToday) : null,
        createdAtMs: now,
        updatedAtMs: now,
      );
      _programs.put(entity);
      debugImportHook?.call('program');
      for (var i = 0; i < 7; i++) {
        final id = program.week[i];
        _days.put(
          ProgramDayEntity(
            uuid: _ids.newId(),
            programUuid: requestUuid,
            dayIndex: i,
            planUuid: id == null ? null : planUuids[id],
          ),
        );
      }
      debugImportHook?.call('days');
      return _record(entity);
    });
  }

  void _deactivateAll(int now, {String? except}) {
    for (final other in _programs.getAll()) {
      if (other.isActive && other.uuid != except) {
        other.isActive = false;
        other.updatedAtMs = now;
        _programs.put(other);
      }
    }
  }

  @override
  void setActive(String programUuid, bool active, DateTime localToday) {
    _store.runInTransaction(TxMode.write, () {
      final program = _live(programUuid);
      final now = _now();
      if (active) {
        _deactivateAll(now, except: programUuid);
        program.activatedLocalDate = localDateKey(localToday);
      }
      program.isActive = active;
      program.updatedAtMs = now;
      _programs.put(program);
    });
  }

  @override
  void setFirstWeekday(String programUuid, int weekday) {
    if (weekday < 1 || weekday > 7) throw ArgumentError('Invalid weekday');
    _store.runInTransaction(TxMode.write, () {
      final program = _live(programUuid);
      program.firstDayWeekday = weekday;
      program.updatedAtMs = _now();
      _programs.put(program);
    });
  }

  @override
  void setDayPlan(String programUuid, int dayIndex, String? planUuid) {
    if (dayIndex < 0 || dayIndex > 6) throw ArgumentError('Invalid day');
    _store.runInTransaction(TxMode.write, () {
      final program = _live(programUuid);
      if (planUuid != null &&
          !_plansOf(
            programUuid,
          ).any((plan) => plan.uuid == planUuid && plan.archivedAtMs == null)) {
        throw ArgumentError('Plan does not belong to this program');
      }
      final day = _daysOf(programUuid)
          .firstWhere((d) => d.dayIndex == dayIndex);
      day.planUuid = planUuid;
      _days.put(day);
      program.updatedAtMs = _now();
      _programs.put(program);
    });
  }

  @override
  void archiveProgram(String programUuid, int nowMs) {
    _store.runInTransaction(TxMode.write, () {
      final program = _byUuid(programUuid);
      if (program == null) throw StateError('Unknown program');
      if (program.archivedAtMs != null) return;
      for (final plan in _plansOf(programUuid)) {
        plan.archivedAtMs ??= nowMs;
        _plans.put(plan);
      }
      program
        ..archivedAtMs = nowMs
        ..isActive = false
        ..updatedAtMs = nowMs;
      _programs.put(program);
    });
  }

  @override
  TrainingProgramRecord? getProgram(String programUuid) {
    return _store.runInTransaction(TxMode.read, () {
      final program = _byUuid(programUuid);
      return program == null ? null : _record(program);
    });
  }

  List<TrainingProgramRecord> _listLive() {
    return _store.runInTransaction(TxMode.read, () {
      final list = _programs.getAll()
        ..removeWhere((p) => p.archivedAtMs != null)
        ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
      return list.map(_record).toList(growable: false);
    });
  }

  @override
  Stream<List<TrainingProgramRecord>> watchPrograms() {
    return _programs
        .query()
        .watch(triggerImmediately: true)
        .map((_) => _listLive());
  }

  @override
  TrainingProgramRecord? activeProgram() {
    return _store.runInTransaction(TxMode.read, () {
      for (final p in _programs.getAll()) {
        if (p.isActive && p.archivedAtMs == null) return _record(p);
      }
      return null;
    });
  }
}
