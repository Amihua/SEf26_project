import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_display_models.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_rehearsal_screen.dart';

class _FakeDriver implements WolfGuardRehearsalDriver {
  _FakeDriver({this.loadError = false, this.hasPlan = true});

  bool loadError;
  bool hasPlan;
  int loadCalls = 0;
  int planCalls = 0;
  int applyCalls = 0;
  bool repaired = false;

  @override
  Future<WolfGuardReportViewData> loadReport() async {
    loadCalls++;
    if (loadError) throw StateError('fixture unavailable');
    final summary = repaired
        ? WolfGuardSummaryViewData.fromCounts(
            totalUnits: 1,
            coveredUnits: 1,
            selfPayUnits: 0,
            blockedUnits: 0,
            unknownUnits: 0,
          )
        : WolfGuardSummaryViewData.fromCounts(
            totalUnits: 1,
            coveredUnits: 0,
            selfPayUnits: 0,
            blockedUnits: 1,
            unknownUnits: 0,
          );
    return WolfGuardReportViewData(
      summary: summary,
      lines: [
        WolfGuardLineViewData(
          lineKey: 'sample-cereal',
          productName: 'Synthetic cereal',
          status: repaired
              ? WolfGuardLineStatus.covered
              : WolfGuardLineStatus.blocked,
          quantity: 1,
          coveredUnits: repaired ? 1 : 0,
          selfPayUnits: 0,
          blockedUnits: repaired ? 0 : 1,
          unknownUnits: 0,
          issues: repaired
              ? const []
              : const [
                  WolfGuardIssueViewData(
                    title: 'Synthetic allowance issue',
                    explanation: 'This fixture starts with one blocked unit.',
                    suggestedNextStep: 'Preview the fixture repair.',
                    evidenceLabels: ['synthetic fixture'],
                  ),
                ],
          actionLabel: repaired ? null : 'Preview sample repair',
        ),
      ],
    );
  }

  @override
  Future<WolfGuardFixPlanViewData?> planFor(WolfGuardLineViewData line) async {
    planCalls++;
    if (!hasPlan) return null;
    return WolfGuardFixPlanViewData(
      planId: 'sample-plan',
      before: WolfGuardSummaryViewData.fromCounts(
        totalUnits: 1,
        coveredUnits: 0,
        selfPayUnits: 0,
        blockedUnits: 1,
        unknownUnits: 0,
      ),
      projectedAfter: WolfGuardSummaryViewData.fromCounts(
        totalUnits: 1,
        coveredUnits: 1,
        selfPayUnits: 0,
        blockedUnits: 0,
        unknownUnits: 0,
      ),
      actions: const [
        WolfGuardFixActionViewData(
          title: 'Use sample replacement',
          description: 'Replace the blocked fixture product.',
        ),
      ],
    );
  }

  @override
  Future<WolfGuardApplyViewOutcome> apply(WolfGuardFixPlanViewData plan) async {
    applyCalls++;
    repaired = true;
    return WolfGuardApplyViewOutcome.applied;
  }
}

Widget _app(_FakeDriver driver) =>
    MaterialApp(home: WolfGuardRehearsalScreen(driver: driver));

Future<void> _openRepair(WidgetTester tester) async {
  await tester.tap(find.text('Review with WolfGuard'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('Preview sample repair'),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(find.text('Preview sample repair'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('screen clearly labels synthetic isolated data', (tester) async {
    await tester.pumpWidget(_app(_FakeDriver()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Synthetic sample'), findsOneWidget);
    expect(find.textContaining('not live benefits'), findsOneWidget);
    expect(
      find.textContaining('without changing your shopping basket'),
      findsOneWidget,
    );
  });

  testWidgets('loaded rehearsal shows attention summary', (tester) async {
    final driver = _FakeDriver();
    await tester.pumpWidget(_app(driver));
    await tester.pumpAndSettle();

    expect(driver.loadCalls, 1);
    expect(find.text('Basket needs review'), findsOneWidget);
    expect(find.text('Blocked 1'), findsOneWidget);
  });

  testWidgets('review opens the fixture item report', (tester) async {
    await tester.pumpWidget(_app(_FakeDriver()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review with WolfGuard'));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic cereal'), findsOneWidget);
    expect(find.text('Synthetic allowance issue'), findsOneWidget);
  });

  testWidgets('line action opens repair preview', (tester) async {
    final driver = _FakeDriver();
    await tester.pumpWidget(_app(driver));
    await tester.pumpAndSettle();

    await _openRepair(tester);
    expect(driver.planCalls, 1);
    expect(find.text('Preview basket repair'), findsOneWidget);
    expect(find.text('Use sample replacement'), findsOneWidget);
  });

  testWidgets('cancel preview does not call apply', (tester) async {
    final driver = _FakeDriver();
    await tester.pumpWidget(_app(driver));
    await tester.pumpAndSettle();

    await _openRepair(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(driver.applyCalls, 0);
    expect(find.text('Basket needs review'), findsOneWidget);
  });

  testWidgets('apply refreshes rehearsal with repaired report', (tester) async {
    final driver = _FakeDriver();
    await tester.pumpWidget(_app(driver));
    await tester.pumpAndSettle();

    await _openRepair(tester);
    await tester.tap(find.text('Apply repairs'));
    await tester.pumpAndSettle();

    expect(driver.applyCalls, 1);
    expect(driver.loadCalls, 2);
    expect(find.text('Checkout preflight reviewed'), findsOneWidget);
    expect(find.text('Covered 1'), findsOneWidget);
  });

  testWidgets('missing repair explains that no safe plan exists', (
    tester,
  ) async {
    final driver = _FakeDriver(hasPlan: false);
    await tester.pumpWidget(_app(driver));
    await tester.pumpAndSettle();

    await _openRepair(tester);
    expect(find.textContaining('No safe repair is available'), findsOneWidget);
    expect(driver.applyCalls, 0);
  });

  testWidgets('load error can retry without leaving the screen', (
    tester,
  ) async {
    final driver = _FakeDriver(loadError: true);
    await tester.pumpWidget(_app(driver));
    await tester.pumpAndSettle();

    expect(find.text('Could not check basket'), findsOneWidget);
    driver.loadError = false;
    await tester.tap(find.text('Retry preflight'));
    await tester.pumpAndSettle();

    expect(driver.loadCalls, 2);
    expect(find.text('Basket needs review'), findsOneWidget);
  });
}
