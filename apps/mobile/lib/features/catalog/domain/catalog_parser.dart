import 'canonical_json.dart';
import 'catalog_models.dart';

const supportedCatalogSchema = 1;

const _modes = {'reps_load', 'reps', 'duration', 'duration_load'};
const _durationModes = {'duration', 'duration_load'};

CatalogSnapshot parseCatalogSnapshot(Object? json, {String? expectedSha256}) {
  final root = _map(json);
  final List<int> bytes;
  try {
    bytes = canonicalJsonBytes(json);
  } on ArgumentError {
    throw const CatalogFormatException('shape');
  }
  final digest = sha256Hex(bytes);
  if (expectedSha256 != null && expectedSha256 != digest) {
    throw const CatalogFormatException('checksum');
  }

  final schemaVersion = _int(root, 'schemaVersion');
  final minAppCatalogSchema = _int(root, 'minAppCatalogSchema');
  // minAppCatalogSchema is the only compatibility gate (spec 4.5): publishers
  // raise it for breaking changes. Unknown keys are ignored at every level.
  if (minAppCatalogSchema > supportedCatalogSchema) {
    throw const CatalogFormatException('schema');
  }
  final release = _int(root, 'release');
  final publishedAt = _string(root, 'publishedAt');

  final exercises = _list(root, 'exercises').map(_exercise).toList();
  final templateMaps = _list(root, 'templates').map(_map).toList();
  final programMaps = _list(root, 'programs').map(_map).toList();

  final ids = <String>{};
  void claim(String id) {
    if (!ids.add(id)) throw const CatalogFormatException('duplicateId');
  }

  for (final exercise in exercises) {
    claim(exercise.id);
  }
  for (final template in templateMaps) {
    claim(_string(template, 'id'));
  }
  for (final program in programMaps) {
    claim(_string(program, 'id'));
  }

  final byId = {for (final exercise in exercises) exercise.id: exercise};
  final templateIds = {
    for (final template in templateMaps) _string(template, 'id'),
  };
  final templates = [
    for (final template in templateMaps) _template(template, byId),
  ];
  final programs = [
    for (final program in programMaps) _program(program, templateIds),
  ];

  return CatalogSnapshot(
    release: release,
    schemaVersion: schemaVersion,
    minAppCatalogSchema: minAppCatalogSchema,
    publishedAt: publishedAt,
    sha256: digest,
    exercises: List.unmodifiable(exercises),
    templates: List.unmodifiable(templates),
    programs: List.unmodifiable(programs),
  );
}

CatalogManifest? parseCatalogManifest(Object? json) {
  if (json == null) return null;
  final map = _map(json);
  final sha = _string(map, 'sha256');
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
    throw const CatalogFormatException('shape');
  }
  _string(map, 'url');
  return CatalogManifest(
    release: _int(map, 'release'),
    schemaVersion: _int(map, 'schemaVersion'),
    minAppCatalogSchema: _int(map, 'minAppCatalogSchema'),
    publishedAt: _string(map, 'publishedAt'),
    sha256: sha,
    sizeBytes: _int(map, 'sizeBytes'),
  );
}

CatalogExercise _exercise(Object? value) {
  final map = _map(value);
  final mode = _string(map, 'mode');
  if (!_modes.contains(mode)) throw const CatalogFormatException('shape');
  final status = _string(map, 'status');
  if (status != 'active' && status != 'retired') {
    throw const CatalogFormatException('shape');
  }
  return CatalogExercise(
    id: _string(map, 'id'),
    name: _string(map, 'name'),
    aliases: _strings(map, 'aliases'),
    muscleGroup: _string(map, 'muscleGroup'),
    primaryMuscles: _strings(map, 'primaryMuscles'),
    secondaryMuscles: _strings(map, 'secondaryMuscles'),
    equipment: _strings(map, 'equipment'),
    category: _string(map, 'category'),
    mode: mode,
    cues: _strings(map, 'cues'),
    retired: status == 'retired',
  );
}

