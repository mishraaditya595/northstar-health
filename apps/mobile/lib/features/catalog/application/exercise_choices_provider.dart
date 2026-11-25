import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../train/train_library_state.dart';
import '../data/catalog_repository.dart';
import '../domain/exercise_choices.dart';
import 'catalog_providers.dart';

/// The catalogue state, or "unavailable" when the catalogue layer itself
/// cannot start: picking local exercises must never depend on it.
CatalogState safeCatalogState(CatalogState Function() read) {
  try {
    return read();
  } on Object {
    return const CatalogState(status: CatalogStatus.unavailable);
  }
}

/// Catalogue and local exercises merged for pickers and the Exercises page.
final exerciseChoicesProvider = Provider<AsyncValue<List<ExerciseChoice>>>((
  ref,
) {
  final library = ref.watch(trainLibraryProvider);
  final catalog = safeCatalogState(() => ref.watch(catalogStateProvider))
      .snapshot;
  return library.whenData(
    (data) => buildExerciseChoices(local: data.exercises, catalog: catalog),
  );
});
