import 'package:beyondrep/features/catalog/application/catalog_providers.dart';
import 'package:beyondrep/features/catalog/application/exercise_choices_provider.dart';
import 'package:beyondrep/features/catalog/data/catalog_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CatalogState read(ProviderContainer container) =>
      safeCatalogState(() => container.read(catalogStateProvider));

  test('an unconfigured catalogue layer reads as unavailable', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final state = read(container);
    expect(state.status, CatalogStatus.unavailable);
    expect(state.snapshot, isNull);
  });

  test('any other error is not swallowed', () {
    final container = ProviderContainer(
      overrides: [
        catalogRepositoryProvider.overrideWith(
          (ref) => throw StateError('real bug'),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(() => read(container), throwsA(anything));
  });

  test('a TypeError from the catalogue layer is not swallowed', () {
    final container = ProviderContainer(
      overrides: [
        catalogRepositoryProvider.overrideWith((ref) => throw TypeError()),
      ],
    );
    addTearDown(container.dispose);
    expect(() => read(container), throwsA(anything));
  });
}
