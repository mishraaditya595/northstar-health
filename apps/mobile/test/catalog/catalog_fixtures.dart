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
}) => CatalogManifest(
  release: json['release']! as int,
  schemaVersion: json['schemaVersion']! as int,
  minAppCatalogSchema:
      minAppCatalogSchema ?? json['minAppCatalogSchema']! as int,
  publishedAt: json['publishedAt']! as String,
  sha256: sha256 ?? sha256Hex(canonicalJsonBytes(json)),
  sizeBytes: 1,
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