CatalogTemplate _template(
  Map<String, Object?> map,
  Map<String, CatalogExercise> exercises,
) {
  final tags = _map(map['tags']);
  final standalone = map['standalone'];
  if (standalone != null && standalone is! bool) {
    throw const CatalogFormatException('shape');
  }
  return CatalogTemplate(
    id: _string(map, 'id'),
    name: _string(map, 'name'),
    description: _string(map, 'description'),
    goals: _strings(tags, 'goal'),
    level: _string(tags, 'level'),
    equipment: _strings(tags, 'equipment'),
    estimatedMinutes: _int(map, 'estimatedMinutes'),
    standalone: standalone as bool? ?? true,
    exercises: List.unmodifiable([
      for (final item in _list(map, 'exercises'))
        _prescription(_map(item), exercises),
    ]),
  );
}

CatalogProgram _program(Map<String, Object?> map, Set<String> templateIds) {
  final week = _list(map, 'week');
  if (week.length != 7) throw const CatalogFormatException('range');
  for (final entry in week) {
    if (entry == null) continue;
    if (entry is! String) throw const CatalogFormatException('shape');
    if (!templateIds.contains(entry)) {
      throw const CatalogFormatException('reference');
    }
  }
  final trainingDays = week.where((entry) => entry != null).length;
  final daysPerWeek = _int(map, 'daysPerWeek');
  if (trainingDays == 0 || daysPerWeek != trainingDays) {
    throw const CatalogFormatException('range');
  }
  return CatalogProgram(
    id: _string(map, 'id'),
    name: _string(map, 'name'),
    description: _string(map, 'description'),
    goals: _strings(map, 'goals'),
    level: _string(map, 'level'),
    daysPerWeek: daysPerWeek,
    estimatedMinutes: _int(map, 'estimatedMinutes'),
    equipment: _strings(map, 'equipment'),
    week: List.unmodifiable(week.cast<String?>()),
  );
}

CatalogPrescription _prescription(
  Map<String, Object?> item,
  Map<String, CatalogExercise> exercises,
) {
  final exercise = exercises[_string(item, 'exerciseId')];
  if (exercise == null || exercise.retired) {
    throw const CatalogFormatException('reference');
  }
  final sets = _int(item, 'sets');
  final rest = _int(item, 'restSeconds');
  if (sets < 1 || sets > 30 || rest < 0 || rest > 3600) {
    throw const CatalogFormatException('range');
  }
  final hasReps = item.containsKey('repsMin') || item.containsKey('repsMax');
  final hasDuration = item.containsKey('durationSeconds');
  if (hasReps && hasDuration) throw const CatalogFormatException('mode');
  if (_durationModes.contains(exercise.mode)) {
    if (hasReps || !hasDuration) throw const CatalogFormatException('mode');
  } else if (hasDuration ||
      !(item.containsKey('repsMin') && item.containsKey('repsMax'))) {
    throw const CatalogFormatException('mode');
  }
  final note = item['note'];
  if (note != null && note is! String) {
    throw const CatalogFormatException('shape');
  }
  int? seconds;
  int? low;
  int? high;
  if (hasDuration) {
    seconds = _int(item, 'durationSeconds');
    if (seconds < 1 || seconds > 3600) {
      throw const CatalogFormatException('range');
    }
  } else {
    low = _int(item, 'repsMin');
    high = _int(item, 'repsMax');
    if (low < 1 || high > 1000 || low > high) {
      throw const CatalogFormatException('range');
    }
  }
  return CatalogPrescription(
    exerciseId: exercise.id,
    sets: sets,
    repsMin: low,
    repsMax: high,
    durationSeconds: seconds,
    restSeconds: rest,
    note: note as String? ?? '',
  );
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map) throw const CatalogFormatException('shape');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) throw const CatalogFormatException('shape');
    result[key] = entry.value;
  }
  return result;
}

List<Object?> _list(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! List) throw const CatalogFormatException('shape');
  return value;
}

List<String> _strings(Map<String, Object?> map, String key) {
  final values = _list(map, key);
  if (values.any((value) => value is! String)) {
    throw const CatalogFormatException('shape');
  }
  return List.unmodifiable(values.cast<String>());
}

int _int(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! int) throw const CatalogFormatException('shape');
  return value;
}

String _string(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) throw const CatalogFormatException('shape');
  return value;
}
