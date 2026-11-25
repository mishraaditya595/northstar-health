import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/catalog_models.dart';
import '../domain/catalog_templates.dart';
import 'catalog_providers.dart';
import 'exercise_choices_provider.dart';

/// Templates the phone can show and start: [browsableTemplates] of the cached
/// snapshot, or empty while there is none.
final templatesProvider = Provider<List<CatalogTemplate>>((ref) {
  final snapshot = safeCatalogState(() => ref.watch(catalogStateProvider))
      .snapshot;
  return snapshot == null ? const [] : browsableTemplates(snapshot);
});
