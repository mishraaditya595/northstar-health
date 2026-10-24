import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Feature code must reuse the shared kit in `lib/core/design/` (see
/// docs/DESIGN_SYSTEM.md "Shared Flutter components"). Raw Material inputs,
/// dialogs, sheets, chips and snackbars are only allowed inside the kit.
void main() {
  test('features use the shared design kit, not raw Material controls', () {
    const forbidden = {
      'TextField(': 'NsTextField',
      'TextFormField(': 'NsTextField',
      'DropdownButton<': 'NsDropdown',
      'DropdownButtonFormField<': 'NsDropdown',
      'AlertDialog(': 'NsDialog / showNsConfirm',
      'showDialog<': 'showNsDialog / showNsConfirm',
      'showDialog(': 'showNsDialog / showNsConfirm',
      'showModalBottomSheet': 'showNsSheet',
      'ChoiceChip(': 'NsChip',
      'FilterChip(': 'NsChip',
      'SnackBar(': 'showNsMessage',
      'ScaffoldMessenger': 'showNsMessage',
    };
    final offences = <String>[];
    for (final file in Directory('lib/features').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//') || line.startsWith('///')) continue;
        forbidden.forEach((token, use) {
          // Whole identifier only, so NsTextField( is not a TextField( hit.
          if (RegExp('(?<![A-Za-z0-9_])${RegExp.escape(token)}')
              .hasMatch(line)) {
            offences.add('${file.path}:${i + 1} uses $token — use $use');
          }
        });
      }
    }
    expect(offences, isEmpty, reason: offences.join('\n'));
  });
}
