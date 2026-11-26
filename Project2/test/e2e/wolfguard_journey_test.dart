import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_checkout_coordinator.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_display_models.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_live_controller.dart';

const _candidate = WolfGuardReplacementCandidateViewData(
  upc: '012345678905',
  name: 'Replacement Cereal',
  canonicalCategory: 'Breakfast Cereal',
  evidenceLabel: 'NC APL exact UPC',
  packageMatch: WolfGuardPackageMatchView.unknown,
);

WolfGuardSummaryViewData _riskySummary() => WolfGuardSummaryViewData.fromCounts(
  totalUnits: 4,
  coveredUnits: 1,
  selfPayUnits: 1,
  blockedUnits: 1,
  unknownUnits: 1,
);

WolfGuardSummaryViewData _readySummary() => WolfGuardSummaryViewData.fromCounts(
  totalUnits: 4,
  coveredUnits: 2,
  selfPayUnits: 2,
  blockedUnits: 0,
  unknownUnits: 0,
  selfPayAcknowledged: true,
);

WolfGuardReportViewData _riskyReport() => WolfGuardReportViewData(
  summary: _riskySummary(),
  lines: const [
    WolfGuardLineViewData(
      lineKey: 'covered',
      productName: 'Covered Milk',
      status: WolfGuardLineStatus.covered,
      quantity: 1,
      coveredUnits: 1,
      selfPayUnits: 0,
      blockedUnits: 0,
      unknownUnits: 0,
    ),
    WolfGuardLineViewData(
      lineKey: 'paid',
      productName: 'Self-paid Eggs',
      status: WolfGuardLineStatus.selfPay,
      quantity: 1,
      coveredUnits: 0,
      selfPayUnits: 1,
      blockedUnits: 0,
      unknownUnits: 0,
    ),
    WolfGuardLineViewData(
      lineKey: 'blocked',
      productName: 'Blocked Cereal',
      status: WolfGuardLineStatus.blocked,
      quantity: 1,
      coveredUnits: 0,
      selfPayUnits: 0,
      blockedUnits: 1,
      unknownUnits: 0,
      actionLabel: 'Find replacement',
      issues: [
        WolfGuardIssueViewData(
          title: 'Benefit category mismatch',
          explanation: 'This line needs an evidence-safe replacement.',
          suggestedNextStep: 'Review same-category candidates.',
        ),
      ],
    ),
    WolfGuardLineViewData(
      lineKey: 'unknown',
      productName: 'Unknown Juice',
      status: WolfGuardLineStatus.unknown,
      quantity: 1,
      coveredUnits: 0,
      selfPayUnits: 0,
      blockedUnits: 0,
      unknownUnits: 1,
      issues: [
        WolfGuardIssueViewData(
          title: 'Evidence missing',
          explanation: 'WolfGuard cannot safely classify this package.',
          suggestedNextStep: 'Keep the item self-paid in the proposed plan.',
        ),
      ],
    ),
  ],
);

WolfGuardReportViewData _readyReport() => WolfGuardReportViewData(
  summary: _readySummary(),
  lines: const [
    WolfGuardLineViewData(
      lineKey: 'replacement',
      productName: 'Replacement Cereal',
      status: WolfGuardLineStatus.covered,
      quantity: 1,
      coveredUnits: 1,
      selfPayUnits: 0,
      blockedUnits: 0,
      unknownUnits: 0,
    ),
  ],
);

WolfGuardFixPlanViewData _repairPlan() => WolfGuardFixPlanViewData(
  planId: 'journey-plan',
  before: _riskySummary(),
  projectedAfter: _readySummary(),
  actions: const [
    WolfGuardFixActionViewData(
      title: 'Replace Blocked Cereal',
      description: 'Use the selected same-category APL candidate.',
    ),
    WolfGuardFixActionViewData(
      title: 'Keep Unknown Juice self-paid',
      description: 'Do not claim unknown evidence as covered.',
    ),
  ],
);

