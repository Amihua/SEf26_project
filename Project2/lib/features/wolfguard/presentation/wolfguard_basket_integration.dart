import 'package:flutter/material.dart';

import 'wolfguard_basket_panel.dart';
import 'wolfguard_checkout_coordinator.dart';
import 'wolfguard_display_models.dart';
import 'wolfguard_live_controller.dart';
import 'wolfguard_rehearsal_screen.dart';

/// Optional WolfGuard dependencies injected into the inherited basket screen.
///
/// The screen owns only presentation placement and navigation. Domain analysis,
/// repair, catalog access, and state mutation remain behind these callbacks.
class WolfGuardBasketIntegration {
  const WolfGuardBasketIntegration({
    required this.controller,
    this.onPrepareFix,
    this.onLoadCandidates,
    this.onPrepareReplacementFix,
    this.onApplyFix,
    this.onRepairApplied,
    this.rehearsalDriver,
  });

  final WolfGuardLiveController controller;
  final WolfGuardPrepareFixCallback? onPrepareFix;
  final WolfGuardLoadCandidatesCallback? onLoadCandidates;
  final WolfGuardPrepareReplacementFixCallback? onPrepareReplacementFix;
  final WolfGuardApplyPlanCallback? onApplyFix;
  final VoidCallback? onRepairApplied;
  final WolfGuardRehearsalDriver? rehearsalDriver;

  /// Builds the reactive panel shown alongside inherited basket actions.
  Widget buildPanel() {
    return WolfGuardLiveBasketPanel(
      controller: controller,
      onPrepareFix: onPrepareFix,
      onLoadCandidates: onLoadCandidates,
      onPrepareReplacementFix: onPrepareReplacementFix,
      onApplyFix: onApplyFix,
      onRepairApplied: onRepairApplied,
    );
  }

  /// Applies the safe handoff rules before invoking inherited QR navigation.
  Future<void> checkout(BuildContext context, VoidCallback onProceed) async {
    final currentReport = controller.report;
    await coordinateWolfGuardCheckout(
      context,
      report: WolfGuardReportViewData(
        summary: controller.summary,
        lines: currentReport?.lines ?? const [],
      ),
      onProceed: onProceed,
    );
  }

  /// Opens the isolated rehearsal when a production fixture driver is present.
  Future<void> openRehearsal(BuildContext context) async {
    final driver = rehearsalDriver;
    if (driver == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WolfGuardRehearsalScreen(driver: driver),
      ),
    );
  }
}
