import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_basket_integration.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_display_models.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_live_controller.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_rehearsal_screen.dart';
import 'package:wolfbite/screens/basket_screen.dart';
import 'package:wolfbite/state/app_state.dart';

WolfGuardReportViewData _report({required bool ready}) =>
    WolfGuardReportViewData(
      summary: ready
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
              blockedUnits: 0,
              unknownUnits: 1,
            ),
      lines: [
        WolfGuardLineViewData(
          lineKey: 'milk',
          productName: 'Test Milk',
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

class _Source extends ChangeNotifier implements WolfGuardLiveReportSource {
  _Source({required this.ready});

  final bool ready;

  @override
  Listenable get basketChanges => this;

  @override
  Future<WolfGuardReportViewData> analyze() async => _report(ready: ready);
}

class _RehearsalDriver implements WolfGuardRehearsalDriver {
  @override
  Future<WolfGuardReportViewData> loadReport() async => _report(ready: false);

  @override
  Future<WolfGuardFixPlanViewData?> planFor(WolfGuardLineViewData line) async =>
      null;

  @override
  Future<WolfGuardApplyViewOutcome> apply(
    WolfGuardFixPlanViewData plan,
  ) async => WolfGuardApplyViewOutcome.applied;
}

AppState _basketState() {
  final state = AppState(db: FakeFirebaseFirestore());
  state.balances['MILK'] = {'allowed': 3, 'used': 1};
  state.basket.add({
    'upc': '123456789012',
    'name': 'Test Milk',
    'category': 'MILK',
    'qty': 1,
  });
  return state;
}

Widget _host({WolfGuardBasketIntegration? integration}) {
  return ChangeNotifierProvider<AppState>.value(
    value: _basketState(),
    child: MaterialApp(home: BasketScreen(wolfGuard: integration)),
  );
}

Future<void> _tapCheckout(WidgetTester tester) async {
  final checkout = find.text('Ready to Checkout');
  await tester.ensureVisible(checkout);
  await tester.pump();
  await tester.tap(checkout);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('optional integration renders live status in inherited basket', (
    tester,
  ) async {
    final source = _Source(ready: false);
    final controller = WolfGuardLiveController(source: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(integration: WolfGuardBasketIntegration(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('My Basket'), findsOneWidget);
    expect(find.text('Test Milk'), findsOneWidget);
    expect(find.text('Basket needs review'), findsOneWidget);
    expect(find.text('Unknown 1'), findsOneWidget);
  });

  testWidgets('risky basket is reviewed before inherited QR navigation', (
    tester,
  ) async {
    final source = _Source(ready: false);
    final controller = WolfGuardLiveController(source: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(integration: WolfGuardBasketIntegration(controller: controller)),
    );
    await tester.pumpAndSettle();

    await _tapCheckout(tester);
    expect(find.text('Review before checkout'), findsOneWidget);
    expect(find.text('QR Code Checkout'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Cancel'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('QR Code Checkout'), findsNothing);
    expect(find.text('Test Milk'), findsOneWidget);
  });

  testWidgets('reviewed basket preserves inherited QR destination', (
    tester,
  ) async {
    final source = _Source(ready: true);
    final controller = WolfGuardLiveController(source: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(integration: WolfGuardBasketIntegration(controller: controller)),
    );
    await tester.pumpAndSettle();

    await _tapCheckout(tester);
    expect(find.text('QR Code Checkout'), findsOneWidget);
    expect(find.text('Finish Transaction'), findsOneWidget);
  });

  testWidgets('omitting integration keeps inherited direct checkout', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.textContaining('WolfGuard'), findsNothing);
    await _tapCheckout(tester);
    expect(find.text('QR Code Checkout'), findsOneWidget);
  });

  testWidgets('configured rehearsal entry opens isolated screen', (
    tester,
  ) async {
    final source = _Source(ready: false);
    final controller = WolfGuardLiveController(source: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        integration: WolfGuardBasketIntegration(
          controller: controller,
          rehearsalDriver: _RehearsalDriver(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Try WolfGuard rehearsal'));
    await tester.pumpAndSettle();
    expect(find.text('Try WolfGuard rehearsal'), findsOneWidget);
    expect(find.textContaining('Synthetic sample'), findsOneWidget);
  });
}
