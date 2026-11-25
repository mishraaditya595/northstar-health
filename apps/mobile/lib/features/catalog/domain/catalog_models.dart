class CatalogFormatException implements Exception {
  const CatalogFormatException(this.code);

  /// One of `checksum`, `schema`, `shape`, `duplicateId`, `reference`,
  /// `range`, `mode`. Never carries content from the snapshot.
  final String code;

  @override
  String toString() => 'CatalogFormatException($code)';
}

class CatalogExercise {
  const CatalogExercise({
    required this.id,
    required this.name,
    required this.aliases,
    required this.muscleGroup,
    required this.primaryMuscles,
    required this.secondaryMuscles,
    required this.equipment,
    required this.category,
    required this.mode,
    required this.cues,
    required this.retired,
  });

  final String id;
  final String name;
  final List<String> aliases;
  final String muscleGroup;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final List<String> equipment;
  final String category;
  final String mode;
  final List<String> cues;
  final bool retired;
}

class CatalogSnapshot {
  const CatalogSnapshot({
    required this.release,
    required this.schemaVersion,
    required this.minAppCatalogSchema,
    required this.publishedAt,
    required this.sha256,
    required this.exercises,
    required this.templates,
    required this.programs,
  });

  final int release;
  final int schemaVersion;
  final int minAppCatalogSchema;
  final String publishedAt;

  /// SHA-256 of the canonical snapshot bytes (computed, not read from JSON).
  final String sha256;
  final List<CatalogExercise> exercises;
  final List<Map<String, Object?>> templates;
  final List<Map<String, Object?>> programs;

  Iterable<CatalogExercise> get activeExercises =>
      exercises.where((exercise) => !exercise.retired);
}

class CatalogManifest {
  const CatalogManifest({
    required this.release,
    required this.schemaVersion,
    required this.minAppCatalogSchema,
    required this.publishedAt,
    required this.sha256,
    required this.sizeBytes,
  });

  final int release;
  final int schemaVersion;
  final int minAppCatalogSchema;
  final String publishedAt;
  final String sha256;
  final int sizeBytes;
}
