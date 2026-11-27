import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/domain/wolfguard_models.dart';
import 'package:wolfbite/features/wolfguard/engine/checkout_preflight_engine.dart';
import 'package:wolfbite/features/wolfguard/engine/preflight_request_builder.dart';

import 'support/preflight_builders.dart';

const engine = CheckoutPreflightEngine();
const milk = 'MILK - WHOLE';

final ProductEvidence milkApl = apl(milk);

/// The inherited basket after adding a fourth milk to a 3-unit allowance:
/// AppState fills the benefit line, then overflows into a PAID line.
List<Map<String, dynamic>> overflowBasket() => [
  {
    'upc': '041303',
    'name': 'Whole Milk',
    'category': 'MILK - WHOLE',
    'original_benefit_category': 'MILK - WHOLE',
    'qty': 3,
  },
  {
    'upc': '041303',
    'name': 'Whole Milk',
    'category': 'PAID',
    'original_benefit_category': 'MILK - WHOLE',
    'qty': 1,
  },
];

Map<String, Map<String, dynamic>> overflowBalances() => {
  'MILK - WHOLE': {'allowed': 3, 'used': 3},
  'PAID': {'allowed': null, 'used': 1},
};

void main() {
  group('PreflightRequestBuilder.fromAppState', () {
    test('the inherited PAID overflow analyzes as covered plus self-paid', () {
      final req = PreflightRequestBuilder.fromAppState(
        basket: overflowBasket(),
        balances: overflowBalances(),
        evaluatedAt: evaluatedAt,
        evidenceByUpc: {'041303': milkApl},
      );
      final report = engine.analyze(req);

      expect(report.coveredUnits, 3);
      expect(report.selfPayUnits, 1);
      expect(report.blockedUnits + report.unknownUnits, 0);
      expect(report.readyForHandoff, isTrue);
    });

    test('used excludes units already in the basket', () {
      final req = PreflightRequestBuilder.fromAppState(
        basket: overflowBasket(),
        balances: {
          'MILK - WHOLE': {'allowed': 3, 'used': 3},
        },
        evaluatedAt: evaluatedAt,
      );

      expect(req.benefits[milk]!.used, 0);
      expect(req.benefits.containsKey('PAID'), isFalse);
    });

    test('earlier checkouts stay counted as used', () {
      final req = PreflightRequestBuilder.fromAppState(
        basket: [
          {'upc': '1', 'name': 'Milk', 'category': milk, 'qty': 1},
        ],
        balances: {
          milk: {'allowed': 3, 'used': 3},
        },
        evaluatedAt: evaluatedAt,
      );

      expect(req.benefits[milk]!.used, 2);
    });

    test('an inherited counter over its cap reaches the engine as unknown', () {
      final req = PreflightRequestBuilder.fromAppState(
        basket: [
          {'upc': '1', 'name': 'Milk', 'category': milk, 'qty': 2},
        ],
        balances: {
          milk: {'allowed': 3, 'used': 5},
        },
        evaluatedAt: evaluatedAt,
        evidenceByUpc: {'1': milkApl},
      );
      final report = engine.analyze(req);

      expect(report.unknownUnits, 2);
      expect(
        report.lines.single.issues.single.code,
        IssueCode.contradictoryEvidence,
      );
    });

    test('a counter lower than the basket itself is contradictory', () {
      final req = PreflightRequestBuilder.fromAppState(
        basket: [
          {'upc': '1', 'name': 'Milk', 'category': milk, 'qty': 3},
        ],
        balances: {
          milk: {'allowed': 3, 'used': 1},
        },
        evaluatedAt: evaluatedAt,
        evidenceByUpc: {'1': milkApl},
      );

      expect(engine.analyze(req).unknownUnits, 3);
    });

    for (final entry in <String, Object?>{
      'decimal': 1.5,
      'string': '2',
      'missing': null,
    }.entries) {
      test('a ${entry.key} raw quantity becomes an unknown unit', () {
        final raw = <String, dynamic>{
          'upc': '1',
          'name': 'Milk',
          'category': milk,
        };
        if (entry.value != null) raw['qty'] = entry.value;
        final report = engine.analyze(
          PreflightRequestBuilder.fromAppState(
            basket: [raw],
            balances: {
              milk: {'allowed': 3, 'used': 0},
            },
            evaluatedAt: evaluatedAt,
            evidenceByUpc: {'1': milkApl},
          ),
        );

        expect(report.lines.single.status, PreflightStatus.unknown);
        expect(report.lines.single.quantity, 0);
        expect(report.unknownUnits, 1);
      });
    }

    test('unreadable allowance counters are kept as unconfirmed', () {
      final req = PreflightRequestBuilder.fromAppState(
        basket: const [],
        balances: {
          'CHEESE': {'allowed': '3', 'used': 0},
          'EGGS': {'used': 0},
          'YOGURT': {'allowed': 3},
        },
        evaluatedAt: evaluatedAt,
      );

      for (final category in ['CHEESE', 'EGGS', 'YOGURT']) {
        expect(
          req.benefits[category]!.freshness,
          EvidenceFreshness.unknown,
          reason: category,
        );
      }
    });

    test('line keys are unique for duplicate-UPC lines', () {
      final req = PreflightRequestBuilder.fromAppState(
        basket: overflowBasket(),
        balances: overflowBalances(),
        evaluatedAt: evaluatedAt,
      );

      expect(req.lines.map((l) => l.lineKey), [
        '0:041303:MILK - WHOLE',
        '1:041303:PAID',
      ]);
    });

    test('building a request never mutates the inherited maps', () {
      final basket = overflowBasket();
      final balances = overflowBalances();
      final basketBefore = basket.map((m) => Map.of(m)).toList();
      final balancesBefore = balances.map((k, v) => MapEntry(k, Map.of(v)));

      engine.analyze(
        PreflightRequestBuilder.fromAppState(
          basket: basket,
          balances: balances,
          evaluatedAt: evaluatedAt,
        ),
      );

      expect(basket, basketBefore);
      expect(balances, balancesBefore);
    });
  });

  group('PreflightRequestBuilder.evidenceFromAplRecord', () {
    test('maps an APL record without inventing a package size', () {
      final evidence = PreflightRequestBuilder.evidenceFromAplRecord({
        'upc': '1',
        'name': 'Whole Milk',
        'category': 'MILK-WHOLE',
        'eligible': true,
        'uom': 'GAL',
      })!;

      expect(evidence.aplEligible, isTrue);
      expect(evidence.canonicalCategory, milk);
      expect(evidence.packageSize, isNull);
      expect(evidence.freshness, EvidenceFreshness.current);
    });

    test('a missing record is no evidence, not ineligible', () {
      expect(PreflightRequestBuilder.evidenceFromAplRecord(null), isNull);
      final partial = PreflightRequestBuilder.evidenceFromAplRecord({
        'eligible': 'yes',
      })!;
      expect(partial.aplEligible, isNull);
      expect(partial.canonicalCategory, isNull);
    });
  });
}
