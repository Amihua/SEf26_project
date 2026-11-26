import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_display_models.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_fix_sheet.dart';

WolfGuardFixPlanViewData _plan() {
  return WolfGuardFixPlanViewData(
    planId: 'plan-1',
    before: WolfGuardSummaryViewData.fromCounts(
      totalUnits: 3,
      coveredUnits: 1,
      selfPayUnits: 0,
      blockedUnits: 2,
      unknownUnits: 0,
    ),
    projectedAfter: WolfGuardSummaryViewData.fromCounts(
      totalUnits: 2,
      coveredUnits: 2,
      selfPayUnits: 0,
      blockedUnits: 0,
      unknownUnits: 0,
    ),
    actions: const [
      WolfGuardFixActionViewData(
        title: 'Reduce cereal quantity',
        description: 'Change quantity from 2 to 1.',
      ),
      WolfGuardFixActionViewData(
        title: 'Replace juice',
        description: 'Use the selected same-category candidate.',
      ),
    ],
  );
}

Widget _sheet(WolfGuardApplyCallback callback) {
  return MaterialApp(
    home: Scaffold(
      body: WolfGuardFixSheet(plan: _plan(), onApply: callback),
    ),
  );
}

void main() {
  testWidgets('preview shows all proposed actions', (tester) async {
    await tester.pumpWidget(
      _sheet(() async => WolfGuardApplyViewOutcome.applied),
    );

    expect(find.text('Reduce cereal quantity'), findsOneWidget);
    expect(find.text('Change quantity from 2 to 1.'), findsOneWidget);
    expect(find.text('Replace juice'), findsOneWidget);
  });

  testWidgets('preview shows before and projected counts', (tester) async {
    await tester.pumpWidget(
      _sheet(() async => WolfGuardApplyViewOutcome.applied),
    );

    expect(find.text('Before'), findsOneWidget);
    expect(find.text('Projected after'), findsOneWidget);
    expect(find.text('Blocked 2'), findsOneWidget);
    expect(find.text('Blocked 0'), findsOneWidget);
  });

  testWidgets('cancel closes modal without applying', (tester) async {
    var calls = 0;
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showWolfGuardFixSheet(
                  context,
                  plan: _plan(),
                  onApply: () async {
                    calls++;
                    return WolfGuardApplyViewOutcome.applied;
                  },
                );
              },
              child: const Text('Open preview'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open preview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(result, isFalse);
  });

  testWidgets('successful apply closes modal with true', (tester) async {
    var calls = 0;
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showWolfGuardFixSheet(
                  context,
                  plan: _plan(),
                  onApply: () async {
                    calls++;
                    return WolfGuardApplyViewOutcome.applied;
                  },
                );
              },
              child: const Text('Open preview'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open preview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply repairs'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(result, isTrue);
  });

  testWidgets('rapid apply taps execute callback once', (tester) async {
    final completer = Completer<WolfGuardApplyViewOutcome>();
    var calls = 0;
    await tester.pumpWidget(
      _sheet(() {
        calls++;
        return completer.future;
      }),
    );

    await tester.tap(find.text('Apply repairs'));
    await tester.tap(find.text('Apply repairs'));
    await tester.pump();
    expect(find.text('Applying repairs…'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(calls, 1);

    completer.complete(WolfGuardApplyViewOutcome.stalePlan);
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('stale plan explains that no apply occurred', (tester) async {
    await tester.pumpWidget(
      _sheet(() async => WolfGuardApplyViewOutcome.stalePlan),
    );

    await tester.tap(find.text('Apply repairs'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('basket changed after this preview'),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('persistence failure stays visible for review', (tester) async {
    await tester.pumpWidget(
      _sheet(() async => WolfGuardApplyViewOutcome.persistenceFailed),
    );

    await tester.tap(find.text('Apply repairs'));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be saved'), findsOneWidget);
    expect(find.text('Apply repairs'), findsOneWidget);
  });

  testWidgets('narrow large-text preview remains scrollable', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _sheet(() async => WolfGuardApplyViewOutcome.applied),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsOneWidget);
  });
}
