import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_display_models.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_report_sheet.dart';

const _issue = WolfGuardIssueViewData(
  title: 'Allowance exceeded',
  explanation: 'One unit does not fit the saved cereal allowance.',
  suggestedNextStep: 'Reduce the quantity or keep the extra unit self-paid.',
  evidenceLabels: ['basket quantity', 'saved allowance'],
);

WolfGuardReportViewData _report() {
  return WolfGuardReportViewData(
    summary: WolfGuardSummaryViewData.fromCounts(
      totalUnits: 4,
      coveredUnits: 1,
      selfPayUnits: 1,
      blockedUnits: 1,
      unknownUnits: 1,
      selfPayAcknowledged: true,
    ),
    lines: const [
      WolfGuardLineViewData(
        lineKey: '0:111:CEREAL',
        productName: 'Covered cereal',
        status: WolfGuardLineStatus.covered,
        quantity: 1,
        coveredUnits: 1,
        selfPayUnits: 0,
        blockedUnits: 0,
        unknownUnits: 0,
      ),
      WolfGuardLineViewData(
        lineKey: '1:111:PAID',
        productName: 'Extra cereal',
        status: WolfGuardLineStatus.selfPay,
        quantity: 1,
        coveredUnits: 0,
        selfPayUnits: 1,
        blockedUnits: 0,
        unknownUnits: 0,
        issues: [_issue],
        actionLabel: 'Review self-pay',
      ),
      WolfGuardLineViewData(
        lineKey: '2:222:CEREAL',
        productName: 'Blocked cereal',
        status: WolfGuardLineStatus.blocked,
        quantity: 1,
        coveredUnits: 0,
        selfPayUnits: 0,
        blockedUnits: 1,
        unknownUnits: 0,
        issues: [_issue],
        actionLabel: 'Plan a repair',
      ),
      WolfGuardLineViewData(
        lineKey: '3:333:UNKNOWN',
        productName: 'Unverified item',
        status: WolfGuardLineStatus.unknown,
        quantity: 1,
        coveredUnits: 0,
        selfPayUnits: 0,
        blockedUnits: 0,
        unknownUnits: 1,
        issues: [
          WolfGuardIssueViewData(
            title: 'Not enough evidence',
            explanation: 'The category could not be verified.',
            suggestedNextStep: 'Check current benefit information.',
          ),
        ],
        actionLabel: 'Review evidence',
      ),
    ],
  );
}

Widget _app({ValueChanged<WolfGuardLineViewData>? onAction}) {
  return MaterialApp(
    home: Scaffold(
      body: WolfGuardReportSheet(report: _report(), onLineAction: onAction),
    ),
  );
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable),
  );
  await tester.pump();
}

void main() {
  testWidgets('report shows aggregate counts and every product', (
    tester,
  ) async {
    await tester.pumpWidget(_app());

    expect(find.text('Covered 1'), findsOneWidget);
    expect(find.text('Self-paid 1'), findsOneWidget);
    expect(find.text('Blocked 1'), findsOneWidget);
    expect(find.text('Unknown 1'), findsOneWidget);
    expect(find.text('Covered cereal'), findsOneWidget);
    await _scrollTo(tester, find.text('Unverified item'));
    expect(find.text('Unverified item'), findsOneWidget);
  });

  testWidgets('status is written as text rather than color only', (
    tester,
  ) async {
    await tester.pumpWidget(_app());

    expect(find.text('Expected covered · quantity 1'), findsOneWidget);
    await _scrollTo(tester, find.text('Self-paid · quantity 1'));
    expect(find.text('Self-paid · quantity 1'), findsOneWidget);
    await _scrollTo(tester, find.text('Blocked · quantity 1'));
    expect(find.text('Blocked · quantity 1'), findsOneWidget);
    await _scrollTo(tester, find.text('Unknown · quantity 1'));
    expect(find.text('Unknown · quantity 1'), findsOneWidget);
  });

  testWidgets('issue includes explanation next step and evidence', (
    tester,
  ) async {
    await tester.pumpWidget(_app());

    expect(find.text('Allowance exceeded'), findsWidgets);
    expect(find.textContaining('Next step: Reduce'), findsWidgets);
    expect(
      find.text('Evidence: basket quantity, saved allowance'),
      findsWidgets,
    );
  });

  testWidgets('unknown issue is explicit and conservative', (tester) async {
    await tester.pumpWidget(_app());

    await _scrollTo(tester, find.text('Not enough evidence'));
    expect(find.text('Not enough evidence'), findsOneWidget);
    expect(find.text('The category could not be verified.'), findsOneWidget);
    expect(
      find.textContaining('Unknown means WolfGuard cannot'),
      findsOneWidget,
    );
  });

  testWidgets('line action returns the selected line', (tester) async {
    WolfGuardLineViewData? selected;
    await tester.pumpWidget(_app(onAction: (line) => selected = line));

    await _scrollTo(tester, find.text('Plan a repair'));
    await tester.tap(find.text('Plan a repair'));
    expect(selected?.lineKey, '2:222:CEREAL');
  });

  testWidgets('covered item has no action button', (tester) async {
    await tester.pumpWidget(_app());

    final coveredCard = find.byKey(
      const ValueKey('wolfguard-line-0:111:CEREAL'),
    );
    expect(coveredCard, findsOneWidget);
    expect(
      find.descendant(of: coveredCard, matching: find.byType(OutlinedButton)),
      findsNothing,
    );
  });

  testWidgets('close control dismisses a modal report', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showWolfGuardReportSheet(context, report: _report()),
              child: const Text('Open report'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open report'));
    await tester.pumpAndSettle();
    expect(find.text('WolfGuard checkout preflight'), findsOneWidget);

    await tester.tap(find.byTooltip('Close WolfGuard report'));
    await tester.pumpAndSettle();
    expect(find.text('WolfGuard checkout preflight'), findsNothing);
  });

  testWidgets('narrow large-text report remains scrollable and overflow-free', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _app(),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsOneWidget);
    await tester.flingFrom(const Offset(160, 500), const Offset(0, -500), 800);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
