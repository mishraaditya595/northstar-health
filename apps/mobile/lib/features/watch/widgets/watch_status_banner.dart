import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/clock.dart';
import '../../../core/design/page_header.dart';
import '../application/watch_status_provider.dart';
import '../domain/watch_status.dart';
import 'watch_install_steps_sheet.dart';
import 'watch_time_format.dart';

/// The top of Today when the watch needs attention: BeyondRep is not on the
/// paired watch, or the watch has not synced for 48 hours. Nothing otherwise
/// (a quiet "synced" line goes to the bottom, see `WatchStatusFooter`).
class WatchStatusBanner extends ConsumerWidget {
  const WatchStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(watchLinkStateProvider);
    final status = state.status;
    if (status is WatchNotInstalled && !state.installHintDismissed) {
      return _padded(
        InsightCard(
          icon: Icons.watch_outlined,
          text: const TextSpan(
            children: [
              TextSpan(
                text: "BeyondRep isn't on your watch yet",
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              TextSpan(
                text:
                    '\nOpen the Watch app on this iPhone, find BeyondRep under '
                    'Available Apps and tap Install.',
              ),
            ],
          ),
          actionLabel: 'Show me how',
          onAction: () => showWatchInstallSteps(context),
          secondaryActionLabel: 'Not now',
          onSecondaryAction: () =>
              ref.read(watchLinkStateProvider.notifier).dismissInstallHint(),
        ),
      );
    }
    if (status is WatchStale) {
      final since = watchDayTime(
        context,
        status.at,
        ref.watch(localNowProvider),
      );
      return _padded(
        Semantics(
          button: true,
          onTapHint: 'Open Account and sync',
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => context.push('/today/account'),
            child: InsightCard(
              icon: Icons.watch_off_outlined,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: "Your watch hasn't synced since $since",
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const TextSpan(
                    text: '\nOpen the BeyondRep app on your watch',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _padded(Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Semantics(liveRegion: true, child: child),
  );
}
