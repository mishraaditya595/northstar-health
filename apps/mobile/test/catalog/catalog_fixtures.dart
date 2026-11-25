import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:beyondrep/features/catalog/application/catalog_providers.dart';
import 'package:beyondrep/features/catalog/data/catalog_file_store.dart';
import 'package:beyondrep/features/catalog/data/catalog_repository.dart';
import 'package:beyondrep/features/catalog/data/catalog_transport.dart';
import 'package:beyondrep/features/catalog/domain/canonical_json.dart';
import 'package:beyondrep/features/catalog/domain/catalog_models.dart';

/// Synthetic catalogue content for tests; never real data.
Map<String, Object?> snapshotJson({
  int release = 1,
  int schemaVersion = 1,
  int minAppCatalogSchema = 1,
  List<String> ids = const ['builtin.v1.squat', 'builtin.v1.plank'],
}) => {
  'schemaVersion': schemaVersion,
  'minAppCatalogSchema': minAppCatalogSchema,
  'release': release,
  'publishedAt': '2026-11-26T00:00:00Z',
  'provenance': {'source': 's', 'license': 'MPL-2.0', 'attribution': ''},
  'exercises': [
    for (final id in ids)
      {
        'id': id,
        'name': 'Name of $id',
        'aliases': ['Alias of $id'],
        'muscleGroup': 'Legs',
        'primaryMuscles': ['quads'],
        'secondaryMuscles': ['glutes'],
        'equipment': ['barbell'],
        'category': 'squat',
        'mode': id.endsWith('plank') ? 'duration' : 'reps_load',
        'cues': ['Cue'],
        'status': 'active',
      },
  ],
  'templates': <Object?>[],
  'programs': <Object?>[],
};

CatalogManifest manifestFor(
  Map<String, Object?> json, {
  int? minAppCatalogSchema,
  String? sha256,
  int? sizeBytes,
}) => CatalogManifest(
  release: json['release']! as int,
  schemaVersion: json['schemaVersion']! as int,
  minAppCatalogSchema:
      minAppCatalogSchema ?? json['minAppCatalogSchema']! as int,
  publishedAt: json['publishedAt']! as String,
  sha256: sha256 ?? sha256Hex(canonicalJsonBytes(json)),
  sizeBytes: sizeBytes ?? canonicalJsonBytes(json).length,
);

class FakeCatalogTransport implements CatalogTransport {
  FakeCatalogTransport({this.manifest, this.snapshot});

  Future<CatalogManifest?> Function()? manifest;
  Future<Object?> Function(int release)? snapshot;
  int manifestCalls = 0;
  final snapshotRequests = <int>[];

  @override
  Future<CatalogManifest?> fetchManifest() {
    manifestCalls++;
    return manifest!();
  }

  @override
  Future<Object?> fetchSnapshot(int release) {
    snapshotRequests.add(release);
    return snapshot!(release);
  }
}

/// Reports a fixed state and records refresh calls; never touches disk or
/// network.
class StubCatalogRepository extends CatalogRepository {
  StubCatalogRepository(
    this.fixed,
    Directory directory, {
    this.outcome = CatalogRefreshOutcome.skippedFresh,
  }) : super(
         transport: FakeCatalogTransport(),
         store: CatalogFileStore(directory),
       );

  CatalogState fixed;
  CatalogRefreshOutcome outcome;
  final forceCalls = <bool>[];

  @override
  CatalogState get state => fixed;

  /// Simulates a refresh landing while a screen is open.
  void emit(CatalogState next) {
    fixed = next;
    notifyListeners();
  }

  @override
  Future<CatalogRefreshOutcome> refresh({bool force = false}) async {
    forceCalls.add(force);
    return outcome;
  }
}

/// For widget tests that open pickers without caring about the catalogue:
/// the catalogue is simply not downloaded.
List<Override> catalogTestOverrides({
  CatalogState state = const CatalogState(status: CatalogStatus.unavailable),
}) => [
  catalogRepositoryProvider.overrideWithValue(
    StubCatalogRepository(state, Directory.systemTemp),
  ),
];

CatalogExercise catalogExercise(
  String id,
  String name, {
  List<String> aliases = const [],
  String mode = 'reps_load',
  String category = 'hinge',
}) => CatalogExercise(
  id: id,
  name: name,
  aliases: aliases,
  muscleGroup: 'Legs',
  primaryMuscles: const ['glutes'],
  secondaryMuscles: const [],
  equipment: const ['barbell', 'bench'],
  category: category,
  mode: mode,
  cues: const [],
  retired: false,
);

CatalogSnapshot catalogSnapshotOf(
  List<CatalogExercise> exercises, {
  int release = 4,
}) => CatalogSnapshot(
  release: release,
  schemaVersion: 1,
  minAppCatalogSchema: 1,
  publishedAt: '2026-11-26T00:00:00Z',
  sha256: 'a' * 64,
  exercises: exercises,
  templates: const [],
  programs: const [],
);
