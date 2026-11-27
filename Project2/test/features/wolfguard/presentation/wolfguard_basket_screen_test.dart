import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_basket_screen.dart';
import 'package:wolfbite/state/app_state.dart';

class _RepairableAppState extends AppState {
  _RepairableAppState(this.db) : super(db: db);

  final FakeFirebaseFirestore db;

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

_RepairableAppState _state() {
  final state = _RepairableAppState(FakeFirebaseFirestore());
  state.balances['MILK'] = {'allowed': 2, 'used': 1};
  state.basket.add({
    'upc': '111',
    'name': 'Unknown milk',
    'category': 'MILK',
    'qty': 1,
  });
  return state;
}

Widget _app(AppState state) {
  return ChangeNotifierProvider<AppState>.value(
    value: state,
    child: const MaterialApp(home: WolfGuardBasketScreen()),
  );
}

Future<void> _openRepair(WidgetTester tester) async {
  final review = find.text('Review with WolfGuard');
  await tester.ensureVisible(review);
  await tester.tap(review);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Preview safe repair'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('production wrapper shows real M1 report in inherited basket', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_state()));
    await tester.pumpAndSettle();

    expect(find.text('My Basket'), findsOneWidget);
    expect(find.text('Unknown milk'), findsOneWidget);
    expect(find.text('Basket needs review'), findsOneWidget);
    expect(find.text('Unknown 1'), findsOneWidget);
  });

  testWidgets('inherited basket previews and applies real M2 repair', (
    tester,
  ) async {
    final state = _state();
    await tester.pumpWidget(_app(state));
    await tester.pumpAndSettle();

    await _openRepair(tester);
    expect(find.text('Preview basket repair'), findsOneWidget);
    expect(find.text('Keep item self-paid'), findsOneWidget);
    expect(find.text('Unknown 1'), findsWidgets);
    expect(find.text('Unknown 0'), findsOneWidget);

    await tester.tap(find.text('Apply repairs'));
    await tester.pumpAndSettle();

    expect(state.basket.single['category'], 'PAID');
    expect(state.basket.single['original_benefit_category'], 'MILK');
    expect(find.text('Checkout preflight reviewed'), findsOneWidget);
    expect(find.text('Self-paid 1'), findsOneWidget);
    expect(find.text('Unknown 0'), findsOneWidget);
  });

  testWidgets('replacing provider state disposes old live binding', (
    tester,
  ) async {
    final first = _state();
    final second = _state();
    second.basket.single['name'] = 'Second basket milk';

    await tester.pumpWidget(_app(first));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(second));
    await tester.pumpAndSettle();

    expect(find.text('Second basket milk'), findsOneWidget);
    first.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Second basket milk'), findsOneWidget);
  });
}
