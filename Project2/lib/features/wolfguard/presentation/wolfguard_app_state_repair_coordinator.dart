import '../domain/wolfguard_models.dart';
import '../domain/wolfguard_ports.dart';
import '../engine/checkout_preflight_engine.dart';
import '../engine/preflight_rules.dart';
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
    CandidateProvider? candidateProvider,
  }) : _planner =
           planner ?? WolfGuardFixPlanner(const CheckoutPreflightEngine()),
       _applier =
           applier ??
           WolfGuardFixPlanApplier(
             target: source.state,
             snapshot: source.snapshotWithLatestEvidence,
           ),
       _candidateProvider = candidateProvider;

  final WolfGuardAppStateReportSource source;
  final FixPlanner _planner;
  final FixPlanApplier _applier;
  final CandidateProvider? _candidateProvider;
  final Map<String, FixPlan> _plans = {};
  final Map<String, _CandidateLookup> _candidateLookups = {};

  /// Whether the production composition supplied an M3 catalog provider.
  bool get supportsCandidates => _candidateProvider != null;

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

  /// Loads M3 candidates for one line and maps only explicit package matches.
  ///
  /// Provider failures and stale basket reads propagate to the candidate
  /// sheet, which renders its retryable unavailable state. The original
  /// domain candidates are cached for planning; presentation data is never
  /// reverse-mapped into a trusted replacement.
  Future<List<WolfGuardReplacementCandidateViewData>> loadCandidates(
    WolfGuardLineViewData selectedLine,
  ) async {
    final provider = _candidateProvider;
    if (provider == null) {
      throw StateError('WolfGuard candidate provider is unavailable.');
    }
    final request = source.latestRequest;
    if (request == null) {
      throw StateError('WolfGuard analysis has not completed.');
    }
    final line = _lineFor(request, selectedLine.lineKey);
    if (line == null) {
      throw StateError('The selected basket line is no longer available.');
    }

    final candidates = await provider.findFor(line: line);
    if (source.snapshotWithLatestEvidence().fingerprint !=
        request.fingerprint) {
      throw StateError('The basket changed during candidate lookup.');
    }

    final byUpc = <String, ReplacementCandidate>{};
    for (final candidate in candidates) {
      byUpc.putIfAbsent(candidate.upc, () => candidate);
    }
    final unique = List<ReplacementCandidate>.unmodifiable(byUpc.values);
    _candidateLookups[selectedLine.lineKey] = _CandidateLookup(
      requestFingerprint: request.fingerprint,
      byUpc: Map.unmodifiable(byUpc),
    );
    return WolfGuardDomainMapper.candidates(
      unique,
      permittedPackageSize: _permittedPackageSize(request, line),
    );
  }

  /// Creates an M2 preview using exactly the M3 candidate selected in the UI.
  Future<WolfGuardFixPlanViewData?> prepareReplacement(
    WolfGuardLineViewData selectedLine,
    WolfGuardReplacementCandidateViewData selectedCandidate,
  ) async {
    final request = source.latestRequest;
    final report = source.latestReport;
    final lookup = _candidateLookups[selectedLine.lineKey];
    if (request == null ||
        report == null ||
        lookup == null ||
        lookup.requestFingerprint != request.fingerprint ||
        source.snapshotWithLatestEvidence().fingerprint !=
            request.fingerprint) {
      return null;
    }
    final line = _lineFor(request, selectedLine.lineKey);
    final candidate = lookup.byUpc[selectedCandidate.upc];
    if (line == null || candidate == null) return null;

    final plan = _planner.propose(
      request: request,
      report: report,
      candidatesByLine: {
        selectedLine.lineKey: [candidate],
      },
    );
    final selectedReplacement = plan.actions.any(
      (action) =>
          action.lineKey == selectedLine.lineKey &&
          action.kind == FixKind.replaceProduct &&
          action.replacement == candidate,
    );
    if (!selectedReplacement) return null;

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

  BasketLineSnapshot? _lineFor(PreflightRequest request, String lineKey) {
    for (final line in request.lines) {
      if (line.lineKey == lineKey) return line;
    }
    return null;
  }

  PackageAmount? _permittedPackageSize(
    PreflightRequest request,
    BasketLineSnapshot line,
  ) {
    final category = PreflightCategories.benefitCategory(
      line.originalBenefitCategory ?? line.basketCategory,
    );
    return category == null
        ? null
        : request.benefits[category]?.permittedPackageSize;
  }
}

final class _CandidateLookup {
  const _CandidateLookup({
    required this.requestFingerprint,
    required this.byUpc,
  });

  final String requestFingerprint;
  final Map<String, ReplacementCandidate> byUpc;
}
