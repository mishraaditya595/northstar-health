import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/dialogs.dart';

/// The published policy; the same URL the Health Connect rationale screen
/// and the store listings use.
final privacyPolicyUrl = Uri.parse('https://beyondrep.in/privacy');

/// Opens [uri] outside the app; returns false when nothing could open it.
typedef PrivacyPolicyOpener = Future<bool> Function(Uri uri);

Future<bool> _openInBrowser(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// A "Privacy policy" link for the sign-in and Account screens.
class PrivacyPolicyLink extends StatelessWidget {
  const PrivacyPolicyLink({this.open = _openInBrowser, super.key});

  final PrivacyPolicyOpener open;

  Future<void> _open(BuildContext context) async {
    bool opened;
    try {
      opened = await open(privacyPolicyUrl);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      showNsMessage(
        context,
        'Could not open a browser. Visit beyondrep.in/privacy.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _open(context),
      icon: const Icon(Icons.privacy_tip_outlined),
      label: const Text('Privacy policy'),
    );
  }
}
