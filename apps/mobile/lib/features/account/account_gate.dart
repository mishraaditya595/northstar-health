import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/northstar_app.dart';
import '../../core/design/northstar_theme.dart';
import '../../core/storage/account_store.dart';
import '../../core/storage/objectbox_store_provider.dart';
import '../../objectbox.g.dart';
import 'account_auth_controller.dart';
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
        title: 'Northstar Health · Sign in',
        debugShowCheckedModeBanner: false,
        theme: NorthstarTheme.build(Brightness.light),
        darkTheme: NorthstarTheme.build(Brightness.dark),
        home: AccountSignInPage(controller: controller),
      );
    },
  );
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
            accountAuthControllerProvider.overrideWithValue(widget.controller),
            blockedWorkoutCountProvider.overrideWith(
              (ref) => ref.watch(workoutOutboxProvider).blockedCount(),
            ),
          ],
          child: const NorthstarApp(),
        );
      }
      return MaterialApp(
        title: 'Northstar Health',
        theme: NorthstarTheme.build(Brightness.light),
        darkTheme: NorthstarTheme.build(Brightness.dark),
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
