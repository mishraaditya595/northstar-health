import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/dialogs.dart';
import '../../core/design/page_header.dart';
import '../sync/workout_conflict_resolution.dart';
import '../sync/workout_upload_coordinator.dart';
import '../workouts/data/objectbox_workout_outbox.dart';
import 'account_auth_controller.dart';
import 'account_auth_provider.dart';
import 'account_sync_overview.dart';

/// P2-07: a truthful device-local sync dashboard and account access surface.
/// Does not claim cloud completion, delete a server account or export raw data.
class AccountSyncPage extends ConsumerWidget {
  const AccountSyncPage({super.key});

  Future<void> _signOut(
    BuildContext context,
    AccountAuthController auth,
    AccountSyncOverview overview,
  ) async {
    final warning = overview.hasUnresolvedLocalChanges
        ? 'Some completed workouts still need backup or review. '
          'They will stay on this device and will not move to a different '
          'account. Sign in to the same account to resume. '
        : '';
    final confirmed = await showNsConfirm(
      context,
      title: 'Sign out of NorthStar?',
      message:
          '${warning}All workouts, unfinished sessions and custom plans '
          'remain on this device. Signing out locks their local account '
          'partition; it does not erase your cloud account or its data.',
      confirmLabel: 'Sign out',
    );
    if (!confirmed || !context.mounted) return;
    await auth.signOut();
    if (context.mounted && auth.error != null) {
      showNsMessage(context, auth.error!);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(accountAuthControllerProvider);
    if (auth == null) {
      return const Center(child: Text('Sign in to view account status.'));
    }
    // Auth is a ChangeNotifier, so the UI must rebuild on session expiry,
    // refresh and sign-out (not just on the Riverpod provider's identity).
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        if (auth.userId == null) {
          return const Center(
            child: Text('Signed out. Sign in to review account status.'),
          );
        }
        final flags = ref.watch(workoutSyncFlagsProvider);
        final overview = AccountSyncOverview.fromState(
          flags: flags,
          blockedOperations: ref.watch(blockedWorkoutCountProvider),
          restorePaused: ref.watch(workoutRestoreBlockedCodeProvider) != null,
        );
        final kick = ref.watch(workoutUploadKickProvider);
        final online = auth.cloudBackupReady;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            16, 16, 16, 32 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            const PageHeader(title: 'Account', eyebrow: 'BACKUP & PRIVACY'),
            const SizedBox(height: 18),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      online ? 'Cloud session ready' : 'Cloud backup paused',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      online
                          ? 'Signed in on this device. Only completed '
                            'NorthStar phone workouts are eligible for '
                            'automatic cloud backup while the app is active.'
                          : 'Your saved workouts remain available on this '
                            'device. Cloud transfers need a renewed sign-in '
                            'and a working connection.',
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: online && kick != null
                              ? () {
                                  kick();
                                  showNsMessage(
                                    context,
                                    'Sync requested. Check status again after '
                                    'the foreground worker finishes.',
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.sync),
                          label: const Text('Sync now'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            ref.invalidate(workoutSyncFlagsProvider);
                            ref.invalidate(blockedWorkoutCountProvider);
                            ref.invalidate(workoutRestoreCursorProvider);
                            showNsMessage(
                              context,
                              'Refreshed status saved on this device.',
                            );
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh status'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Workout backup status',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'These counts show unresolved changes on this device, not '
              'a verified count of cloud workouts.',
            ),
            const SizedBox(height: 12),
            NsListCard(
              icon: Icons.schedule_outlined,
              title: '${overview.queued} queued for backup',
              subtitle:
                  'Saved locally; upload waits for foreground sync '
                  'or a successful retry.',
            ),
            const SizedBox(height: 8),
            NsListCard(
              icon: Icons.compare_arrows_outlined,
              title: '${overview.needsReview} need review',
              subtitle:
                  'Conflicting or skipped changes are kept until you '
                  'choose how to resolve them.',
            ),
            const SizedBox(height: 8),
            NsListCard(
              icon: Icons.phone_android_outlined,
              title: '${overview.localOnly} local-only workouts',
              subtitle:
                  'These workouts cannot be backed up in their current form.',
            ),
            if (overview.blockedOperations > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${overview.blockedOperations} blocked upload '
                'operation${overview.blockedOperations == 1 ? '' : 's'} '
                'require review (operations may share a workout).',
              ),
            ],
            if (overview.restorePaused) ...[
              const SizedBox(height: 8),
              const NsListCard(
                icon: Icons.cloud_off_outlined,
                title: 'Cloud restore paused',
                subtitle:
                    'The shared restore cursor is blocked. '
                    'Review the saved position before retrying.',
              ),
            ],
            if (!overview.hasIssues) ...[
              const SizedBox(height: 12),
              const Text(
                'No unresolved sync issue is recorded on this device. '
                'This does not verify that every workout is in the cloud.',
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: overview.requiresReview
                  ? () => context.push('/today/sync/review')
                  : null,
              icon: const Icon(Icons.rule_outlined),
              label: const Text('Review sync issues'),
            ),
            const SizedBox(height: 28),
            Text(
              'Your data',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Completed phone workouts (including sets, loads, exercise '
              'labels and timestamps) can be backed up automatically. '
              'Unfinished sessions, custom plans, preferences and health '
              'measurements stay on this device. Signing out never deletes '
              'either local or cloud records.',
            ),
            const SizedBox(height: 10),
            const Text(
              'JSON history export and permanent account deletion are '
              'not yet available in this development build. Do not '
              'interpret sign-out as account deletion.',
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => _signOut(context, auth, overview),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out of this device'),
            ),
          ],
        );
      },
    );
  }
}
