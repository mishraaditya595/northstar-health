import 'package:flutter/material.dart';

import '../../../core/design/page_header.dart';

/// Stand-in for the Sleep, Heart, Activity and Body detail screens until
/// they are built (Tasks 14-15).
class HealthDetailPlaceholderPage extends StatelessWidget {
  const HealthDetailPlaceholderPage({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const NsBackButton(), title: Text(title)),
    );
  }
}
