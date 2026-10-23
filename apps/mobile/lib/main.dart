import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/northstar_app.dart';
import 'core/storage/objectbox_store_provider.dart';
import 'objectbox.g.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _StorageBootstrap());
}

class _StorageBootstrap extends StatefulWidget {
  const _StorageBootstrap();

  @override
  State<_StorageBootstrap> createState() => _StorageBootstrapState();
}

class _StorageBootstrapState extends State<_StorageBootstrap> {
  late Future<Store> _opening = _open();

  Future<Store> _open() async {
    try {
      return await initializeObjectBox();
    } catch (error) {
      // Deliberately log only the exception type. No workout values, file
      // paths, or raw DB messages are sent to logs or telemetry.
      debugPrint('Local workout storage unavailable: ${error.runtimeType}');
      rethrow;
    }
  }

  void _retry() => setState(() => _opening = _open());

  @override
  Widget build(BuildContext context) => FutureBuilder<Store>(
    future: _opening,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return ProviderScope(
          overrides: [
            objectBoxStoreProvider.overrideWithValue(snapshot.requireData),
          ],
          child: const NorthstarApp(),
        );
      }
      return MaterialApp(
        title: 'Northstar Health',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF316946)),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFD6FF60),
            brightness: Brightness.dark,
          ),
        ),
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: snapshot.hasError
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.storage_rounded, size: 44),
                          const SizedBox(height: 16),
                          const Text(
                            'Could not open your local workout data. '
                            'Your database has not been reset.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _retry,
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
