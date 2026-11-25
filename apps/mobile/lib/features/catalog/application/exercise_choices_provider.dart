import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;

import '../../train/train_library_state.dart';
import '../data/catalog_repository.dart';
import '../domain/exercise_choices.dart';
import 'catalog_providers.dart';

/// The catalogue state, or "unavailable" when the catalogue layer has not
/// been set up ([CatalogNotInitialized]). Every other error is rethrown:
/// picking local exercises must work without the catalogue, but a real bug
/// must not be hidden.
CatalogState safeCatalogState(CatalogState Function() read) {
  try {
    return read();
  } on Object catch (error) {
    if (_isNotInitialized(error)) {
      return const CatalogState(status: CatalogStatus.unavailable);
    }
    rethrow;
  }
}

bool _isNotInitialized(Object error) {
  var current = error;
  while (current is ProviderException) {
    current = current.exception;
  }
  return current is CatalogNotInitialized;
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
