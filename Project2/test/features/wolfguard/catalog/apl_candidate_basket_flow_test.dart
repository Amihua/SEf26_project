import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wolfbite/features/wolfguard/catalog/apl_candidate_provider.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_basket_screen.dart';
import 'package:wolfbite/services/apl_service.dart';
import 'package:wolfbite/state/app_state.dart';

/// M3 (Feiyang): the concrete APL provider driven through the production
/// WolfGuard basket composition, with fake Firestore and no network.

const _milk = 'MILK - WHOLE';

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

/// Fails the replacement query a fixed number of times, then delegates.
class _FlakyAplService extends AplService {
  _FlakyAplService(FirebaseFirestore db, {required this.failures})
    : super(db: db, useNutritionCollection: false);

  int failures;

  @override
  Future<List<Map<String, dynamic>>> eligibleReplacements(
    String canonicalCategory, {
    String? excludeUpc,
    int max = 5,
  }) {
    if (failures > 0) {
      failures--;
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    return super.eligibleReplacements(
      canonicalCategory,
      excludeUpc: excludeUpc,
      max: max,
    );
  }
}

Future<_RepairableAppState> _state() async {
  final db = FakeFirebaseFirestore();
  final apl = db.collection('apl');
  await apl.doc('000111').set({
    'name': 'Delisted whole milk',
    'category': _milk,
    'categoryCode': '51',
    'eligible': false,
  });
  await apl.doc('000222').set({
    'name': 'Listed whole milk',
    'category': 'MILK-WHOLE',
    'categoryCode': '51',
    'unitOfMeasure': 'GAL',
    'eligible': true,
  });
  final state = _RepairableAppState(db);
  state.balances[_milk] = {'allowed': 2, 'used': 1};
  state.basket.add({
    'upc': '000111',
    'name': 'Delisted whole milk',
    'category': _milk,
    'qty': 1,
  });
  return state;
}

List<Map<String, dynamic>> _copy(List<Map<String, dynamic>> basket) =>
    basket.map((item) => Map<String, dynamic>.from(item)).toList();

Widget _app(AppState state, AplCandidateProvider provider) {
  return ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      home: WolfGuardBasketScreen(candidateProvider: provider),
    ),
  );
}

Future<void> _openCandidates(WidgetTester tester) async {
  final review = find.text('Review with WolfGuard');
  await tester.ensureVisible(review);
  await tester.tap(review);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Preview safe repair'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'real APL candidate keeps its UPC through preview, cancel, and apply',
    (tester) async {
      final state = await _state();
      final before = _copy(state.basket);
      await tester.pumpWidget(
        _app(state, AplCandidateProvider(state.productCatalog)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Blocked 1'), findsOneWidget);

      await _openCandidates(tester);
      expect(find.text('Listed whole milk'), findsOneWidget);
      expect(find.text('Same benefit category · $_milk'), findsOneWidget);
      expect(find.textContaining('package size not verified'), findsOneWidget);
      expect(find.textContaining('Delisted whole milk'), findsWidgets);
      expect(state.basket, before, reason: 'lookup must not mutate');

      await tester.tap(find.text('Use in repair preview'));
      await tester.pumpAndSettle();
      expect(find.text('Preview basket repair'), findsOneWidget);
      expect(find.text('Use eligible replacement'), findsOneWidget);
      expect(state.basket, before, reason: 'preview must not mutate');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Preview basket repair'), findsNothing);
      expect(state.basket, before, reason: 'cancel must be a no-op');
      expect(find.text('Blocked 1'), findsWidgets);

      // Navigate back to the basket in case Cancel left the report open.
      while (find
              .text('Review with WolfGuard')
              .hitTestable()
              .evaluate()
              .isEmpty &&
          find.byType(BackButton).evaluate().isNotEmpty) {
        await tester.tap(find.byType(BackButton).last);
        await tester.pumpAndSettle();
      }
      await _openCandidates(tester);
      await tester.tap(find.text('Use in repair preview'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply repairs'));
      await tester.pumpAndSettle();

      expect(state.basket.single['upc'], '000222');
      expect(state.basket.single['name'], 'Listed whole milk');
      expect(find.text('Checkout preflight reviewed'), findsOneWidget);
      expect(find.text('Covered 1'), findsOneWidget);
    },
  );

  testWidgets('catalog failure offers Retry and leaves the basket unchanged', (
    tester,
  ) async {
    final state = await _state();
    final before = _copy(state.basket);
    final apl = _FlakyAplService(state.db, failures: 1);
    await tester.pumpWidget(_app(state, AplCandidateProvider(apl)));
    await tester.pumpAndSettle();

    await _openCandidates(tester);
    expect(
      find.textContaining('Replacement evidence is temporarily unavailable'),
      findsOneWidget,
    );
    expect(find.text('Listed whole milk'), findsNothing);
    expect(state.basket, before);

    await tester.tap(find.text('Retry alternatives'));
    await tester.pumpAndSettle();

    expect(find.text('Listed whole milk'), findsOneWidget);
    expect(state.basket, before);
  });

  testWidgets('no eligible alternative is reported honestly', (tester) async {
    final state = await _state();
    await state.db.collection('apl').doc('000222').delete();
    await tester.pumpWidget(
      _app(state, AplCandidateProvider(state.productCatalog)),
    );
    await tester.pumpAndSettle();

    await _openCandidates(tester);

    expect(find.text('No evidence-safe alternatives found.'), findsOneWidget);
    expect(
      find.textContaining('does not mean no alternatives'),
      findsOneWidget,
    );
    expect(find.text('Use in repair preview'), findsNothing);
  });
}
