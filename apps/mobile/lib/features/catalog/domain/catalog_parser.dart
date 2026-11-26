import 'canonical_json.dart';
import 'catalog_models.dart';

const supportedCatalogSchema = 1;

const _modes = {'reps_load', 'reps', 'duration', 'duration_load'};
const _durationModes = {'duration', 'duration_load'};

// The closed vocabularies and limits of catalog/schema/catalog.schema.json.
const _muscles = {
  'chest', 'shoulders', 'biceps', 'forearms', 'abs', 'obliques', 'quads', //
  'calves', 'traps', 'lats', 'lowerBack', 'triceps', 'glutes', 'hamstrings',
};
const _muscleGroups = {'Chest', 'Back', 'Legs', 'Shoulders', 'Arms', 'Core'};
const _equipment = {
  'barbell', 'dumbbell', 'kettlebell', 'machine', 'cable', 'band', //
  'bodyweight', 'bench', 'pull_up_bar', 'ez_bar', 'trap_bar', 'plate', 'box',
  'rings', 'other',
};
const _categories = {
  'squat', 'hinge', 'lunge', 'push_horizontal', 'push_vertical', //
  'pull_horizontal', 'pull_vertical', 'carry', 'core', 'isolation', 'calf',
  'conditioning', 'mobility',
};
const _levels = {'beginner', 'intermediate', 'advanced'};
const _goals = {'strength', 'hypertrophy', 'general', 'endurance', 'fat_loss'};
final _exerciseId = RegExp(r'^builtin\.v1\.[a-z0-9]+(-[a-z0-9]+)*$');
final _templateId = RegExp(r'^tpl\.[a-z0-9]+(-[a-z0-9]+)*$');
final _programId = RegExp(r'^prog\.[a-z0-9]+(-[a-z0-9]+)*$');

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
  // Canonicalisation already bounded the depth; now reject any control
  // character or lone surrogate in a key or a value.
  _checkText(json);

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
    id: _id(map, _exerciseId),
    name: _text(map, 'name', min: 1, max: 80),
    aliases: _strings(map, 'aliases', maxItems: 10, min: 1, max: 60),
    muscleGroup: _oneOf(map, 'muscleGroup', _muscleGroups),
    primaryMuscles: _vocab(map, 'primaryMuscles', _muscles),
    secondaryMuscles: _vocab(map, 'secondaryMuscles', _muscles),
    equipment: _vocab(map, 'equipment', _equipment),
    category: _oneOf(map, 'category', _categories),
    mode: mode,
    cues: _strings(map, 'cues', maxItems: 6, min: 1, max: 160),
    retired: status == 'retired',
  );
}

/// Optional `status` on templates and programs: missing or `active` is
/// active. `retired`, and any value this build does not know, count as retired
/// (not browsable): a future status must hide one item, not reject the whole
/// snapshot. Exercises keep their strict check.
bool _retired(Map<String, Object?> map) {
  final status = map['status'];
  return status != null && status != 'active';
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
    id: _id(map, _templateId),
    name: _text(map, 'name', min: 1, max: 80),
    description: _text(map, 'description', max: 1000),
    goals: _vocab(tags, 'goal', _goals),
    level: _oneOf(tags, 'level', _levels),
    equipment: _vocab(tags, 'equipment', _equipment),
    estimatedMinutes: _int(map, 'estimatedMinutes'),
    standalone: standalone as bool? ?? true,
    retired: _retired(map),
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
    id: _id(map, _programId),
    name: _text(map, 'name', min: 1, max: 80),
    description: _text(map, 'description', max: 1000),
    goals: _vocab(map, 'goals', _goals),
    level: _oneOf(map, 'level', _levels),
    daysPerWeek: daysPerWeek,
    estimatedMinutes: _int(map, 'estimatedMinutes'),
    equipment: _vocab(map, 'equipment', _equipment),
    retired: _retired(map),
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
  if (note != null) {
    if (note is! String) throw const CatalogFormatException('shape');
    if (note.runes.length > 300) throw const CatalogFormatException('range');
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

List<String> _strings(
  Map<String, Object?> map,
  String key, {
  int? maxItems,
  int min = 0,
  int? max,
}) {
  final values = _list(map, key);
  if (values.any((value) => value is! String)) {
    throw const CatalogFormatException('shape');
  }
  if (maxItems != null && values.length > maxItems) {
    throw const CatalogFormatException('range');
  }
  for (final value in values.cast<String>()) {
    _checkLength(value, min, max);
  }
  return List.unmodifiable(values.cast<String>());
}

void _checkLength(String value, int min, int? max) {
  final length = value.runes.length;
  if (length < min || (max != null && length > max)) {
    throw const CatalogFormatException('range');
  }
}

/// A string within the schema's length limits (in code points).
String _text(Map<String, Object?> map, String key, {int min = 0, int? max}) {
  final value = _string(map, key);
  _checkLength(value, min, max);
  return value;
}

String _id(Map<String, Object?> map, RegExp pattern) {
  final value = _text(map, 'id', min: 1, max: 120);
  if (!pattern.hasMatch(value)) throw const CatalogFormatException('shape');
  return value;
}

String _oneOf(Map<String, Object?> map, String key, Set<String> allowed) {
  final value = _string(map, key);
  if (!allowed.contains(value)) throw const CatalogFormatException('shape');
  return value;
}

List<String> _vocab(Map<String, Object?> map, String key, Set<String> allowed) {
  final values = _strings(map, key);
  if (values.any((value) => !allowed.contains(value))) {
    throw const CatalogFormatException('shape');
  }
  return values;
}

/// Rejects ASCII control characters (U+0000-U+001F, U+007F) and unpaired
/// surrogates in every key and string, like the publisher's validator.
void _checkText(Object? node) {
  if (node is String) {
    _checkString(node);
  } else if (node is List) {
    node.forEach(_checkText);
  } else if (node is Map) {
    for (final entry in node.entries) {
      _checkText(entry.key);
      _checkText(entry.value);
    }
  }
}

void _checkString(String value) {
  final units = value.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit < 0x20 || unit == 0x7f) {
      throw const CatalogFormatException('shape');
    }
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (i + 1 < units.length &&
          units[i + 1] >= 0xDC00 &&
          units[i + 1] <= 0xDFFF) {
        i++;
        continue;
      }
      throw const CatalogFormatException('shape');
    }
    if (unit >= 0xDC00 && unit <= 0xDFFF) {
      throw const CatalogFormatException('shape');
    }
  }
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
