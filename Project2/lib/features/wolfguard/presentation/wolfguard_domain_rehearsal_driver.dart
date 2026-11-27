import '../domain/wolfguard_models.dart';
import '../domain/wolfguard_ports.dart';
import '../engine/checkout_preflight_engine.dart';
import '../engine/preflight_request_builder.dart';
import '../repair/fix_plan_applier.dart';
import '../repair/fix_planner.dart';
import 'wolfguard_display_models.dart';
import 'wolfguard_domain_mapper.dart';
import 'wolfguard_rehearsal_screen.dart';

/// Deterministic offline rehearsal powered by the production M1/M2 classes.
///
/// The data is synthetic and isolated, but analysis, planning, application,
/// and presentation mapping are the same implementations used by the live
/// basket. No Firebase, camera, credentials, or signed-in [AppState] is read.
class WolfGuardDomainRehearsalDriver implements WolfGuardRehearsalDriver {
  WolfGuardDomainRehearsalDriver({
    PreflightAnalyzer analyzer = const CheckoutPreflightEngine(),
    FixPlanner? planner,
  }) : _analyzer = analyzer,
       _planner = planner ?? WolfGuardFixPlanner(analyzer),
       _target = _RehearsalTarget.initial() {
    _applier = WolfGuardFixPlanApplier(target: _target, snapshot: _snapshot);
  }

  final PreflightAnalyzer _analyzer;
  final FixPlanner _planner;
  final _RehearsalTarget _target;
  late final FixPlanApplier _applier;
  PreflightRequest? _latestRequest;
  PreflightReport? _latestReport;
  FixPlan? _latestPlan;

  @override
  Future<WolfGuardReportViewData> loadReport() async {
    final request = _snapshot();
    final report = _analyzer.analyze(request);
    _latestRequest = request;
    _latestReport = report;
    return WolfGuardDomainMapper.report(request, report);
  }

  @override
  Future<WolfGuardFixPlanViewData?> planFor(WolfGuardLineViewData line) async {
    final request = _latestRequest;
    final report = _latestReport;
    if (request == null || report == null) return null;
    final plan = _planner.propose(
      request: request,
      report: report,
      candidatesByLine: const {},
    );
    if (plan.actions.every((action) => action.lineKey != line.lineKey)) {
      return null;
    }
    _latestPlan = plan;
    return WolfGuardDomainMapper.fixPlan(plan);
  }

  @override
  Future<WolfGuardApplyViewOutcome> apply(WolfGuardFixPlanViewData plan) async {
    final domainPlan = _latestPlan;
    if (domainPlan == null || domainPlan.planId != plan.planId) {
      return WolfGuardApplyViewOutcome.stalePlan;
    }
    final result = await _applier.apply(domainPlan);
    if (result != ApplyPlanResult.persistenceFailed) _latestPlan = null;
    return WolfGuardDomainMapper.applyOutcome(result);
  }

  PreflightRequest _snapshot() {
    final base = PreflightRequestBuilder.fromAppState(
      basket: [
        for (final line in _target.basket) Map<String, Object?>.from(line),
      ],
      balances: {
        for (final entry in _target.balances.entries)
          entry.key: Map<String, Object?>.from(entry.value),
      },
      evaluatedAt: DateTime.utc(2026, 11, 27),
      evidenceByUpc: _evidence,
    );
    final benefits = Map<String, BenefitCategorySnapshot>.from(base.benefits);
    final cereal = benefits['BREAKFAST CEREAL'];
    if (cereal != null) {
      benefits['BREAKFAST CEREAL'] = BenefitCategorySnapshot(
        category: cereal.category,
        allowed: cereal.allowed,
        used: cereal.used,
        freshness: cereal.freshness,
        permittedPackageSize: const PackageAmount(18, 'oz'),
      );
    }
    return PreflightRequest(
      lines: base.lines,
      benefits: benefits,
      evaluatedAt: base.evaluatedAt,
    );
  }

  static const Map<String, ProductEvidence> _evidence = {
    'synthetic-milk': ProductEvidence(
      aplEligible: true,
      canonicalCategory: 'MILK',
      freshness: EvidenceFreshness.current,
      sourceLabel: 'Synthetic current APL evidence',
    ),
    'synthetic-eggs': ProductEvidence(
      aplEligible: true,
      canonicalCategory: 'EGGS',
      freshness: EvidenceFreshness.current,
      sourceLabel: 'Synthetic current APL evidence',
    ),
    'synthetic-cereal-24': ProductEvidence(
      aplEligible: true,
      canonicalCategory: 'BREAKFAST CEREAL',
      packageSize: PackageAmount(24, 'oz'),
      freshness: EvidenceFreshness.current,
      sourceLabel: 'Synthetic explicit package evidence',
    ),
  };
}

class _RehearsalTarget implements RepairTarget {
  _RehearsalTarget._({required this.basket, required this.balances});

  factory _RehearsalTarget.initial() => _RehearsalTarget._(
    basket: [
      {
        'upc': 'synthetic-milk',
        'name': 'Synthetic covered milk',
        'category': 'MILK',
        'original_benefit_category': 'MILK',
        'qty': 1,
      },
      {
        'upc': 'synthetic-eggs',
        'name': 'Synthetic self-paid eggs',
        'category': wolfGuardPaidCategory,
        'original_benefit_category': 'EGGS',
        'qty': 1,
      },
      {
        'upc': 'synthetic-cereal-24',
        'name': 'Synthetic blocked cereal',
        'category': 'BREAKFAST CEREAL',
        'original_benefit_category': 'BREAKFAST CEREAL',
        'qty': 1,
      },
      {
        'upc': 'synthetic-juice',
        'name': 'Synthetic unknown juice',
        'category': 'JUICE',
        'original_benefit_category': 'JUICE',
        'qty': 1,
      },
    ],
    balances: {
      'MILK': {'allowed': 2, 'used': 1},
      'EGGS': {'allowed': 2, 'used': 0},
      'BREAKFAST CEREAL': {'allowed': 2, 'used': 1},
      'JUICE': {'allowed': 2, 'used': 1},
      wolfGuardPaidCategory: {'allowed': null, 'used': 1},
    },
  );

  @override
  final List<Map<String, dynamic>> basket;

  @override
  Map<String, Map<String, dynamic>> balances;

  @override
  Future<bool> commitWolfGuardRepair({
    required List<Map<String, dynamic>> basket,
    required Map<String, Map<String, dynamic>> balances,
  }) async {
    this.basket
      ..clear()
      ..addAll(basket);
    this.balances = balances;
    return true;
  }
}
