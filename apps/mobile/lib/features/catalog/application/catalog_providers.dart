import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../account/account_auth_provider.dart';
import '../data/catalog_file_store.dart';
import '../data/catalog_repository.dart';
import '../data/catalog_transport.dart';
import '../domain/catalog_models.dart';

/// Overridden by the account gate with the per-host shared cache directory.
final catalogDirectoryProvider = Provider<Directory>(
  (ref) => throw StateError('Catalogue directory not initialized'),
);

/// Test seams; production uses the real clock and the isolate parser.
final catalogClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
final catalogParserProvider =
    Provider<Future<CatalogSnapshot?> Function(String text)?>((ref) => null);

final catalogTransportProvider = Provider<CatalogTransport>((ref) {
  final owner = ref.watch(accountAuthControllerProvider)?.userId;
  if (owner == null) {
    throw StateError('Catalogue downloads require a bound account');
  }
  return SupabaseCatalogTransport.fromClient(Supabase.instance.client, owner);
});

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  final repository = CatalogRepository(
    transport: ref.watch(catalogTransportProvider),
    store: CatalogFileStore(ref.watch(catalogDirectoryProvider)),
    clock: ref.watch(catalogClockProvider),
    parseInBackground: ref.watch(catalogParserProvider),
  );
  unawaited(repository.load());
  ref.onDispose(repository.dispose);
  return repository;
});

final catalogStateProvider =
    NotifierProvider<CatalogStateNotifier, CatalogState>(
      CatalogStateNotifier.new,
    );

class CatalogStateNotifier extends Notifier<CatalogState> {
  @override
  CatalogState build() {
    final repository = ref.watch(catalogRepositoryProvider);
    void onChanged() => state = repository.state;
    repository.addListener(onChanged);
    ref.onDispose(() => repository.removeListener(onChanged));
    return repository.state;
  }
}
