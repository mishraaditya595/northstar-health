import 'package:flutter/material.dart';

import '../../core/design/page_header.dart';
import '../account/account_auth_controller.dart';

/// Standard design kit notice. Never claims a local-only workout was uploaded.
class BackupStatusNotice extends StatelessWidget {
  const BackupStatusNotice({
    required this.controller,
    this.blockedCount = 0,
    this.unsyncedCount = 0,
    this.reviewCount = 0,
    this.onSyncNow,
    super.key,
  });

  final AccountAuthController? controller;
  final int blockedCount;
  final int unsyncedCount;

  /// Conflicted/skipped workouts: retrying cannot fix them, so no action.
  final int reviewCount;

  /// Runs the foreground upload/restore now. Null hides the action.
  final VoidCallback? onSyncNow;

  @override
  Widget build(BuildContext context) {
    final auth = controller;
    if (auth == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: auth,
      builder: (context, child) {
        final showUnsynced = !auth.backupPaused && unsyncedCount > 0;
        if (!auth.backupPaused &&
            blockedCount == 0 &&
            reviewCount == 0 &&
            !showUnsynced) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (auth.backupPaused)
                  const InsightCard(
                    icon: Icons.cloud_off_outlined,
                    text: TextSpan(
                      text:
                          'Session expired — backup paused. '
                          'Workouts stay saved locally. '
                          'Sign in again before they can sync.',
                    ),
                  ),
                if (showUnsynced)
                  InsightCard(
                    icon: Icons.sync_problem_outlined,
                    text: TextSpan(
                      text:
                          '$unsyncedCount completed '
                          'workout${unsyncedCount == 1 ? '' : 's'} not synced '
                          'yet. Saved on this phone.',
                    ),
                    actionLabel: onSyncNow == null ? null : 'Sync now',
                    onAction: onSyncNow,
                  ),
                if ((auth.backupPaused || showUnsynced) && reviewCount > 0)
                  const SizedBox(height: 8),
                if (reviewCount > 0)
                  InsightCard(
                    icon: Icons.devices_outlined,
                    text: TextSpan(
                      text:
                          '$reviewCount completed '
                          'workout${reviewCount == 1 ? '' : 's'} changed on '
                          'another device. This phone\'s copy is kept; '
                          'conflict review is not available yet.',
                    ),
                  ),
                if ((auth.backupPaused || showUnsynced || reviewCount > 0) &&
                    blockedCount > 0)
                  const SizedBox(height: 8),
                if (blockedCount > 0)
                  InsightCard(
                    icon: Icons.error_outline,
                    text: TextSpan(
                      text:
                          '$blockedCount completed '
                          'workout${blockedCount == 1 ? '' : 's'} saved locally '
                          'but not backup-compatible. No upload will be '
                          'attempted for these workouts.',
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
