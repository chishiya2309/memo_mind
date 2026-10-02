import 'package:flutter/material.dart';

import '../application/statistics_controller.dart';
import 'statistics_panel.dart';

/// Tab body; the home shell supplies navigation and SafeArea.
class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({
    super.key,
    required this.controller,
    required this.onOpenDueCards,
  });
  final StatisticsController? controller;
  final Future<void> Function() onOpenDueCards;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async => controller?.refresh(),
    child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: StatisticsPanel(
            controller: controller,
            onOpenDueCards: onOpenDueCards,
          ),
        ),
      ),
    ),
  );
}
