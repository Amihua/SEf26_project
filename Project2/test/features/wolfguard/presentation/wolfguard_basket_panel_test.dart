import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_basket_panel.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_display_models.dart';

WolfGuardSummaryViewData _summary({int covered = 1, int blocked = 1}) =>
    WolfGuardSummaryViewData.fromCounts(
      totalUnits: covered + blocked,
      coveredUnits: covered,
      selfPayUnits: 0,
      blockedUnits: blocked,
      unknownUnits: 0,
    );

WolfGuardLineViewData _blockedLine() => const WolfGuardLineViewData(
  lineKey: 'milk-line',
  productName: 'Whole Milk',
  status: WolfGuardLineStatus.blocked,
  quantity: 1,
  coveredUnits: 0,
  selfPayUnits: 0,
  blockedUnits: 1,
  unknownUnits: 0,
  actionLabel: 'Preview repair',
  issues: [
    WolfGuardIssueViewData(
      title: 'Allowance exceeded',
      explanation: 'No application-managed allowance remains.',
      suggestedNextStep: 'Reduce, remove, or keep this unit self-paid.',
    ),
  ],
);

WolfGuardReportViewData _report() =>
    WolfGuardReportViewData(summary: _summary(), lines: [_blockedLine()]);

WolfGuardFixPlanViewData _plan() => WolfGuardFixPlanViewData(
  planId: 'plan-7',
  before: _summary(),
  projectedAfter: _summary(covered: 1, blocked: 0),
  actions: const [
    WolfGuardFixActionViewData(
      title: 'Remove Whole Milk',
      description: 'Remove one blocked unit from the basket.',
    ),
  ],
);

const _candidate = WolfGuardReplacementCandidateViewData(
  upc: '007070707070',
  name: 'Replacement Milk',
  canonicalCategory: 'Milk',
  evidenceLabel: 'NC APL exact UPC',
  packageMatch: WolfGuardPackageMatchView.unknown,
);

Widget _host(WolfGuardBasketPanel panel) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: panel)),
);

Future<void> _openRepair(WidgetTester tester) async {
  await tester.tap(find.text('Review with WolfGuard'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Preview repair'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('card opens the complete report', (tester) async {
    await tester.pumpWidget(_host(WolfGuardBasketPanel(report: _report())));

    expect(find.text('Basket needs review'), findsOneWidget);
    await tester.tap(find.text('Review with WolfGuard'));
    await tester.pumpAndSettle();

    expect(find.text('WolfGuard checkout preflight'), findsOneWidget);
    expect(find.text('Whole Milk'), findsOneWidget);
    expect(find.text('Allowance exceeded'), findsOneWidget);
  });

  testWidgets('selected line becomes an applyable repair preview', (
    tester,
  ) async {
    WolfGuardLineViewData? preparedLine;
    String? appliedPlanId;
    var refreshes = 0;
    await tester.pumpWidget(
      _host(
        WolfGuardBasketPanel(
          report: _report(),
          onPrepareFix: (line) async {
            preparedLine = line;
            return _plan();
          },
          onApplyFix: (planId) async {
            appliedPlanId = planId;
            return WolfGuardApplyViewOutcome.applied;
          },
          onRepairApplied: () => refreshes++,
        ),
      ),
    );

    await _openRepair(tester);
    expect(preparedLine?.lineKey, 'milk-line');
    expect(find.text('Preview basket repair'), findsOneWidget);

    await tester.tap(find.text('Apply repairs'));
    await tester.pumpAndSettle();
    expect(appliedPlanId, 'plan-7');
    expect(refreshes, 1);
  });

  testWidgets('missing repair plan produces an honest unavailable message', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        WolfGuardBasketPanel(
          report: _report(),
          onPrepareFix: (_) async => null,
          onApplyFix: (_) async => WolfGuardApplyViewOutcome.applied,
        ),
      ),
    );

    await _openRepair(tester);
    expect(
      find.text('No safe repair preview is available for this item yet.'),
      findsOneWidget,
    );
    expect(find.text('Preview basket repair'), findsNothing);
  });

  testWidgets('cancelling a preview never applies or reports success', (
    tester,
  ) async {
    var applies = 0;
    var refreshes = 0;
    await tester.pumpWidget(
      _host(
        WolfGuardBasketPanel(
          report: _report(),
          onPrepareFix: (_) async => _plan(),
          onApplyFix: (_) async {
            applies++;
            return WolfGuardApplyViewOutcome.applied;
          },
          onRepairApplied: () => refreshes++,
        ),
      ),
    );

    await _openRepair(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(applies, 0);
    expect(refreshes, 0);
  });

  testWidgets('error card forwards retry to the integration adapter', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      _host(
        WolfGuardBasketPanel(
          report: const WolfGuardReportViewData(
            summary: WolfGuardSummaryViewData.error('Temporary failure'),
            lines: [],
          ),
          onRetry: () => retries++,
        ),
      ),
    );

    await tester.tap(find.text('Retry preflight'));
    expect(retries, 1);
  });

  testWidgets('replacement flow selects evidence before creating preview', (
    tester,
  ) async {
    WolfGuardLineViewData? requestedLine;
    WolfGuardReplacementCandidateViewData? selectedCandidate;
    await tester.pumpWidget(
      _host(
        WolfGuardBasketPanel(
          report: _report(),
          onLoadCandidates: (line) async {
            requestedLine = line;
            return const [_candidate];
          },
          onPrepareReplacementFix: (line, candidate) async {
            selectedCandidate = candidate;
            return _plan();
          },
          onApplyFix: (_) async => WolfGuardApplyViewOutcome.applied,
        ),
      ),
    );

    await tester.tap(find.text('Review with WolfGuard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview repair'));
    await tester.pumpAndSettle();
    expect(requestedLine?.lineKey, 'milk-line');
    expect(find.text('Replacement Milk'), findsOneWidget);

    await tester.tap(find.text('Use in repair preview'));
    await tester.pumpAndSettle();
    expect(selectedCandidate?.upc, '007070707070');
    expect(find.text('Preview basket repair'), findsOneWidget);
  });

  testWidgets('closing replacement search is a planner no-op', (tester) async {
    var plans = 0;
    var applies = 0;
    await tester.pumpWidget(
      _host(
        WolfGuardBasketPanel(
          report: _report(),
          onLoadCandidates: (_) async => const [_candidate],
          onPrepareReplacementFix: (_, _) async {
            plans++;
            return _plan();
          },
          onApplyFix: (_) async {
            applies++;
            return WolfGuardApplyViewOutcome.applied;
          },
        ),
      ),
    );

    await tester.tap(find.text('Review with WolfGuard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview repair'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close replacement search'));
    await tester.pumpAndSettle();

    expect(plans, 0);
    expect(applies, 0);
    expect(find.text('Preview basket repair'), findsNothing);
  });
}
