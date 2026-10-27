import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/dialogs.dart';
import '../../core/design/inputs.dart';
import '../../core/design/page_header.dart';
import '../sync/workout_conflict_resolution.dart';
import '../sync/workout_upload_coordinator.dart';
import '../workouts/data/objectbox_workout_outbox.dart';
import 'account_auth_controller.dart';
import 'account_auth_provider.dart';
import 'account_sync_overview.dart';
import 'workout_export_file_writer.dart';
import 'workout_history_export.dart';

/// P2-07: a truthful device-local sync dashboard and account access surface.
/// Shows device-local sync state; exports selected cloud workout history
/// only on explicit user action. Delete requires a second verified OTP and
/// server-only hard deletion; this screen never handles privileged secrets.
class AccountSyncPage extends ConsumerStatefulWidget {
  const AccountSyncPage({super.key});

  @override
  ConsumerState<AccountSyncPage> createState() => _AccountSyncPageState();
}

class _AccountSyncPageState extends ConsumerState<AccountSyncPage> {
  bool _confirmingSignOut = false;
  bool _exporting = false;
  final _deletionCode = TextEditingController();

  @override
  void dispose() {
    _deletionCode.dispose();
    super.dispose();
  }

  Future<void> _beginDeletion(
    AccountAuthController auth,
    AccountSyncOverview overview,
  ) async {
    if (auth.busy || _exporting || !auth.cloudBackupReady) return;
    final warning = overview.hasUnresolvedLocalChanges
        ? 'This device has workouts waiting for backup, requiring review, '
              'or stored only locally. They will NOT be included in the '
              'cloud export, and they cannot be recovered from the server. '
        : '';
    final accepted = await showNsConfirm(
      context,
      title: 'Permanently delete your account?',
      message:
          '${warning}This permanently deletes your signed-in account, '
          'cloud workout history, deletion tombstones and sync receipts. '
          'Other devices will lose access. Once deletion is confirmed, '
          'this device will also erase this account\'s local workouts, '
          'plans and pending uploads. If the response is uncertain, local '
          'data stays locked instead. Export your cloud workout history FIRST, '
          'and be aware the current export has a 4 MiB limit. '
          'You must verify a new code sent using the normal Supabase '
          'sign-in email template before deletion.',
      confirmLabel: 'Send deletion code',
    );
    if (!accepted || !mounted || !auth.cloudBackupReady) return;
    await auth.requestDeletionCode();
    if (mounted && auth.error != null) {
      showNsMessage(context, auth.error!);
    }
  }

  Future<void> _confirmDeletion(AccountAuthController auth) async {
    if (auth.busy || _exporting || !auth.deletionCodeSent) return;
    final accepted = await showNsConfirm(
      context,
      title: 'Delete permanently?',
      message:
          'This cannot be undone. The verified account and its cloud '
          'history will be deleted. This device immediately locks the '
          'account partition. Once the server confirms deletion, local '
          'workouts, plans and unsynced data are permanently erased too. '
          'If the result is uncertain they remain locked, not erased.',
      confirmLabel: 'Delete permanently',
    );
    if (!accepted || !mounted || !auth.deletionCodeSent) return;
    await auth.confirmAccountDeletion(_deletionCode.text);
  }

