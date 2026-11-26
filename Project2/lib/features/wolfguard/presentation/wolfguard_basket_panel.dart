import 'dart:async';

import 'package:flutter/material.dart';

import 'wolfguard_candidate_sheet.dart';
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

/// Loads evidence-safe candidates for one affected basket line.
typedef WolfGuardLoadCandidatesCallback =
    Future<List<WolfGuardReplacementCandidateViewData>> Function(
      WolfGuardLineViewData line,
    );

/// Creates a repair preview using the shopper's selected candidate.
typedef WolfGuardPrepareReplacementFixCallback =
    Future<WolfGuardFixPlanViewData?> Function(
      WolfGuardLineViewData line,
      WolfGuardReplacementCandidateViewData candidate,
    );

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
    this.onLoadCandidates,
    this.onPrepareReplacementFix,
    this.onApplyFix,
    this.onRepairApplied,
  }) : assert(
         (onLoadCandidates == null) == (onPrepareReplacementFix == null),
         'Candidate loading and replacement planning must be supplied together.',
       );

  final WolfGuardReportViewData report;
  final VoidCallback? onRetry;
  final WolfGuardPrepareFixCallback? onPrepareFix;
  final WolfGuardLoadCandidatesCallback? onLoadCandidates;
  final WolfGuardPrepareReplacementFixCallback? onPrepareReplacementFix;
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
      onLineAction: !_canHandleLineAction
          ? null
          : (line) {
              Navigator.of(context).pop();
              unawaited(_handleLineAction(context, line));
            },
    );
  }

  bool get _canHandleLineAction =>
      onApplyFix != null &&
      (onPrepareFix != null ||
          (onLoadCandidates != null && onPrepareReplacementFix != null));

  Future<void> _handleLineAction(
    BuildContext context,
    WolfGuardLineViewData line,
  ) async {
    final WolfGuardFixPlanViewData? plan;
    if (onLoadCandidates != null && onPrepareReplacementFix != null) {
      final candidate = await showWolfGuardCandidateSheet(
        context,
        productName: line.productName,
        loadCandidates: () => onLoadCandidates!(line),
      );
      if (!context.mounted || candidate == null) return;
      plan = await onPrepareReplacementFix!(line, candidate);
    } else {
      plan = await onPrepareFix!(line);
    }
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
    final resolvedPlan = plan;

    final applied = await showWolfGuardFixSheet(
      context,
      plan: resolvedPlan,
      onApply: () => onApplyFix!(resolvedPlan.planId),
    );
    if (applied == true) onRepairApplied?.call();
  }
}
