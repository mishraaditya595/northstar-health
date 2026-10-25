import 'package:flutter/material.dart';

import '../../core/design/page_header.dart';
import '../account/account_auth_controller.dart';

/// Standard design kit notice. Never claims a local-only workout was uploaded.
class BackupStatusNotice extends StatelessWidget {
  const BackupStatusNotice({
    required this.controller,
    this.blockedCount = 0,
    super.key,
  });

  final AccountAuthController? controller;
  final int blockedCount;

  @override
  Widget build(BuildContext context) {
    final auth = controller;
    if (auth == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: auth,
      builder: (context, child) {
        if (!auth.backupPaused && blockedCount == 0) {
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
                if (auth.backupPaused && blockedCount > 0)
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
