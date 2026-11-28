import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/dialogs.dart';
import '../../../core/design/inputs.dart';
import '../application/health_overview.dart';
import '../application/weight_logger.dart';
import '../data/health_weight_writer.dart';

String _storeName(bool ios) => ios ? 'Apple Health' : 'Health Connect';

/// Opens the Log weight sheet. A saved weight shows "Saved to ..." with Undo
/// on the page's messenger, so the message outlives the sheet.
Future<void> showLogWeightSheet(BuildContext context, WidgetRef ref) async {
  final logger = ref.read(weightLoggerProvider);
  final messenger = nsMessengerOf(context);
  final section = ref.read(healthOverviewProvider).value?.body;
  final latest = switch (section) {
    SectionData(:final value) => value.weight?.value,
    _ => null,
  };
  final saved = await showNsSheet<SavedWeight>(
    context,
    heightFactor: 0.5,
    // Dragging down would close the sheet and lose Undo while a save runs.
    enableDrag: false,
    builder: (_) => _LogWeightSheet(
      logger: logger,
      initial: latest?.toStringAsFixed(1) ?? '',
    ),
  );
  if (saved == null) return;
  final store = _storeName(logger.isIos);
  showNsMessageOn(
    messenger,
    'Saved to $store',
    actionLabel: 'Undo',
    onAction: () async {
      final removed = await logger.undo(saved);
      if (removed) return;
      showNsMessageOn(
        messenger,
        "Couldn't remove it. Delete it in "
        '${logger.isIos ? 'the Health app' : 'Health Connect'}.',
      );
    },
  );
}

class _LogWeightSheet extends StatefulWidget {
  const _LogWeightSheet({required this.logger, required this.initial});

  final WeightLogger logger;
  final String initial;

  @override
  State<_LogWeightSheet> createState() => _LogWeightSheetState();
}

class _LogWeightSheetState extends State<_LogWeightSheet> {
  late final _controller = TextEditingController(text: widget.initial);
  bool _saving = false;
  String? _error;
  bool _denied = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
      _denied = false;
    });
    final result = await widget.logger.save(_controller.text);
    if (!mounted) return;
    final store = _storeName(widget.logger.isIos);
    switch (result) {
      case WeightSaved(:final saved):
        Navigator.of(context).pop(saved);
        return;
      case WeightInvalid():
        _error = 'Enter a weight between 20 and 400 kg';
      case WeightDenied():
        _error = 'Allow BeyondRep to write weight in Settings';
        _denied = true;
      case WeightSaveFailed():
        _error = "Couldn't save to $store. Try again.";
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;
    return PopScope(
      canPop: !_saving,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          24 +
              MediaQuery.paddingOf(context).bottom +
              MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: [
          Semantics(
            header: true,
            child: Text(
              'Log weight',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 16),
          NsTextField(
            controller: _controller,
            label: 'Weight (kg)',
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onSubmitted: (_) => _save(),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
          if (_denied) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: widget.logger.openSettings,
              child: const Text('Open Settings'),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
