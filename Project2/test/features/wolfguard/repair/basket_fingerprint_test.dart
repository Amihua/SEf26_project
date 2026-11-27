import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/domain/wolfguard_models.dart';
import 'package:wolfbite/features/wolfguard/engine/preflight_request_builder.dart';
import 'package:wolfbite/features/wolfguard/repair/basket_fingerprint.dart';

import 'repair_test_fixtures.dart';

void main() {
  group('BasketLineKey', () {
    test('issues the key PreflightRequestBuilder issues', () {
      final request = PreflightRequestBuilder.fromAppState(
        basket: [
          rawLine(upc: '111', category: 'MILK - WHOLE'),
          rawLine(upc: '222', category: 'CHEESE'),
        ],
        balances: const {},
        evaluatedAt: DateTime.utc(2026, 11, 27),
      );

      expect(request.lines.map((line) => line.lineKey), [
        BasketLineKey.of(index: 0, upc: '111', basketCategory: 'MILK - WHOLE'),
        BasketLineKey.of(index: 1, upc: '222', basketCategory: 'CHEESE'),
      ]);
    });

    test('parses a key the builder issued', () {
      final request = PreflightRequestBuilder.fromAppState(
        basket: [rawLine(upc: '111', category: 'MILK - WHOLE')],
        balances: const {},
        evaluatedAt: DateTime.utc(2026, 11, 27),
      );

      final key = BasketLineKey.parse(request.lines.single.lineKey)!;

      expect(key.index, 0);
      expect(key.upc, '111');
      expect(key.basketCategory, 'MILK - WHOLE');
      expect(key.value, request.lines.single.lineKey);
    });

    test('parses a key for a line whose UPC is blank', () {
      final key = BasketLineKey.parse('3::MILK - WHOLE')!;

      expect(key.index, 3);
      expect(key.upc, isEmpty);
      expect(key.basketCategory, 'MILK - WHOLE');
    });

    test('rejects a key that was not built by BasketLineKey', () {
      expect(BasketLineKey.parse('milk-line'), isNull);
      expect(BasketLineKey.parse('0:111'), isNull);
      expect(BasketLineKey.parse('first:111:MILK - WHOLE'), isNull);
      expect(BasketLineKey.parse('-1:111:MILK - WHOLE'), isNull);
    });
  });

  group('BasketFingerprint', () {
    PreflightRequest snapshot({
      Object? qty = 1,
      String name = 'Whole milk',
      int used = 1,
      Map<String, ProductEvidence> evidence = const {},
    }) {
      return PreflightRequestBuilder.fromAppState(
        basket: [rawLine(upc: '111', name: name, qty: qty)],
        balances: {
          'MILK - WHOLE': {'allowed': 3, 'used': used},
        },
        evaluatedAt: DateTime.utc(2026, 11, 27),
        evidenceByUpc: evidence,
      );
    }

    test('is stable for the same state', () {
      expect(
        BasketFingerprint.of(snapshot()),
        BasketFingerprint.of(snapshot()),
      );
    });

    test('changes when a quantity changes', () {
      expect(
        BasketFingerprint.of(snapshot(qty: 1)),
        isNot(BasketFingerprint.of(snapshot(qty: 2))),
      );
    });

    test('changes when an allowance is spent elsewhere', () {
      expect(
        BasketFingerprint.of(snapshot(used: 1)),
        isNot(BasketFingerprint.of(snapshot(used: 2))),
      );
    });

    test('changes when catalog evidence changes', () {
      final withEvidence = snapshot(
        evidence: {
          '111': const ProductEvidence(
            aplEligible: true,
            canonicalCategory: 'MILK - WHOLE',
            freshness: EvidenceFreshness.current,
            sourceLabel: 'Imported NC APL',
          ),
        },
      );

      expect(
        BasketFingerprint.of(snapshot()),
        isNot(BasketFingerprint.of(withEvidence)),
      );
    });

    test('does not change when the evaluation time moves', () {
      final morning = PreflightRequestBuilder.fromAppState(
        basket: [rawLine(upc: '111')],
        balances: const {},
        evaluatedAt: DateTime.utc(2026, 11, 27, 9),
      );
      final evening = PreflightRequestBuilder.fromAppState(
        basket: [rawLine(upc: '111')],
        balances: const {},
        evaluatedAt: DateTime.utc(2026, 11, 27, 21),
      );

      expect(BasketFingerprint.of(morning), BasketFingerprint.of(evening));
    });

    test('binds a plan to the state it was proposed from', () {
      final request = snapshot();
      final plan = planOf(BasketFingerprint.of(request), const []);

      expect(
        BasketFingerprint.matches(plan, BasketFingerprint.of(request)),
        isTrue,
      );
      expect(
        BasketFingerprint.matches(plan, BasketFingerprint.of(snapshot(qty: 2))),
        isFalse,
      );
    });
  });
}
