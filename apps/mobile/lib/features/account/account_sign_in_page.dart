import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/dialogs.dart';
import '../../core/design/inputs.dart';
import 'account_auth_controller.dart';

/// Initial authentication requires an online Supabase email OTP.
/// No workout navigation is instantiated until secure owner binding succeeds.
class AccountSignInPage extends StatefulWidget {
  const AccountSignInPage({required this.controller, super.key});

  final AccountAuthController controller;

  @override
  State<AccountSignInPage> createState() => _AccountSignInPageState();
}

class _AccountSignInPageState extends State<AccountSignInPage> {
  final _email = TextEditingController();
  final _otp = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final auth = widget.controller;
        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.monitor_heart_outlined,
                            color: colorScheme.primary,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'NORTHSTAR',
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -1,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            auth.codeSent
                                ? 'VERIFY YOUR EMAIL'
                                : auth.confirmedLocalCleanupPending
                                ? 'FINISH DATA REMOVAL'
                                : auth.deletionRecoveryPending
                                ? 'RECOVER ORIGINAL ACCOUNT'
                                : 'SHOW UP. GET STRONG.',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            auth.codeSent
                                ? 'Enter the six-digit sign-in code sent to your email.'
                                : auth.confirmedLocalCleanupPending
                                ? 'Cloud deletion was confirmed. Local data '
                                      'removal must finish before sign-in.'
                                : auth.deletionRecoveryPending
                                ? 'A deletion result was uncertain. Only the '
                                      'original account can be recovered if it '
                                      'still exists. Recovery does NOT create '
                                      'a new account or unlock another user’s data.'
                                : 'Create your account or sign in to start tracking.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),
                          if (!auth.codeSent) ...[
                            NsTextField(
                              controller: _email,
                              enabled:
                                  !auth.busy &&
                                  !auth.confirmedLocalCleanupPending,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              autocorrect: false,
                              label: 'Email address',
                              onSubmitted: (_) => auth.requestCode(_email.text),
                            ),
                            const SizedBox(height: 14),
                            FilledButton(
                              onPressed:
                                  auth.busy || auth.confirmedLocalCleanupPending
                                  ? null
                                  : () => auth.requestCode(_email.text),
                              child: Text(
                                auth.deletionRecoveryPending
                                    ? 'Send recovery code'
                                    : 'Send sign-in code',
                              ),
                            ),
                          ] else ...[
                            NsTextField(
                              controller: _otp,
                              enabled: !auth.busy,
                              autofocus: true,
                              keyboardType: TextInputType.number,
                              autofillHints: const [AutofillHints.oneTimeCode],
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              label: 'Six-digit code',
                              onSubmitted: (_) => auth.verifyCode(_otp.text),
                            ),
                            const SizedBox(height: 14),
                            FilledButton(
                              onPressed: auth.busy
                                  ? null
                                  : () => auth.verifyCode(_otp.text),
                              child: Text(
                                auth.deletionRecoveryPending
                                    ? 'Verify original account'
                                    : 'Verify and continue',
                              ),
                            ),
                            TextButton(
                              onPressed: auth.busy
                                  ? null
                                  : () => auth.requestCode(_email.text),
                              child: const Text('Resend code'),
                            ),
                            TextButton(
                              onPressed: auth.busy ? null : auth.changeEmail,
                              child: const Text('Use a different email'),
                            ),
                          ],
                          if (auth.deletionRecoveryPending &&
                              !auth.confirmedLocalCleanupPending &&
                              !auth.codeSent) ...[
                            const SizedBox(height: 14),
                            TextButton(
                              onPressed: auth.busy
                                  ? null
                                  : () async {
                                      final leave = await showNsConfirm(
                                        context,
                                        title: 'Erase local data and leave recovery?',
                                        message:
                                            'Your cloud account may still exist if '
                                            'deletion was not confirmed. This will '
                                            'permanently erase this device’s '
                                            'original workouts, unfinished sessions, '
                                            'custom plans and pending uploads, '
                                            'including items never backed up. '
                                            'It does not delete cloud data. '
                                            'Only choose this if you no longer '
                                            'need any local workout data.',
                                        confirmLabel: 'Erase local data and leave',
                                        cancelLabel: 'Keep recovering',
                                      );
                                      if (leave == true) {
                                        await auth.leaveDeletionRecovery();
                                      }
                                    },
                              child: const Text(
                                'Erase local workouts and use another account',
                              ),
                            ),
                          ],
                          if (auth.confirmedLocalCleanupPending) ...[
                            const Text(
                              'The account is deleted. Local workouts remain '
                              'locked until the cleanup finishes.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 14),
                            FilledButton(
                              onPressed: auth.busy
                                  ? null
                                  : auth.retryConfirmedLocalCleanup,
                              child: const Text('Retry local data removal'),
                            ),
                          ],
                          if (auth.busy) ...[
                            const SizedBox(height: 16),
                            const Center(child: CircularProgressIndicator()),
                          ],
                          if (auth.notice != null) ...[
                            const SizedBox(height: 16),
                            Text(auth.notice!, textAlign: TextAlign.center),
                          ],
                          if (auth.error != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              auth.error!,
                              style: TextStyle(color: colorScheme.error),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 24),
                          const Text(
                            'A NorthStar account is required. Once signed in, '
                            'you can record workouts without an internet '
                            'connection. Completed workouts are automatically '
                            'backed up to your account when online. Unfinished '
                            'sessions stay on this device.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No health-platform measurements are included in '
                            'workout backups.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
