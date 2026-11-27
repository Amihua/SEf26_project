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
  bool eligible = false,
}) async {
  final source = WolfGuardAppStateReportSource(
    state: state,
    aplLookup: (_) async => eligible
        ? {
            'upc': '111',
            'name': 'Known milk',
            'category': 'MILK',
            'eligible': true,
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
    final (source, report) = await _analyze(_unknownState(), eligible: true);
    final coordinator = WolfGuardAppStateRepairCoordinator(source: source);

    expect(await coordinator.prepare(report.lines.single), isNull);
  });
}
