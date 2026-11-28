import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_auth_controller.dart';
import '../../account/account_auth_provider.dart';
import 'workout_health_export_controller.dart';

/// Runs a health export pass after the first frame, on resume and when an
/// account signs in. Mirrors `CatalogRefreshHost`.
class HealthExportHost extends ConsumerStatefulWidget {
  const HealthExportHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<HealthExportHost> createState() => _HealthExportHostState();
}

class _HealthExportHostState extends ConsumerState<HealthExportHost>
    with WidgetsBindingObserver {
  AccountAuthController? _auth;
  String? _user;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth = ref.read(accountAuthControllerProvider);
    _user = _auth?.userId;
    _auth?.addListener(_onAuthChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _kick();
  }

  void _onAuthChanged() {
    final user = _auth?.userId;
    if (user != null && user != _user) _kick();
    _user = user;
  }

  void _kick() {
    if (!mounted || _auth?.userId == null) return;
    ref.read(healthExportKickProvider)();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
