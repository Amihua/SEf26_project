import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_checkout_coordinator.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_display_models.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_handoff_dialog.dart';

WolfGuardReportViewData _report({bool ready = false}) {
  final summary = ready
      ? WolfGuardSummaryViewData.fromCounts(
          totalUnits: 1,
          coveredUnits: 1,
          selfPayUnits: 0,
          blockedUnits: 0,
          unknownUnits: 0,
        )
      : WolfGuardSummaryViewData.fromCounts(
          totalUnits: 2,
          coveredUnits: 1,
          selfPayUnits: 0,
          blockedUnits: 0,
          unknownUnits: 1,
        );
  return WolfGuardReportViewData(
    summary: summary,
    lines: [
      WolfGuardLineViewData(
        lineKey: 'line-1',
        productName: ready ? 'Approved Cereal' : 'Unverified Cereal',
        status: ready
            ? WolfGuardLineStatus.covered
            : WolfGuardLineStatus.unknown,
        quantity: 1,
        coveredUnits: ready ? 1 : 0,
        selfPayUnits: 0,
        blockedUnits: 0,
        unknownUnits: ready ? 0 : 1,
      ),
    ],
  );
}

Widget _host(
  WolfGuardReportViewData report,
  ValueChanged<WolfGuardHandoffDecision> onDecision,
  VoidCallback onProceed,
) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: TextButton(
        onPressed: () async => onDecision(
          await coordinateWolfGuardCheckout(
            context,
            report: report,
            onProceed: onProceed,
          ),
        ),
        child: const Text('Ready to Checkout'),
      ),
    ),
  ),
);

Future<void> _scrollToCancel(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Cancel'),
    180,
    scrollable: find.byType(Scrollable),
  );
  await tester.pump();
}

void main() {
  testWidgets('reviewed basket preserves immediate checkout navigation', (
    tester,
  ) async {
    var proceeds = 0;
    WolfGuardHandoffDecision? decision;
    await tester.pumpWidget(
      _host(
        _report(ready: true),
        (value) => decision = value,
        () => proceeds++,
      ),
    );

    await tester.tap(find.text('Ready to Checkout'));
    await tester.pump();
    expect(proceeds, 1);
    expect(decision, WolfGuardHandoffDecision.proceed);
    expect(find.text('Review before checkout'), findsNothing);
  });

  testWidgets('cancel leaves checkout navigation untouched', (tester) async {
    var proceeds = 0;
    WolfGuardHandoffDecision? decision;
    await tester.pumpWidget(
      _host(_report(), (value) => decision = value, () => proceeds++),
    );

    await tester.tap(find.text('Ready to Checkout'));
    await tester.pumpAndSettle();
    await _scrollToCancel(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(proceeds, 0);
    expect(decision, WolfGuardHandoffDecision.cancel);
  });

  testWidgets('review choice opens item report without navigating', (
    tester,
  ) async {
    var proceeds = 0;
    WolfGuardHandoffDecision? decision;
    await tester.pumpWidget(
      _host(_report(), (value) => decision = value, () => proceeds++),
    );

    await tester.tap(find.text('Ready to Checkout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review report'));
    await tester.pumpAndSettle();

    expect(find.text('WolfGuard checkout preflight'), findsOneWidget);
    expect(find.text('Unverified Cereal'), findsOneWidget);
    expect(proceeds, 0);

    await tester.tap(find.byTooltip('Close WolfGuard report'));
    await tester.pumpAndSettle();
    expect(decision, WolfGuardHandoffDecision.review);
  });

  testWidgets('explicit acknowledgement permits one navigation', (
    tester,
  ) async {
    var proceeds = 0;
    WolfGuardHandoffDecision? decision;
    await tester.pumpWidget(
      _host(_report(), (value) => decision = value, () => proceeds++),
    );

    await tester.tap(find.text('Ready to Checkout'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Continue anyway'));
    await tester.pumpAndSettle();

    expect(proceeds, 1);
    expect(decision, WolfGuardHandoffDecision.proceed);
  });

  testWidgets('error state cannot silently navigate as reviewed', (
    tester,
  ) async {
    var proceeds = 0;
    await tester.pumpWidget(
      _host(
        const WolfGuardReportViewData(
          summary: WolfGuardSummaryViewData.error('No evidence'),
          lines: [],
        ),
        (_) {},
        () => proceeds++,
      ),
    );

    await tester.tap(find.text('Ready to Checkout'));
    await tester.pumpAndSettle();
    expect(find.text('Review before checkout'), findsOneWidget);
    expect(proceeds, 0);
  });
}
