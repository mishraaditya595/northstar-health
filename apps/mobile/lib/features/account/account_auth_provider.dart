import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_auth_controller.dart';

/// Overridden by AccountGate for all authenticated production routes.
/// A null default permits isolated design-system widget tests to mount Today.
final accountAuthControllerProvider = Provider<AccountAuthController?>(
  (ref) => null,
);
