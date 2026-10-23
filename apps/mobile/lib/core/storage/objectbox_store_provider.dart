import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../objectbox.g.dart';

/// A single app-scoped Store, overridden during app bootstrap.
final objectBoxStoreProvider = Provider<Store>((ref) {
  throw StateError('ObjectBox Store not initialized');
});

/// Generated Flutter openStore uses the app documents directory. Never
/// silently delete/recreate a user's database on initialization failure.
Future<Store> initializeObjectBox() => openStore();
