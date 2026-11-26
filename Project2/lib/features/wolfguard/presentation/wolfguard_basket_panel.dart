import 'dart:async';

import 'package:flutter/material.dart';

import 'wolfguard_card.dart';
import 'wolfguard_display_models.dart';
import 'wolfguard_fix_sheet.dart';
import 'wolfguard_report_sheet.dart';

/// Creates a repair preview for the selected report line.
typedef WolfGuardPrepareFixCallback =
    Future<WolfGuardFixPlanViewData?> Function(WolfGuardLineViewData line);

/// Applies the identified repair plan through the integration adapter.
typedef WolfGuardApplyPlanCallback =
    Future<WolfGuardApplyViewOutcome> Function(String planId);

/// Presentation coordinator embedded by the inherited basket screen.
///
/// Business analysis and basket mutation remain behind injected callbacks so
/// this widget can be exercised without Firebase or concrete state classes.
class WolfGuardBasketPanel extends StatelessWidget {
  const WolfGuardBasketPanel({
    super.key,
    required this.report,
    this.onRetry,
    this.onPrepareFix,
    this.onApplyFix,
    this.onRepairApplied,
  });

  final WolfGuardReportViewData report;
  final VoidCallback? onRetry;
  final WolfGuardPrepareFixCallback? onPrepareFix;
  final WolfGuardApplyPlanCallback? onApplyFix;
  final VoidCallback? onRepairApplied;

  @override
  Widget build(BuildContext context) {
    return WolfGuardCard(
      data: report.summary,
      onRetry: onRetry,
      onReview: () => _openReport(context),
    );
  }

  Future<void> _openReport(BuildContext context) {
    return showWolfGuardReportSheet(
      context,
      report: report,
      onLineAction: onPrepareFix == null || onApplyFix == null
          ? null
          : (line) {
              Navigator.of(context).pop();
              unawaited(_prepareAndOpenFix(context, line));
            },
    );
  }

  Future<void> _prepareAndOpenFix(
    BuildContext context,
    WolfGuardLineViewData line,
  ) async {
    final plan = await onPrepareFix!(line);
    if (!context.mounted) return;

    if (plan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No safe repair preview is available for this item yet.',
          ),
        ),
      );
      return;
    }

    final applied = await showWolfGuardFixSheet(
      context,
      plan: plan,
      onApply: () => onApplyFix!(plan.planId),
    );
    if (applied == true) onRepairApplied?.call();
  }
}
