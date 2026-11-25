import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_auth_controller.dart';
import '../../account/account_auth_provider.dart';
import 'catalog_providers.dart';

/// Refreshes the shared catalogue (at most once a day, see the repository)
/// on start, on resume, and when cloud backup becomes ready for the account.
class CatalogRefreshHost extends ConsumerStatefulWidget {
  const CatalogRefreshHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<CatalogRefreshHost> createState() => _CatalogRefreshHostState();
}

class _CatalogRefreshHostState extends ConsumerState<CatalogRefreshHost>
    with WidgetsBindingObserver {
  AccountAuthController? _auth;
  bool _wasReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth = ref.read(accountAuthControllerProvider);
    _wasReady = _auth?.cloudBackupReady ?? false;
    _auth?.addListener(_onAuthChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _onAuthChanged() {
    final ready = _auth?.cloudBackupReady ?? false;
    if (ready && !_wasReady) _refresh();
    _wasReady = ready;
  }

  void _refresh() {
    if (!mounted) return;
    final auth = _auth;
    if (auth == null || !auth.cloudBackupReady) return;
    // Repository.refresh waits for load() and honours the 24 hour window.
    unawaited(ref.read(catalogRepositoryProvider).refresh());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
