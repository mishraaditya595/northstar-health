import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/design/northstar_theme.dart';
import 'features/account/account_auth_controller.dart';
import 'features/account/account_gate.dart';

/// Only public client settings are provided at build time. Never accept or
/// embed service_role / secret keys, database passwords or personal tokens.
/// These values are public in a distributed Flutter binary, so database RLS
/// and authenticated server-side authorization remain mandatory.
const _url = String.fromEnvironment('SUPABASE_URL');
const _publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _AuthBootstrap());
}

class _AuthBootstrap extends StatefulWidget {
  const _AuthBootstrap();

  @override
  State<_AuthBootstrap> createState() => _AuthBootstrapState();
}

class _AuthBootstrapState extends State<_AuthBootstrap> {
  AccountAuthController? _controller;
  late Future<AccountAuthController> _opening = _initialize();

  Future<AccountAuthController> _initialize() async {
    final uri = Uri.tryParse(_url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        !_publishableKey.startsWith('sb_publishable_')) {
      throw const FormatException(
        'A public Supabase URL and publishable key are required.',
      );
    }
    await Supabase.initialize(
      url: _url,
      publishableKey: _publishableKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: NorthstarSecureSessionStorage(projectHost: uri.host),
        // Email codes are verified in-app; unexpected auth deep links must
        // never switch the JWT while another account's ObjectBox is open.
        detectSessionInUri: false,
      ),
    );

    final controller = AccountAuthController(
      SupabaseAccountAuthApi(Supabase.instance.client),
      SecureBoundAccountStore(projectHost: uri.host),
    );
    await controller.restore();
    _controller = controller;
    return controller;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AccountAuthController>(
    future: _opening,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return AccountGate(
          controller: snapshot.requireData,
          authenticatedBuilder: (accountId) => BoundAccountWorkoutApp(
            key: ValueKey(accountId),
            accountId: accountId,
            projectHost: Uri.parse(_url).host,
            controller: snapshot.requireData,
          ),
        );
      }
      return MaterialApp(
        title: 'Northstar Health',
        theme: NorthstarTheme.build(Brightness.light),
        darkTheme: NorthstarTheme.build(Brightness.dark),
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: snapshot.hasError
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline, size: 44),
                          const SizedBox(height: 16),
                          const Text(
                            'NorthStar authentication is unavailable. '
                            'Check the public build configuration and '
                            'secure storage setup. Workout data is locked.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          // Secure storage reads can fail transiently, e.g.
                          // before the first unlock after a reboot.
                          FilledButton(
                            onPressed: () =>
                                setState(() => _opening = _initialize()),
                            child: const Text('Retry'),
                          ),
                        ],
                      )
                    : const CircularProgressIndicator(),
              ),
            ),
          ),
        ),
      );
    },
  );
}
