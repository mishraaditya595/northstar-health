import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/page_header.dart';
import '../application/health_summary_controller.dart';
import '../data/health_reader.dart';
import '../domain/metric_explanations.dart';
import '../widgets/metric_info_sheet.dart';

/// Every health metric explained in one list, A to Z.
class HealthTermsPage extends ConsumerWidget {
  const HealthTermsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = switch (ref.watch(healthSummaryProvider).value) {
      HealthConnected(:final platform) ||
      HealthNotConnected(:final platform) => platform,
      null =>
        defaultTargetPlatform == TargetPlatform.iOS
            ? HealthPlatformKind.appleHealth
            : HealthPlatformKind.healthConnect,
    };
    final terms =
        [
          for (final key in MetricKey.values)
            (key: key, copy: explanationFor(key, platform)),
        ]..sort(
          (a, b) =>
              a.copy.title.toLowerCase().compareTo(b.copy.title.toLowerCase()),
        );
    return Scaffold(
      appBar: AppBar(
        leading: NsBackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/health'),
        ),
        title: const Text('Health terms'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          for (final t in terms) ...[
            NsListCard(
              icon: Icons.menu_book_outlined,
              title: t.copy.title,
              subtitle: t.copy.summary,
              onTap: () => showMetricInfo(
                context,
                t.key,
                platform: platform,
                showTermsLink: false,
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
