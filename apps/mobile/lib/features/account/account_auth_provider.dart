import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_auth_controller.dart';

/// Overridden by each unlocked account's ProviderScope.
/// UI must not use this provider to infer server-side authorization.
final accountAuthControllerProvider = Provider<AccountAuthController>((ref) {
  throw StateError('No unlocked account scope');
});
