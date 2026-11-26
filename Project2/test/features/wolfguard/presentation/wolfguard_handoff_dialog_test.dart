import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_display_models.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_handoff_dialog.dart';

Widget _host(
  WolfGuardSummaryViewData summary,
  ValueChanged<WolfGuardHandoffDecision> onDecision,
) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            onDecision(
              await requestWolfGuardHandoff(context, summary: summary),
            );
          },
          child: const Text('Checkout'),
        ),
      ),
    ),
  );
}

WolfGuardSummaryViewData _attention() => WolfGuardSummaryViewData.fromCounts(
  totalUnits: 4,
  coveredUnits: 1,
  selfPayUnits: 1,
  blockedUnits: 1,
  unknownUnits: 1,
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
  testWidgets('reviewed basket proceeds without a dialog', (tester) async {
    WolfGuardHandoffDecision? decision;
    await tester.pumpWidget(
      _host(
        WolfGuardSummaryViewData.fromCounts(
          totalUnits: 2,
          coveredUnits: 2,
          selfPayUnits: 0,
          blockedUnits: 0,
          unknownUnits: 0,
        ),
        (value) => decision = value,
      ),
    );

    await tester.tap(find.text('Checkout'));
    await tester.pump();
    expect(decision, WolfGuardHandoffDecision.proceed);
    expect(find.text('Review before checkout'), findsNothing);
  });

  testWidgets('attention state shows every outcome count', (tester) async {
    await tester.pumpWidget(_host(_attention(), (_) {}));

    await tester.tap(find.text('Checkout'));
    await tester.pumpAndSettle();
    expect(find.text('Review before checkout'), findsOneWidget);
    expect(find.text('Covered 1'), findsOneWidget);
    expect(find.text('Self-paid 1'), findsOneWidget);
    expect(find.text('Blocked 1'), findsOneWidget);
    expect(find.text('Unknown 1'), findsOneWidget);
  });

  testWidgets('cancel returns cancel decision', (tester) async {
    WolfGuardHandoffDecision? decision;
    await tester.pumpWidget(_host(_attention(), (value) => decision = value));

    await tester.tap(find.text('Checkout'));
    await tester.pumpAndSettle();
    await _scrollToCancel(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(decision, WolfGuardHandoffDecision.cancel);
  });

  testWidgets('review button returns review decision', (tester) async {
    WolfGuardHandoffDecision? decision;
    await tester.pumpWidget(_host(_attention(), (value) => decision = value));

    await tester.tap(find.text('Checkout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review report'));
    await tester.pumpAndSettle();
    expect(decision, WolfGuardHandoffDecision.review);
  });

  testWidgets('continue is disabled before explicit acknowledgement', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_attention(), (_) {}));
    await tester.tap(find.text('Checkout'));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue anyway'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('acknowledged shopper can explicitly continue', (tester) async {
    WolfGuardHandoffDecision? decision;
    await tester.pumpWidget(_host(_attention(), (value) => decision = value));
    await tester.tap(find.text('Checkout'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Continue anyway'));
    await tester.pumpAndSettle();
    expect(decision, WolfGuardHandoffDecision.proceed);
  });

  testWidgets('large text dialog remains scrollable and closable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2),
        ),
        child: _host(_attention(), (_) {}),
      ),
    );
    await tester.tap(find.text('Checkout'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsOneWidget);
    await _scrollToCancel(tester);
    expect(find.text('Cancel'), findsOneWidget);
  });
}
