import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/northstar_app.dart';
import 'core/storage/objectbox_store_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Open the durable store before the UI can acknowledge any future writes.
    // Never delete or recreate user data when opening fails.
    final store = await initializeObjectBox();
    runApp(ProviderScope(
      overrides: [objectBoxStoreProvider.overrideWithValue(store)],
      child: const NorthstarApp(),
    ));
  } catch (_) {
    runApp(const MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Could not open your local workout data. Your data has not '
                'been reset. Restart the app or contact support.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    ));
  }
}