  Future<void> _exportWorkouts(AccountAuthController auth) async {
    final owner = auth.userId;
    if (_exporting || owner == null || !auth.cloudBackupReady) return;
    setState(() => _exporting = true);
    try {
      final data = await ref
          .read(workoutHistoryExporterProvider)(owner)
          .exportJson();
      if (!mounted || auth.userId != owner || !auth.cloudBackupReady) return;
      final saved = await ref
          .read(workoutExportFileWriterProvider)
          .saveJson(data);
      if (!mounted || auth.userId != owner) return;
      if (saved) showNsMessage(context, 'Workout history exported.');
    } on WorkoutExportException catch (error) {
      if (mounted && auth.userId == owner) {
        showNsMessage(context, switch (error.code) {
          'history_changed_retry' =>
            'Cloud history changed during export. Please retry.',
          'export_too_large' =>
            'This history is too large for safe export on this device. '
                'A larger export method is not available yet.',
          'invalid_row' ||
          'invalid_order' ||
          'invalid_payload' ||
          'invalid_revision' ||
          'invalid_head' ||
          'page_too_large' =>
            'Cloud history contains unsupported or invalid data. '
                'Please contact support.',
          _ => 'Unable to export cloud history. Please retry.',
        });
      }
    } catch (_) {
      if (mounted && auth.userId == owner) {
        showNsMessage(context, 'Unable to export cloud history. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _signOut(
    BuildContext context,
    AccountAuthController auth,
    AccountSyncOverview overview,
  ) async {
    if (_confirmingSignOut || auth.busy) return;
    setState(() => _confirmingSignOut = true);
    try {
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
      if (!confirmed || !context.mounted || auth.busy) return;
      await auth.signOut();
      if (context.mounted && auth.error != null) {
        showNsMessage(context, auth.error!);
      }
    } finally {
      if (mounted) setState(() => _confirmingSignOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(accountAuthControllerProvider);
    if (auth == null) {
      return const Center(child: Text('Sign in to view account status.'));
    }
    // Auth is a ChangeNotifier, so the UI must rebuild on session expiry,
    // refresh and sign-out (not just on the Riverpod provider's identity).
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) => Consumer(
        builder: (context, ref, _) {
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

          return Scaffold(
            appBar: AppBar(
              leading: BackButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/today');
                  }
                },
              ),
              title: const Text('Account'),
            ),
            body: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                32 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Text(
                  'BACKUP & PRIVACY',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 18),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          online
                              ? 'Cloud session ready'
                              : 'Cloud backup paused',
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
                              onPressed: online && kick != null && !_exporting
                                  ? () {
                                      if (!auth.cloudBackupReady) {
                                        showNsMessage(
                                          context,
                                          'Cloud session expired. Sign in again '
                                          'before syncing.',
                                        );
                                        return;
                                      }
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
                                  'Status re-read from this device.',
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
                  title:
                      '${overview.localOnly} local-only workout${overview.localOnly == 1 ? '' : 's'}',
                  subtitle: 'These workouts cannot be backed up in their current form.',
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
                  'Unfinished sessions, custom plans and preferences stay '
                  'on this device. HealthKit/Health Connect measurements '
                  'are not integrated in this build. Signing out never deletes '
                  'either local or cloud records.',
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: online && !auth.busy && !_exporting
                      ? () => _exportWorkouts(auth)
                      : null,
                  icon: const Icon(Icons.file_download_outlined),
                  label: Text(
                    _exporting
                        ? 'Preparing export…'
                        : 'Export cloud workout history (JSON)',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Exports include completed phone workouts currently in '
                  'your cloud account. Pending local workouts, custom plans, '
                  'unfinished sessions and HealthKit/Health Connect data '
                  'are excluded. Choose the destination in the system '
                  'document picker; treat the file as private.',
                ),
                const SizedBox(height: 10),
                const Text(
                  'Deleting an account permanently removes its cloud history '
                  'and disables sign-in on other devices. Any unfinished or '
                  'unsynced workouts and custom plans on this device are NOT '
                  'part of the cloud export. A confirmed deletion also erases '
                  'this account\'s local workouts and plans; an uncertain '
                  'server result only locks them.',
                ),
                const SizedBox(height: 12),
                if (!auth.deletionCodeSent)
                  OutlinedButton.icon(
                    onPressed:
                        online &&
                            !auth.busy &&
                            !_exporting &&
                            !_confirmingSignOut
                        ? () => _beginDeletion(auth, overview)
                        : null,
                    icon: const Icon(Icons.person_remove_outlined),
                    label: const Text('Permanently delete account'),
                  )
                else ...[
                  NsTextField(
                    controller: _deletionCode,
                    label: 'Six-digit deletion code',
                    enabled: !auth.busy && !_exporting,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    onSubmitted: (_) => _confirmDeletion(auth),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This code arrives in the usual sign-in email; there '
                    'is no separate deletion-email template.',
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: auth.busy || _exporting
                        ? null
                        : () => _confirmDeletion(auth),
                    child: const Text('Verify and permanently delete'),
                  ),
                  TextButton(
                    onPressed: auth.busy ? null : auth.cancelDeletion,
                    child: const Text('Cancel account deletion'),
                  ),
                ],
                if (auth.error != null &&
                    (auth.deletionCodeSent ||
                        auth.error!.toLowerCase().contains('deletion') ||
                        auth.error!.contains('session expired'))) ...[
                  const SizedBox(height: 8),
                  Text(
                    auth.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed:
                      auth.busy ||
                          auth.deletionCodeSent ||
                          _confirmingSignOut ||
                          _exporting
                      ? null
                      : () => _signOut(context, auth, overview),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out of this device'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
