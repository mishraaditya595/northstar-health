import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/design/beyondrep_theme.dart';
import '../../../core/design/page_header.dart';
import '../application/watch_status_provider.dart';
import '../domain/watch_platform.dart';
import '../domain/watch_status.dart';
import 'watch_time_format.dart';

/// The watch section of Account & sync. Hidden unless the platform reports a
/// paired watch, so people without one see nothing.
class WatchAccountSection extends ConsumerWidget {
  const WatchAccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(watchLinkStateProvider);
    final status = state.status;
    if (status is WatchHidden) return const SizedBox.shrink();
    final now = ref.watch(localNowProvider);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final stale = status is WatchStale;
    final lastSynced = switch (status) {
      WatchSynced(:final at) || WatchStale(:final at) => at,
      _ => null,
    };
    final summary = state.sentSummary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            watchName(defaultTargetPlatform).toUpperCase(),
            style: theme.textTheme.labelSmall,
          ),
        ),
        const SizedBox(height: 18),
        NsListCard(
          icon: Icons.watch_outlined,
          title: switch (status) {
            WatchSynced() => 'Connected',
            WatchNotInstalled() => 'Not installed',
            WatchWaiting() => 'Waiting for the watch',
            WatchStale() => 'Not synced recently',
            WatchHidden() => '',
          },
          subtitle: 'Status',
        ),
        const SizedBox(height: 8),
        NsListCard(
          icon: Icons.download_done_outlined,
          title: state.device.installed ? 'Installed' : 'Not installed',
          subtitle: 'BeyondRep on watch',
        ),
        const SizedBox(height: 8),
        NsListCard(
          icon: Icons.sync_outlined,
          title: lastSynced == null
              ? 'Not synced yet'
              : watchDayTime(context, lastSynced, now),
          subtitle: 'Last synced',
          trailing: stale
              ? Icon(
                  Icons.error_outline,
                  semanticLabel: 'Not synced recently',
                  color: dark
                      ? BeyondRepPalette.amberDark
                      : BeyondRepPalette.amberLight,
                )
              : null,
        ),
        if (summary != null) ...[
          const SizedBox(height: 8),
          NsListCard(
            icon: Icons.upload_outlined,
            title: summary,
            subtitle: 'Sent to watch',
          ),
        ],
        const SizedBox(height: 28),
      ],
    );
  }
}
