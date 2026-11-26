import 'package:flutter/material.dart';

import 'wolfguard_display_models.dart';
import 'wolfguard_handoff_dialog.dart';
import 'wolfguard_report_sheet.dart';

/// Runs the WolfGuard review step before the inherited checkout navigation.
///
/// The callback is invoked only when a reviewed basket can proceed immediately
/// or the shopper explicitly acknowledges the prototype limitation. Review and
/// cancel paths never mutate the basket or invoke checkout navigation.
Future<WolfGuardHandoffDecision> coordinateWolfGuardCheckout(
  BuildContext context, {
  required WolfGuardReportViewData report,
  required VoidCallback onProceed,
}) async {
  final decision = await requestWolfGuardHandoff(
    context,
    summary: report.summary,
  );
  if (!context.mounted) return decision;

  switch (decision) {
    case WolfGuardHandoffDecision.proceed:
      onProceed();
    case WolfGuardHandoffDecision.review:
      await showWolfGuardReportSheet(context, report: report);
    case WolfGuardHandoffDecision.cancel:
      break;
  }
  return decision;
}
