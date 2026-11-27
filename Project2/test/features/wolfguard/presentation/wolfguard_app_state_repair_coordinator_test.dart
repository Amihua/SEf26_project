import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/domain/wolfguard_models.dart';
import 'package:wolfbite/features/wolfguard/domain/wolfguard_ports.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_app_state_repair_coordinator.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_app_state_report_source.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_display_models.dart';
import 'package:wolfbite/state/app_state.dart';

class _RepairableAppState extends AppState {
  _RepairableAppState() : super(db: FakeFirebaseFirestore());

  @override
  Future<bool> commitWolfGuardRepair({
    required List<Map<String, dynamic>> basket,
    required Map<String, Map<String, dynamic>> balances,
  }) async {
    this.basket
      ..clear()
      ..addAll(basket);
    this.balances = balances;
    notifyListeners();
    return true;
  }
}

class _RecordingApplier implements FixPlanApplier {
  _RecordingApplier(this.result);

  final ApplyPlanResult result;
  FixPlan? received;

  @override
  Future<ApplyPlanResult> apply(FixPlan plan) async {
    received = plan;
    return result;
  }
}

class _CandidateProvider implements CandidateProvider {
  _CandidateProvider(this.response);

  final Future<List<ReplacementCandidate>> Function(BasketLineSnapshot line)
  response;
  BasketLineSnapshot? received;

  @override
  Future<List<ReplacementCandidate>> findFor({
    required BasketLineSnapshot line,
    int max = 5,
  }) async {
    received = line;
    return response(line);
  }
}

const _replacement = ReplacementCandidate(
  upc: '222',
  name: 'Known replacement milk',
  canonicalCategory: 'MILK',
  aplEligible: true,
  freshness: EvidenceFreshness.current,
  evidenceLabel: 'Imported NC APL exact UPC',
);

_RepairableAppState _unknownState() {
  final state = _RepairableAppState();
  state.balances['MILK'] = {'allowed': 2, 'used': 1};
  state.basket.add({
    'upc': '111',
    'name': 'Unknown milk',
    'category': 'MILK',
    'qty': 1,
  });
  return state;
}

Future<(WolfGuardAppStateReportSource, WolfGuardReportViewData)> _analyze(
  AppState state, {
  bool? eligibility,
}) async {
  final source = WolfGuardAppStateReportSource(
    state: state,
    aplLookup: (_) async => eligibility != null
        ? {
            'upc': '111',
            'name': 'Known milk',
            'category': 'MILK',
            'eligible': eligibility,
          }
        : null,
    now: () => DateTime.utc(2026, 11, 27),
  );
  return (source, await source.analyze());
}

