import '../domain/wolfguard_models.dart';
import '../engine/preflight_rules.dart';
import 'wolfguard_display_models.dart';

/// Maps the shared WolfGuard domain into immutable presentation data.
///
/// This class contains no analysis or repair policy. Counts, statuses,
/// explanations, evidence labels, and apply outcomes are copied from the
/// domain objects owned by M1 and M2.
abstract final class WolfGuardDomainMapper {
  /// Maps one analyzed request and report into the basket UI model.
  static WolfGuardReportViewData report(
    PreflightRequest request,
    PreflightReport report,
  ) {
    final linesByKey = {for (final line in request.lines) line.lineKey: line};
    return WolfGuardReportViewData(
      summary: summary(report),
      lines: [
        for (final result in report.lines)
          _line(result, linesByKey[result.lineKey]),
      ],
    );
  }

  /// Maps aggregate report counts without recalculating them in the UI.
  static WolfGuardSummaryViewData summary(PreflightReport report) {
    return WolfGuardSummaryViewData.fromCounts(
      totalUnits: report.totalUnits,
      coveredUnits: report.coveredUnits,
      selfPayUnits: report.selfPayUnits,
      blockedUnits: report.blockedUnits,
      unknownUnits: report.unknownUnits,
      // M1 emits selfPay only for an explicit PAID basket classification.
      selfPayAcknowledged: true,
    );
  }

  /// Maps a preview returned by M2 into the existing confirmation sheet.
  static WolfGuardFixPlanViewData fixPlan(FixPlan plan) {
    return WolfGuardFixPlanViewData(
      planId: plan.planId,
      before: summary(plan.before),
      projectedAfter: summary(plan.projectedAfter),
      actions: [
        for (final action in plan.actions)
          WolfGuardFixActionViewData(
            title: _actionTitle(action.kind),
            description: action.shopperExplanation,
          ),
      ],
    );
  }

  /// Maps M2's atomic apply result without treating failure as success.
  static WolfGuardApplyViewOutcome applyOutcome(ApplyPlanResult result) {
    return switch (result) {
      ApplyPlanResult.applied => WolfGuardApplyViewOutcome.applied,
      ApplyPlanResult.stalePlan => WolfGuardApplyViewOutcome.stalePlan,
      ApplyPlanResult.unsupportedAction =>
        WolfGuardApplyViewOutcome.unsupportedAction,
      ApplyPlanResult.persistenceFailed =>
        WolfGuardApplyViewOutcome.persistenceFailed,
    };
  }

  /// Maps one M3 catalog candidate without overstating package evidence.
  ///
  /// A candidate is shown as a verified package match only when both explicit
  /// sizes exist and the shared M1 package rule says they match. A known but
  /// different or non-comparable size remains an ordinary same-category
  /// candidate; the UI never infers a match from its name or UPC.
  static WolfGuardReplacementCandidateViewData candidate(
    ReplacementCandidate candidate, {
    required PackageAmount? permittedPackageSize,
  }) {
    final offered = candidate.verifiedPackageSize;
    final packageVerified =
        offered != null &&
        permittedPackageSize != null &&
        PackageRules.compare(offered, permittedPackageSize) ==
            PackageComparison.match;

    return WolfGuardReplacementCandidateViewData(
      upc: candidate.upc,
      name: candidate.name,
      canonicalCategory: candidate.canonicalCategory,
      evidenceLabel: candidate.evidenceLabel,
      packageMatch: packageVerified
          ? WolfGuardPackageMatchView.verified
          : WolfGuardPackageMatchView.unknown,
      packageEvidenceLabel: packageVerified
          ? '${offered.toString()} explicit package evidence'
          : null,
    );
  }

  /// Maps M3 results in provider order and returns an immutable collection.
  static List<WolfGuardReplacementCandidateViewData> candidates(
    Iterable<ReplacementCandidate> candidates, {
    required PackageAmount? permittedPackageSize,
  }) => List.unmodifiable(
    candidates.map(
      (candidate) => WolfGuardDomainMapper.candidate(
        candidate,
        permittedPackageSize: permittedPackageSize,
      ),
    ),
  );

  static WolfGuardLineViewData _line(
    LinePreflightResult result,
    BasketLineSnapshot? source,
  ) {
    final productName = source?.name.trim() ?? '';
    return WolfGuardLineViewData(
      lineKey: result.lineKey,
      productName: productName.isNotEmpty ? productName : 'Basket item',
      status: switch (result.status) {
        PreflightStatus.covered => WolfGuardLineStatus.covered,
        PreflightStatus.selfPay => WolfGuardLineStatus.selfPay,
        PreflightStatus.blocked => WolfGuardLineStatus.blocked,
        PreflightStatus.unknown => WolfGuardLineStatus.unknown,
      },
      quantity: result.quantity,
      coveredUnits: result.coveredUnits,
      selfPayUnits: result.selfPayUnits,
      blockedUnits: result.blockedUnits,
      unknownUnits: result.unknownUnits,
      issues: [
        for (final issue in result.issues)
          WolfGuardIssueViewData(
            title: issue.title,
            explanation: issue.explanation,
            suggestedNextStep: issue.suggestedNextStep,
            evidenceLabels: List.unmodifiable(issue.evidenceLabels),
          ),
      ],
      actionLabel: switch (result.status) {
        PreflightStatus.blocked ||
        PreflightStatus.unknown => 'Preview safe repair',
        PreflightStatus.covered || PreflightStatus.selfPay => null,
      },
    );
  }

  static String _actionTitle(FixKind kind) => switch (kind) {
    FixKind.reduceQuantity => 'Reduce product quantity',
    FixKind.removeLine => 'Remove unreadable item',
    FixKind.keepAsSelfPay => 'Keep item self-paid',
    FixKind.replaceProduct => 'Use eligible replacement',
  };
}
