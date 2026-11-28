import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:objectbox_flutter_libs/objectbox_flutter_libs.dart';

import '../../app/beyondrep_app.dart';
import '../../core/design/beyondrep_theme.dart';
import '../../core/storage/account_store.dart';
import '../../core/storage/objectbox_store_provider.dart';
import '../../objectbox.g.dart';
import '../catalog/application/catalog_providers.dart';
import '../catalog/application/catalog_definition_sync.dart';
import '../catalog/application/catalog_refresh_host.dart';
import '../catalog/data/catalog_file_store.dart';
import 'account_auth_controller.dart';
import '../health/application/health_export_host.dart';
import '../health/application/health_overview.dart';
import '../health/application/own_workout_health.dart';
import '../health/data/health_export_repository.dart';
import '../health/data/health_reader.dart';
import '../health/data/health_workout_writer.dart';
import '../health/data/platform_health_reader.dart';
import '../sync/workout_upload_coordinator.dart';
import '../watch/application/watch_sync_controller.dart';
import '../watch/data/objectbox_watch_workout_importer.dart';
import '../sync/objectbox_workout_restore_importer.dart';
import '../sync/workout_conflict_resolution.dart';
import '../workouts/data/objectbox_workout_outbox.dart';
import 'account_auth_provider.dart';
import 'account_sign_in_page.dart';

/// The entire workout UI stays unmounted unless an account is unlocked.
/// In tests, [authenticatedBuilder] can replace the native ObjectBox store.
class AccountGate extends StatelessWidget {
  const AccountGate({
    required this.controller,
    required this.authenticatedBuilder,
    super.key,
  });

  final AccountAuthController controller;
  final Widget Function(String) authenticatedBuilder;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final id = controller.userId;
      if (id != null) return authenticatedBuilder(id);
      return MaterialApp(
        title: 'BeyondRep · Sign in',
        debugShowCheckedModeBanner: false,
        theme: BeyondRepTheme.build(Brightness.light),
        darkTheme: BeyondRepTheme.build(Brightness.dark),
        home: AccountSignInPage(controller: controller),
      );
    },
  );
}

/// The platform record of a watch workout for the signed-in account.
/// iOS: the HKWorkout UUID in the import receipt. Android: the Health Connect
/// record the phone wrote, found through its export receipt, so it is null
/// until the watch health write confirms it; that write invalidates this
/// family member (`watchWorkoutHealthInboxProvider` `onWritten`).
String? resolveWatchWorkoutPlatformId(Ref ref, String workoutUuid) {
  final auth = ref.watch(accountAuthControllerProvider);
  final owner = auth?.userId;
  if (owner == null) return null;
  if (!ref.watch(healthWorkoutWriterProvider).isIos) {
    return confirmedPlatformRecordId(
      ref.watch(healthExportRepositoryProvider),
      workoutUuid,
    );
  }
  return ref
      .watch(watchWorkoutImporterProvider)(owner, () => auth?.userId)
      .platformWorkoutUuidFor(workoutUuid);
}

/// Native ObjectBox is not opened until AccountGate verified the account.
/// Swapping account IDs disposes the previous ProviderScope and Store.
class BoundAccountWorkoutApp extends StatefulWidget {
  const BoundAccountWorkoutApp({
    required this.accountId,
    required this.projectHost,
    required this.controller,
    super.key,
  });

  final String accountId;
  final String projectHost;
  final AccountAuthController controller;

  @override
  State<BoundAccountWorkoutApp> createState() => _BoundAccountWorkoutAppState();
}

class _BoundAccountWorkoutAppState extends State<BoundAccountWorkoutApp> {
  late Future<Store> _opening;
  Store? _store;
  Directory? _catalogDirectory;

  @override
  void initState() {
    super.initState();
    _opening = _open();
  }

  Future<Store> _open() async {
    final store = await openBoundAccountStore(
      widget.accountId,
      projectHost: widget.projectHost,
    );
    if (!mounted) {
      store.close();
      throw StateError('Account storage was closed during initialization');
    }
    _store = store;
    // Shared across accounts on this backend host; holds no account data.
    _catalogDirectory = Directory(
      '${(await defaultStoreDirectory()).path}/'
      '${catalogCacheRelativePath(widget.projectHost)}',
    );
    return store;
  }

  @override
  void dispose() {
    _store?.close();
    super.dispose();
  }

  void _retry() {
    setState(() => _opening = _open());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Store>(
    future: _opening,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return ProviderScope(
          overrides: [
            objectBoxStoreProvider.overrideWithValue(snapshot.requireData),
            catalogDirectoryProvider.overrideWithValue(_catalogDirectory!),
            accountAuthControllerProvider.overrideWithValue(widget.controller),
            // A factory, not a value: build() reruns on every auth notification
            // and a fresh unequal value would invalidate the health summary.
            healthReaderProvider.overrideWith(
              (ref) => PlatformHealthReader.system(),
            ),
            ownPlatformWorkoutIdsProvider.overrideWith((ref) {
              final auth = ref.watch(accountAuthControllerProvider);
              final owner = auth?.userId;
              if (owner == null) return const {};
              return ref
                  .watch(watchWorkoutImporterProvider)(
                    owner,
                    () => auth?.userId,
                  )
                  .platformWorkoutUuids();
            }),
            watchWorkoutPlatformIdProvider.overrideWith(
              resolveWatchWorkoutPlatformId,
            ),
            workoutUploadKickProvider.overrideWith(
              (ref) => ref.read(workoutUploadCoordinatorProvider).kick,
            ),
            workoutRestoreCursorProvider.overrideWith((ref) {
              final auth = ref.watch(accountAuthControllerProvider);
              final owner = auth?.userId;
              if (owner == null) return null;
              return ref
                  .watch(workoutRestoreImporterProvider)(
                    owner,
                    () => auth?.userId,
                  )
                  .readCursor();
            }),
            blockedWorkoutCountProvider.overrideWith(
              (ref) => ref.watch(workoutOutboxProvider).blockedCount(),
            ),
            workoutSyncFlagsProvider.overrideWith(
              (ref) => ref.watch(workoutOutboxProvider).syncFlags(),
            ),
          ],
          child: const AccountWorkoutUploadHost(
            child: WatchSyncHost(
              child: CatalogDefinitionSyncHost(
                child: HealthExportHost(
                  child: CatalogRefreshHost(child: BeyondRepApp()),
                ),
              ),
            ),
          ),
        );
      }
      return MaterialApp(
        title: 'BeyondRep',
        theme: BeyondRepTheme.build(Brightness.light),
        darkTheme: BeyondRepTheme.build(Brightness.dark),
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: snapshot.hasError
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.storage_rounded, size: 44),
                        const SizedBox(height: 16),
                        const Text(
                          'Could not unlock this account\'s local workouts. '
                          'No data has been deleted.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _retry,
                          child: const Text('Retry'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => widget.controller.signOut(),
                          child: const Text('Sign out of this account'),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
        ),
      );
    },
  );
}
