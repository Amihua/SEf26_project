import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_card.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_display_models.dart';

Widget _app(
  WolfGuardSummaryViewData data, {
  VoidCallback? review,
  VoidCallback? retry,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: WolfGuardCard(data: data, onReview: review, onRetry: retry),
      ),
    ),
  );
}

void main() {
  testWidgets('empty basket explains when preflight starts', (tester) async {
    await tester.pumpWidget(
      _app(
        WolfGuardSummaryViewData.fromCounts(
          totalUnits: 0,
          coveredUnits: 0,
          selfPayUnits: 0,
          blockedUnits: 0,
          unknownUnits: 0,
        ),
      ),
    );

    expect(find.text('WolfGuard checkout preflight'), findsOneWidget);
    expect(find.textContaining('Add products'), findsOneWidget);
    expect(find.text('Review with WolfGuard'), findsNothing);
  });

  testWidgets('loading state has progress and no review action', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const WolfGuardSummaryViewData.loading()));

    expect(find.text('Checking basket'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Review with WolfGuard'), findsNothing);
  });

  testWidgets('ready state shows all outcome counts', (tester) async {
    await tester.pumpWidget(
      _app(
        WolfGuardSummaryViewData.fromCounts(
          totalUnits: 3,
          coveredUnits: 2,
          selfPayUnits: 1,
          blockedUnits: 0,
          unknownUnits: 0,
          selfPayAcknowledged: true,
        ),
      ),
    );

    expect(find.text('Checkout preflight reviewed'), findsOneWidget);
    expect(find.text('Covered 2'), findsOneWidget);
    expect(find.text('Self-paid 1'), findsOneWidget);
    expect(find.text('Blocked 0'), findsOneWidget);
    expect(find.text('Unknown 0'), findsOneWidget);
  });

  testWidgets('blocked units keep card in attention state', (tester) async {
    await tester.pumpWidget(
      _app(
        WolfGuardSummaryViewData.fromCounts(
          totalUnits: 2,
          coveredUnits: 1,
          selfPayUnits: 0,
          blockedUnits: 1,
          unknownUnits: 0,
        ),
      ),
    );

    expect(find.text('Basket needs review'), findsOneWidget);
    expect(find.text('Blocked 1'), findsOneWidget);
  });

  testWidgets('unknown units are never presented as ready', (tester) async {
    final data = WolfGuardSummaryViewData.fromCounts(
      totalUnits: 1,
      coveredUnits: 0,
      selfPayUnits: 0,
      blockedUnits: 0,
      unknownUnits: 1,
    );
    await tester.pumpWidget(_app(data));

    expect(data.readyForHandoff, isFalse);
    expect(find.text('Basket needs review'), findsOneWidget);
    expect(find.text('Unknown 1'), findsOneWidget);
  });

  testWidgets('unacknowledged self-pay requires review', (tester) async {
    final data = WolfGuardSummaryViewData.fromCounts(
      totalUnits: 1,
      coveredUnits: 0,
      selfPayUnits: 1,
      blockedUnits: 0,
      unknownUnits: 0,
    );
    await tester.pumpWidget(_app(data));

    expect(data.readyForHandoff, isFalse);
    expect(find.text('Basket needs review'), findsOneWidget);
  });

  testWidgets('review button invokes callback once', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _app(
        WolfGuardSummaryViewData.fromCounts(
          totalUnits: 1,
          coveredUnits: 1,
          selfPayUnits: 0,
          blockedUnits: 0,
          unknownUnits: 0,
        ),
        review: () => calls++,
      ),
    );

    await tester.tap(find.text('Review with WolfGuard'));
    expect(calls, 1);
  });

  testWidgets('error state shows message and retry callback', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _app(
        const WolfGuardSummaryViewData.error('Evidence service unavailable.'),
        retry: () => calls++,
      ),
    );

    expect(find.text('Could not check basket'), findsOneWidget);
    expect(find.text('Evidence service unavailable.'), findsOneWidget);
    await tester.tap(find.text('Retry preflight'));
    expect(calls, 1);
  });

  testWidgets('semantics describe status without relying on color', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        WolfGuardSummaryViewData.fromCounts(
          totalUnits: 2,
          coveredUnits: 1,
          selfPayUnits: 0,
          blockedUnits: 0,
          unknownUnits: 1,
        ),
      ),
    );

    expect(
      find.bySemanticsLabel(
        'WolfGuard checkout preflight needs review. '
        '1 covered, 0 self-paid, 0 blocked, 1 unknown.',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('narrow screen and large text remain overflow-free', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _app(
          WolfGuardSummaryViewData.fromCounts(
            totalUnits: 8,
            coveredUnits: 3,
            selfPayUnits: 1,
            blockedUnits: 2,
            unknownUnits: 2,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Review with WolfGuard'), findsOneWidget);
  });
}
