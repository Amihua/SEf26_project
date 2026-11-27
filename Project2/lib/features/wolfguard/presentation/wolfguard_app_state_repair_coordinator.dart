import '../domain/wolfguard_models.dart';
import '../domain/wolfguard_ports.dart';
import '../engine/checkout_preflight_engine.dart';
import '../repair/fix_plan_applier.dart';
import '../repair/fix_planner.dart';
import 'wolfguard_app_state_report_source.dart';
import 'wolfguard_display_models.dart';
import 'wolfguard_domain_mapper.dart';

/// Connects the existing repair preview UI to M2's planner and atomic applier.
///
/// Candidate-backed replacement plans are intentionally not invented here.
/// Until an M3 [CandidateProvider] is injected, the planner receives no
/// candidates and proposes only repairs that are safe without catalog search.
class WolfGuardAppStateRepairCoordinator {
  WolfGuardAppStateRepairCoordinator({
    required this.source,
    FixPlanner? planner,
    FixPlanApplier? applier,
  }) : _planner =
           planner ?? WolfGuardFixPlanner(const CheckoutPreflightEngine()),
       _applier =
           applier ??
           WolfGuardFixPlanApplier(
             target: source.state,
             snapshot: source.snapshotWithLatestEvidence,
           );

  final WolfGuardAppStateReportSource source;
  final FixPlanner _planner;
  final FixPlanApplier _applier;
  final Map<String, FixPlan> _plans = {};

  /// Creates a preview from the most recently completed live analysis.
  ///
  /// Returns null when analysis has not completed or M2 cannot safely propose
  /// an action for the selected line. Preparing a new plan invalidates older
  /// presentation handles; M2 still performs its own fingerprint check when
  /// the shopper confirms.
  Future<WolfGuardFixPlanViewData?> prepare(
    WolfGuardLineViewData selectedLine,
  ) async {
    final request = source.latestRequest;
    final report = source.latestReport;
    if (request == null || report == null) return null;
    if (request.lines.every((line) => line.lineKey != selectedLine.lineKey)) {
      return null;
    }

    final plan = _planner.propose(
      request: request,
      report: report,
      candidatesByLine: const {},
    );
    if (plan.actions.every(
      (action) => action.lineKey != selectedLine.lineKey,
    )) {
      return null;
    }

    _plans
      ..clear()
      ..[plan.planId] = plan;
    return WolfGuardDomainMapper.fixPlan(plan);
  }

  /// Atomically applies a plan previously returned by [prepare].
  Future<WolfGuardApplyViewOutcome> apply(String planId) async {
    final plan = _plans[planId];
    if (plan == null) return WolfGuardApplyViewOutcome.stalePlan;

    final result = await _applier.apply(plan);
    if (result != ApplyPlanResult.persistenceFailed) {
      _plans.remove(planId);
    }
    return WolfGuardDomainMapper.applyOutcome(result);
  }
}