class _JourneySource extends ChangeNotifier
    implements WolfGuardLiveReportSource {
  bool repaired = false;
  int analyzeCalls = 0;
  int candidateCalls = 0;
  int planCalls = 0;
  int applyCalls = 0;
  String? selectedUpc;

  @override
  Listenable get basketChanges => this;

  @override
  Future<WolfGuardReportViewData> analyze() async {
    analyzeCalls++;
    return repaired ? _readyReport() : _riskyReport();
  }

  Future<List<WolfGuardReplacementCandidateViewData>> candidates(
    WolfGuardLineViewData line,
  ) async {
    candidateCalls++;
    expect(line.lineKey, 'blocked');
    return const [_candidate];
  }

  Future<WolfGuardFixPlanViewData?> plan(
    WolfGuardLineViewData line,
    WolfGuardReplacementCandidateViewData candidate,
  ) async {
    planCalls++;
    expect(line.lineKey, 'blocked');
    selectedUpc = candidate.upc;
    return _repairPlan();
  }

  Future<WolfGuardApplyViewOutcome> apply(String planId) async {
    applyCalls++;
    expect(planId, 'journey-plan');
    repaired = true;
    return WolfGuardApplyViewOutcome.applied;
  }
}

class _JourneyHost extends StatelessWidget {
  const _JourneyHost({required this.source, required this.controller});

  final _JourneySource source;
  final WolfGuardLiveController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (journeyContext) => Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              WolfGuardLiveBasketPanel(
                controller: controller,
                onLoadCandidates: source.candidates,
                onPrepareReplacementFix: source.plan,
                onApplyFix: source.apply,
              ),
              TextButton(
                onPressed: () async {
                  final report = controller.report;
                  if (report == null) return;
                  await coordinateWolfGuardCheckout(
                    journeyContext,
                    report: report,
                    onProceed: () => Navigator.of(journeyContext).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(
                          body: Center(child: Text('Inherited QR checkout')),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Ready to Checkout'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openRepairPreview(WidgetTester tester) async {
  await tester.tap(find.text('Review with WolfGuard'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('Find replacement'),
    180,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pump();
  await tester.tap(find.text('Find replacement'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Use in repair preview'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('risky basket repairs, recalculates, and reaches checkout', (
    tester,
  ) async {
    final source = _JourneySource();
    final controller = WolfGuardLiveController(source: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _JourneyHost(source: source, controller: controller),
    );
    await tester.pumpAndSettle();

    expect(find.text('Basket needs review'), findsOneWidget);
    expect(find.text('Blocked 1'), findsOneWidget);
    await _openRepairPreview(tester);
    expect(find.text('Preview basket repair'), findsOneWidget);
    expect(source.selectedUpc, '012345678905');

    await tester.tap(find.text('Apply repairs'));
    await tester.pumpAndSettle();
    expect(find.text('Checkout preflight reviewed'), findsOneWidget);
    expect(find.text('Blocked 0'), findsOneWidget);
    expect(source.analyzeCalls, 2);
    expect(source.candidateCalls, 1);
    expect(source.planCalls, 1);
    expect(source.applyCalls, 1);

    await tester.tap(find.text('Ready to Checkout'));
    await tester.pumpAndSettle();
    expect(find.text('Inherited QR checkout'), findsOneWidget);
    expect(find.text('Review before checkout'), findsNothing);
  });

  testWidgets('repair cancel and checkout cancel remain no-ops', (
    tester,
  ) async {
    final source = _JourneySource();
    final controller = WolfGuardLiveController(source: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _JourneyHost(source: source, controller: controller),
    );
    await tester.pumpAndSettle();

    await _openRepairPreview(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(source.applyCalls, 0);
    expect(source.repaired, isFalse);
    expect(find.text('Basket needs review'), findsOneWidget);

    await tester.tap(find.text('Ready to Checkout'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Cancel'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Inherited QR checkout'), findsNothing);
    expect(source.repaired, isFalse);
  });
}
