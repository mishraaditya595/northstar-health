import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../account/account_auth_provider.dart';
import '../data/catalog_file_store.dart';
import '../data/catalog_repository.dart';
import '../data/catalog_transport.dart';
import '../domain/catalog_models.dart';

/// The catalogue layer has no directory or bound account yet. Screens treat
/// this, and only this, as "catalogue unavailable".
class CatalogNotInitialized implements Exception {
  const CatalogNotInitialized(this.reason);

  final String reason;

  @override
  String toString() => 'CatalogNotInitialized($reason)';
}

/// Overridden by the account gate with the per-host shared cache directory.
final catalogDirectoryProvider = Provider<Directory>(
  (ref) => throw const CatalogNotInitialized('directory'),
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
    throw const CatalogNotInitialized('account');
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
