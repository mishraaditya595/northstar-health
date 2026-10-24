import 'package:flutter/widgets.dart';

/// `showDialog` completes on pop, but the exit animation keeps rebuilding the
/// dialog's fields; disposing at that point throws "used after being disposed".
void disposeAfterDialog(List<TextEditingController> controllers) {
  Future<void>.delayed(const Duration(milliseconds: 300), () {
    for (final c in controllers) {
      c.dispose();
    }
  });
}