void main() {
  test('unknown line previews conservative self-pay repair', () async {
    final (source, report) = await _analyze(_unknownState());
    final coordinator = WolfGuardAppStateRepairCoordinator(source: source);

    final plan = await coordinator.prepare(report.lines.single);

    expect(plan, isNotNull);
    expect(plan!.before.unknownUnits, 1);
    expect(plan.projectedAfter.unknownUnits, 0);
    expect(plan.projectedAfter.selfPayUnits, 1);
    expect(plan.actions.single.title, 'Keep item self-paid');
  });

  test(
    'real M2 applier commits a confirmed repair through state port',
    () async {
      final state = _unknownState();
      final (source, report) = await _analyze(state);
      final coordinator = WolfGuardAppStateRepairCoordinator(source: source);
      final plan = await coordinator.prepare(report.lines.single);

      final outcome = await coordinator.apply(plan!.planId);

      expect(outcome, WolfGuardApplyViewOutcome.applied);
      expect(state.basket.single['category'], 'PAID');
      expect(state.basket.single['original_benefit_category'], 'MILK');
      expect(state.balances['MILK']!['used'], 0);
      expect(state.balances['PAID']!['used'], 1);
    },
  );

  test('live mutation after preview is rejected as stale', () async {
    final state = _unknownState();
    final (source, report) = await _analyze(state);
    final coordinator = WolfGuardAppStateRepairCoordinator(source: source);
    final plan = await coordinator.prepare(report.lines.single);
    state.basket.single['qty'] = 2;

    final outcome = await coordinator.apply(plan!.planId);

    expect(outcome, WolfGuardApplyViewOutcome.stalePlan);
    expect(state.basket.single['category'], 'MILK');
    expect(state.basket.single['qty'], 2);
  });

  test('unknown presentation plan id never reaches the applier', () async {
    final state = _unknownState();
    final (source, _) = await _analyze(state);
    final applier = _RecordingApplier(ApplyPlanResult.applied);
    final coordinator = WolfGuardAppStateRepairCoordinator(
      source: source,
      applier: applier,
    );

    expect(
      await coordinator.apply('missing-plan'),
      WolfGuardApplyViewOutcome.stalePlan,
    );
    expect(applier.received, isNull);
  });

  test('every M2 failure is returned to the confirmation sheet', () async {
    for (final result in [
      ApplyPlanResult.stalePlan,
      ApplyPlanResult.unsupportedAction,
      ApplyPlanResult.persistenceFailed,
    ]) {
      final state = _unknownState();
      final (source, report) = await _analyze(state);
      final applier = _RecordingApplier(result);
      final coordinator = WolfGuardAppStateRepairCoordinator(
        source: source,
        applier: applier,
      );
      final plan = await coordinator.prepare(report.lines.single);

      final outcome = await coordinator.apply(plan!.planId);

      expect(outcome.name, result.name);
      expect(applier.received?.planId, plan.planId);
    }
  });

  test('covered line does not invent a repair plan', () async {
    final (source, report) = await _analyze(_unknownState(), eligibility: true);
    final coordinator = WolfGuardAppStateRepairCoordinator(source: source);

    expect(await coordinator.prepare(report.lines.single), isNull);
  });

  test('M3 candidate identity is preserved through the M2 preview', () async {
    final state = _unknownState();
    final (source, report) = await _analyze(state, eligibility: false);
    final provider = _CandidateProvider((_) async => const [_replacement]);
    final applier = _RecordingApplier(ApplyPlanResult.applied);
    final coordinator = WolfGuardAppStateRepairCoordinator(
      source: source,
      candidateProvider: provider,
      applier: applier,
    );

    final candidates = await coordinator.loadCandidates(report.lines.single);
    final plan = await coordinator.prepareReplacement(
      report.lines.single,
      candidates.single,
    );
    final outcome = await coordinator.apply(plan!.planId);

    expect(coordinator.supportsCandidates, isTrue);
    expect(provider.received?.lineKey, report.lines.single.lineKey);
    expect(candidates.single.upc, '222');
    expect(plan.actions.single.title, 'Use eligible replacement');
    expect(outcome, WolfGuardApplyViewOutcome.applied);
    expect(applier.received?.actions.single.replacement, same(_replacement));
  });

  test(
    'candidate source failure propagates for retry without a fake',
    () async {
      final (source, report) = await _analyze(_unknownState());
      final coordinator = WolfGuardAppStateRepairCoordinator(
        source: source,
        candidateProvider: _CandidateProvider(
          (_) async => throw StateError('catalog offline'),
        ),
      );

      await expectLater(
        coordinator.loadCandidates(report.lines.single),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('unknown or stale candidate selection cannot create a plan', () async {
    final state = _unknownState();
    final (source, report) = await _analyze(state);
    final coordinator = WolfGuardAppStateRepairCoordinator(
      source: source,
      candidateProvider: _CandidateProvider((_) async => const [_replacement]),
    );
    final candidates = await coordinator.loadCandidates(report.lines.single);
    const unknown = WolfGuardReplacementCandidateViewData(
      upc: 'not-returned',
      name: 'Invented',
      canonicalCategory: 'MILK',
      evidenceLabel: 'not provider evidence',
      packageMatch: WolfGuardPackageMatchView.unknown,
    );

    expect(
      await coordinator.prepareReplacement(report.lines.single, unknown),
      isNull,
    );

    state.basket.single['qty'] = 2;
    expect(
      await coordinator.prepareReplacement(
        report.lines.single,
        candidates.single,
      ),
      isNull,
    );
  });

  test(
    'missing M3 provider is unavailable rather than an empty result',
    () async {
      final (source, report) = await _analyze(_unknownState());
      final coordinator = WolfGuardAppStateRepairCoordinator(source: source);

      expect(coordinator.supportsCandidates, isFalse);
      await expectLater(
        coordinator.loadCandidates(report.lines.single),
        throwsA(isA<StateError>()),
      );
    },
  );
}
