import 'package:flutter/widgets.dart';

import '../../core/storage/account_store.dart';
import 'account_auth_controller.dart';

/// Removes only a verified, previously bound account's directory after the
/// server has returned the exact success receipt. Never called for timeouts.
class NativeAccountDataCleaner implements LocalAccountDataCleaner {
  const NativeAccountDataCleaner({required this.projectHost});

  final String projectHost;

  @override
  Future<void> erase(String owner, {bool waitForUnmount = false}) async {
    if (waitForUnmount) {
      // Controller clears userId and notifies AccountGate *before* this call.
      // End of frame lets the old ProviderScope and ObjectBox Store dispose.
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
    }
    await deleteBoundAccountStore(owner, projectHost: projectHost);
  }
}
