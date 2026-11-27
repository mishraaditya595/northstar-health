import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/dialogs.dart';
import '../application/phone_live_session.dart';

/// Asks the person holding the phone before a discard that the Apple Watch
/// requested for the phone's workout. Nothing is discarded unless they
/// confirm; keeping the workout answers the watch with a refusal.
class PhoneDiscardConfirmHost extends ConsumerStatefulWidget {
  const PhoneDiscardConfirmHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PhoneDiscardConfirmHost> createState() =>
      _PhoneDiscardConfirmHostState();
}

class _PhoneDiscardConfirmHostState
    extends ConsumerState<PhoneDiscardConfirmHost> {
  bool _asking = false;

  Future<void> _ask() async {
    if (_asking || !mounted) return;
    _asking = true;
    final yes = await showNsConfirm(
      context,
      title: 'Discard workout?',
      message:
          'Your Apple Watch asked to discard this workout. It will not '
          'appear in your completed history.',
      cancelLabel: 'Keep training',
      confirmLabel: 'Discard workout',
    );
    _asking = false;
    if (!mounted) return;
    ref.read(phoneLiveSessionProvider.notifier).resolveDiscard(yes);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(phoneLiveSessionProvider, (_, next) {
      if (next.pendingDiscard) _ask();
    });
    return widget.child;
  }
}
