import 'wolfguard_display_models.dart';
import 'wolfguard_rehearsal_screen.dart';

/// Deterministic presentation fixture for the offline WolfGuard walkthrough.
///
/// This driver is deliberately labeled synthetic. It does not query Firebase,
/// read signed-in state, or claim to replace the production analyzer/planner
/// adapter that will be wired after the shared M1–M3 contracts merge.
class WolfGuardSyntheticRehearsalDriver implements WolfGuardRehearsalDriver {
  bool _repaired = false;

  static const String _planId = 'synthetic-rehearsal-plan-v1';

  @override
  Future<WolfGuardReportViewData> loadReport() async {
    return _repaired ? _repairedReport() : _initialReport();
  }

  @override
  Future<WolfGuardFixPlanViewData?> planFor(WolfGuardLineViewData line) async {
    if (_repaired || line.lineKey != 'synthetic-blocked-cereal') return null;
    return WolfGuardFixPlanViewData(
      planId: _planId,
      before: _initialSummary(),
      projectedAfter: _repairedSummary(),
      actions: const [
        WolfGuardFixActionViewData(
          title: 'Use synthetic cereal replacement',
          description:
              'Replace the blocked fixture line with a same-category sample.',
        ),
        WolfGuardFixActionViewData(
          title: 'Keep synthetic juice self-paid',
          description:
              'Do not claim the fixture with unknown package evidence as covered.',
        ),
      ],
    );
  }

  @override
  Future<WolfGuardApplyViewOutcome> apply(WolfGuardFixPlanViewData plan) async {
    if (_repaired || plan.planId != _planId) {
      return WolfGuardApplyViewOutcome.stalePlan;
    }
    _repaired = true;
    return WolfGuardApplyViewOutcome.applied;
  }

  WolfGuardReportViewData _initialReport() => WolfGuardReportViewData(
    summary: _initialSummary(),
    lines: const [
      WolfGuardLineViewData(
        lineKey: 'synthetic-covered-milk',
        productName: 'Synthetic covered milk',
        status: WolfGuardLineStatus.covered,
        quantity: 1,
        coveredUnits: 1,
        selfPayUnits: 0,
        blockedUnits: 0,
        unknownUnits: 0,
      ),
      WolfGuardLineViewData(
        lineKey: 'synthetic-self-paid-eggs',
        productName: 'Synthetic self-paid eggs',
        status: WolfGuardLineStatus.selfPay,
        quantity: 1,
        coveredUnits: 0,
        selfPayUnits: 1,
        blockedUnits: 0,
        unknownUnits: 0,
        issues: [
          WolfGuardIssueViewData(
            title: 'Application allowance already allocated',
            explanation: 'This fixture unit is intentionally self-paid.',
            suggestedNextStep: 'Confirm the self-paid choice before checkout.',
            evidenceLabels: ['synthetic fixture allowance'],
          ),
        ],
      ),
      WolfGuardLineViewData(
        lineKey: 'synthetic-blocked-cereal',
        productName: 'Synthetic blocked cereal',
        status: WolfGuardLineStatus.blocked,
        quantity: 1,
        coveredUnits: 0,
        selfPayUnits: 0,
        blockedUnits: 1,
        unknownUnits: 0,
        issues: [
          WolfGuardIssueViewData(
            title: 'Synthetic category mismatch',
            explanation: 'The fixture starts with one actionable blocked line.',
            suggestedNextStep: 'Preview the two-action sample repair.',
            evidenceLabels: ['synthetic fixture category'],
          ),
        ],
        actionLabel: 'Preview sample repair',
      ),
      WolfGuardLineViewData(
        lineKey: 'synthetic-unknown-juice',
        productName: 'Synthetic unknown juice',
        status: WolfGuardLineStatus.unknown,
        quantity: 1,
        coveredUnits: 0,
        selfPayUnits: 0,
        blockedUnits: 0,
        unknownUnits: 1,
        issues: [
          WolfGuardIssueViewData(
            title: 'Synthetic package evidence missing',
            explanation:
                'The fixture intentionally provides no comparable package size.',
            suggestedNextStep: 'Keep the unit self-paid instead of guessing.',
            evidenceLabels: ['synthetic fixture: size unknown'],
          ),
        ],
      ),
    ],
  );

  WolfGuardReportViewData _repairedReport() => WolfGuardReportViewData(
    summary: _repairedSummary(),
    lines: const [
      WolfGuardLineViewData(
        lineKey: 'synthetic-covered-milk',
        productName: 'Synthetic covered milk',
        status: WolfGuardLineStatus.covered,
        quantity: 1,
        coveredUnits: 1,
        selfPayUnits: 0,
        blockedUnits: 0,
        unknownUnits: 0,
      ),
      WolfGuardLineViewData(
        lineKey: 'synthetic-self-paid-eggs',
        productName: 'Synthetic self-paid eggs',
        status: WolfGuardLineStatus.selfPay,
        quantity: 1,
        coveredUnits: 0,
        selfPayUnits: 1,
        blockedUnits: 0,
        unknownUnits: 0,
      ),
      WolfGuardLineViewData(
        lineKey: 'synthetic-replacement-cereal',
        productName: 'Synthetic replacement cereal',
        status: WolfGuardLineStatus.covered,
        quantity: 1,
        coveredUnits: 1,
        selfPayUnits: 0,
        blockedUnits: 0,
        unknownUnits: 0,
      ),
      WolfGuardLineViewData(
        lineKey: 'synthetic-self-paid-juice',
        productName: 'Synthetic self-paid juice',
        status: WolfGuardLineStatus.selfPay,
        quantity: 1,
        coveredUnits: 0,
        selfPayUnits: 1,
        blockedUnits: 0,
        unknownUnits: 0,
      ),
    ],
  );

  WolfGuardSummaryViewData _initialSummary() =>
      WolfGuardSummaryViewData.fromCounts(
        totalUnits: 4,
        coveredUnits: 1,
        selfPayUnits: 1,
        blockedUnits: 1,
        unknownUnits: 1,
      );

  WolfGuardSummaryViewData _repairedSummary() =>
      WolfGuardSummaryViewData.fromCounts(
        totalUnits: 4,
        coveredUnits: 2,
        selfPayUnits: 2,
        blockedUnits: 0,
        unknownUnits: 0,
        selfPayAcknowledged: true,
      );
}
