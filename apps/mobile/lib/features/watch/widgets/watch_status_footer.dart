import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/status_line.dart';
import '../application/watch_status_provider.dart';
import '../domain/watch_status.dart';
import 'watch_time_format.dart';

/// The bottom of Today when the watch works: one quiet line. It opens
/// Account & sync. Nothing for any other state.
class WatchStatusFooter extends ConsumerWidget {
  const WatchStatusFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(watchStatusProvider);
    if (status is! WatchSynced) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: NsStatusLine(
        'Apple Watch · synced ${watchTime(context, status.at)}',
        onTap: () => context.push('/today/account'),
      ),
    );
  }
}
