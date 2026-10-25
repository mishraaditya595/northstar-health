import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
                                : 'SHOW UP. GET STRONG.',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            auth.codeSent
                                ? 'Enter the six-digit sign-in code sent to your email.'
                                : 'Create your account or sign in to start tracking.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),
                          if (!auth.codeSent) ...[
                            TextField(
                              controller: _email,
                              enabled: !auth.busy,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.email],
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Email address',
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (_) => auth.requestCode(_email.text),
                            ),
                            const SizedBox(height: 14),
                            FilledButton(
                              onPressed: auth.busy
                                  ? null
                                  : () => auth.requestCode(_email.text),
                              child: const Text('Send sign-in code'),
                            ),
                          ] else ...[
                            TextField(
                              controller: _otp,
                              enabled: !auth.busy,
                              autofocus: true,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.oneTimeCode],
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Six-digit code',
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (_) => auth.verifyCode(_otp.text),
                            ),
                            const SizedBox(height: 14),
                            FilledButton(
                              onPressed: auth.busy
                                  ? null
                                  : () => auth.verifyCode(_otp.text),
                              child: const Text('Verify and continue'),
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
                          if (auth.busy) ...[
                            const SizedBox(height: 16),
                            const Center(child: CircularProgressIndicator()),
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
