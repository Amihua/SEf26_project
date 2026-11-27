import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/domain/wolfguard_models.dart';
import 'package:wolfbite/features/wolfguard/engine/preflight_request_builder.dart';
import 'package:wolfbite/features/wolfguard/repair/basket_fingerprint.dart';
import 'package:wolfbite/features/wolfguard/repair/fix_plan_applier.dart';

import 'repair_test_fixtures.dart';

void main() {
  /// A target holding one three-unit milk line against a cap of three.
  FakeRepairTarget milkBasket({int qty = 3, int allowed = 3}) {
    return FakeRepairTarget(
      basket: [rawLine(upc: '111', name: 'Whole milk', qty: qty)],
      balances: {
        'MILK - WHOLE': {'allowed': allowed, 'used': qty},
      },
    );
  }

  /// Re-snapshots live state the way the presentation layer does, which is
  /// what the applier compares a plan against.
  PreflightRequest snapshotOf(FakeRepairTarget target) =>
      PreflightRequestBuilder.fromAppState(
        basket: target.basket,
        balances: target.balances,
        evaluatedAt: DateTime.utc(2026, 11, 27),
      );

  String fingerprintOf(FakeRepairTarget target) =>
      BasketFingerprint.of(snapshotOf(target));

  WolfGuardFixPlanApplier applierFor(FakeRepairTarget target) =>
      WolfGuardFixPlanApplier(
        target: target,
        snapshot: () => snapshotOf(target),
      );

  group('stale-plan protection', () {
    test('a plan whose basket is unchanged is applied', () async {
      final target = milkBasket();
      final applier = applierFor(target);
      final plan = planOf(fingerprintOf(target), [
        action(
          FixKind.reduceQuantity,
          index: 0,
          upc: '111',
          basketCategory: 'MILK - WHOLE',
          targetQuantity: 2,
        ),
      ]);

      expect(await applier.apply(plan), ApplyPlanResult.applied);
      expect(target.basket.single['qty'], 2);
    });

    test('a plan is refused once the basket changed', () async {
      final target = milkBasket();
      final applier = applierFor(target);
      final plan = planOf(fingerprintOf(target), [
        action(
          FixKind.reduceQuantity,
          index: 0,
          upc: '111',
          basketCategory: 'MILK - WHOLE',
          targetQuantity: 2,
        ),
      ]);

      // The shopper scans something else while the preview is open.
      target.basket.add(rawLine(upc: '222', category: 'CHEESE'));

      expect(await applier.apply(plan), ApplyPlanResult.stalePlan);
      expect(target.commits, 0);
      expect(target.basket.first['qty'], 3);
    });

    test('a plan is refused once an allowance changed elsewhere', () async {
      final target = milkBasket();
      final applier = applierFor(target);
      final plan = planOf(fingerprintOf(target), [
        action(
          FixKind.removeLine,
          index: 0,
          upc: '111',
          basketCategory: 'MILK - WHOLE',
        ),
      ]);

      target.balances['MILK - WHOLE']!['used'] = 2;

      expect(await applier.apply(plan), ApplyPlanResult.stalePlan);
      expect(target.commits, 0);
    });

    test('applying the same plan a second time is refused', () async {
      final target = milkBasket();
      final applier = applierFor(target);
      final plan = planOf(fingerprintOf(target), [
        action(
          FixKind.reduceQuantity,
          index: 0,
          upc: '111',
          basketCategory: 'MILK - WHOLE',
          targetQuantity: 2,
        ),
      ]);

      expect(await applier.apply(plan), ApplyPlanResult.applied);
      expect(await applier.apply(plan), ApplyPlanResult.stalePlan);
      expect(target.commits, 1);
      expect(target.basket.single['qty'], 2);
    });

    test('a double tap on one plan commits exactly once', () async {
      final target = milkBasket();
      target.gate = Completer<void>();
      final applier = applierFor(target);
      final plan = planOf(fingerprintOf(target), [
        action(
          FixKind.reduceQuantity,
          index: 0,
          upc: '111',
          basketCategory: 'MILK - WHOLE',
          targetQuantity: 1,
        ),
      ]);

      final first = applier.apply(plan);
      final second = applier.apply(plan);
      target.gate!.complete();

      expect(await first, ApplyPlanResult.applied);
      expect(await second, ApplyPlanResult.applied);
      expect(target.commits, 1);
      expect(target.basket.single['qty'], 1);
    });

    test('a second plan cannot interleave with one in flight', () async {
      final target = milkBasket();
      target.gate = Completer<void>();
      final applier = applierFor(target);
      final fingerprint = fingerprintOf(target);
      final first = applier.apply(
        planOf(fingerprint, [
          action(
            FixKind.reduceQuantity,
            index: 0,
            upc: '111',
            basketCategory: 'MILK - WHOLE',
            targetQuantity: 2,
          ),
        ]),
      );
      final second = applier.apply(
        planOf(fingerprint, [
          action(
            FixKind.removeLine,
            index: 0,
            upc: '111',
            basketCategory: 'MILK - WHOLE',
          ),
        ]),
      );
      target.gate!.complete();

      expect(await second, ApplyPlanResult.stalePlan);
      expect(await first, ApplyPlanResult.applied);
      expect(target.commits, 1);
      expect(target.basket.single['qty'], 2);
    });

    test('cancelling, that is never applying, changes nothing', () async {
      final target = milkBasket();
      final before = fingerprintOf(target);
      final applier = applierFor(target);
      final plan = planOf(before, [
        action(
          FixKind.removeLine,
          index: 0,
          upc: '111',
          basketCategory: 'MILK - WHOLE',
        ),
      ]);

      // Cancel is the absence of an apply call, so the only thing to prove is
      // that building and previewing a plan touched nothing.
      expect(target.commits, 0);
      expect(target.basket, hasLength(1));
      expect(target.basket.single['qty'], 3);
      expect(target.balances['MILK - WHOLE']!['used'], 3);
      expect(fingerprintOf(target), before);

      // And that the plan really would have changed something, so the
      // assertions above are not passing for want of a repair.
      expect(await applier.apply(plan), ApplyPlanResult.applied);
      expect(target.basket, isEmpty);
    });

    test('an empty plan writes nothing and reports success', () async {
      final target = milkBasket();
      final applier = applierFor(target);

      expect(
        await applier.apply(planOf(fingerprintOf(target), const [])),
        ApplyPlanResult.applied,
      );
      expect(target.commits, 0);
    });
  });

  group('each fix kind', () {
    test('reduceQuantity lowers the line and returns the allowance', () async {
      final target = milkBasket(qty: 3, allowed: 3);
      final applier = applierFor(target);

      final result = await applier.apply(
        planOf(fingerprintOf(target), [
          action(
            FixKind.reduceQuantity,
            index: 0,
            upc: '111',
            basketCategory: 'MILK - WHOLE',
            targetQuantity: 1,
          ),
        ]),
      );

      expect(result, ApplyPlanResult.applied);
      expect(target.basket.single['qty'], 1);
      expect(target.balances['MILK - WHOLE']!['used'], 1);
    });

    test('removeLine drops the line and returns every unit', () async {
      final target = milkBasket(qty: 2, allowed: 3);
      final applier = applierFor(target);

      final result = await applier.apply(
        planOf(fingerprintOf(target), [
          action(
            FixKind.removeLine,
            index: 0,
            upc: '111',
            basketCategory: 'MILK - WHOLE',
          ),
        ]),
      );

      expect(result, ApplyPlanResult.applied);
      expect(target.basket, isEmpty);
      expect(target.balances['MILK - WHOLE']!['used'], 0);
    });

    test(
      'keepAsSelfPay moves the units to PAID and keeps the origin',
      () async {
        final target = milkBasket(qty: 2, allowed: 2);
        final applier = applierFor(target);

        final result = await applier.apply(
          planOf(fingerprintOf(target), [
            action(
              FixKind.keepAsSelfPay,
              index: 0,
              upc: '111',
              basketCategory: 'MILK - WHOLE',
            ),
          ]),
        );

        expect(result, ApplyPlanResult.applied);
        final moved = target.basket.single;
        expect(moved['category'], 'PAID');
        expect(moved['original_benefit_category'], 'MILK - WHOLE');
        expect(moved['qty'], 2);
        expect(target.balances['MILK - WHOLE']!['used'], 0);
        expect(target.balances['PAID']!['used'], 2);
        expect(target.balances['PAID']!['allowed'], isNull);
      },
    );

    test('replaceProduct swaps the product and leaves the allowance', () async {
      final target = milkBasket(qty: 2, allowed: 3);
      final applier = applierFor(target);

      final result = await applier.apply(
        planOf(fingerprintOf(target), [
          action(
            FixKind.replaceProduct,
            index: 0,
            upc: '111',
            basketCategory: 'MILK - WHOLE',
            replacement: candidate(upc: '222', name: 'Plain whole milk'),
          ),
        ]),
      );

      expect(result, ApplyPlanResult.applied);
      final swapped = target.basket.single;
      expect(swapped['upc'], '222');
      expect(swapped['name'], 'Plain whole milk');
      expect(swapped['qty'], 2);
      expect(swapped['category'], 'MILK - WHOLE');
      expect(target.balances['MILK - WHOLE']!['used'], 2);
    });

    test(
      'a replacement carries unknown nutrition, never the old values',
      () async {
        final target = FakeRepairTarget(
          basket: [
            rawLine(upc: '111', qty: 1, nutrition: const {'calcium': 300}),
          ],
          balances: {
            'MILK - WHOLE': {'allowed': 3, 'used': 1},
          },
        );
        final applier = applierFor(target);

        await applier.apply(
          planOf(fingerprintOf(target), [
            action(
              FixKind.replaceProduct,
              index: 0,
              upc: '111',
              basketCategory: 'MILK - WHOLE',
              replacement: candidate(upc: '222'),
            ),
          ]),
        );

        final nutrition = target.basket.single['nutrition'] as Map;
        expect(nutrition['calcium'], isNot(300));
      },
    );

    test('several actions in one plan all land together', () async {
      final target = FakeRepairTarget(
        basket: [
          rawLine(upc: '111', qty: 3),
          rawLine(upc: '222', category: 'CHEESE', qty: 1),
          rawLine(upc: '333', category: 'EGGS', qty: 1),
        ],
        balances: {
          'MILK - WHOLE': {'allowed': 2, 'used': 3},
          'CHEESE': {'allowed': 1, 'used': 1},
          'EGGS': {'allowed': 1, 'used': 1},
        },
      );
      final applier = applierFor(target);

      final result = await applier.apply(
        planOf(fingerprintOf(target), [
          action(
            FixKind.reduceQuantity,
            index: 0,
            upc: '111',
            basketCategory: 'MILK - WHOLE',
            targetQuantity: 2,
          ),
          action(
            FixKind.keepAsSelfPay,
            index: 1,
            upc: '222',
            basketCategory: 'CHEESE',
          ),
          action(
            FixKind.removeLine,
            index: 2,
            upc: '333',
            basketCategory: 'EGGS',
          ),
        ]),
      );

      expect(result, ApplyPlanResult.applied);
      expect(target.commits, 1);
      expect(target.basket, hasLength(2));
      expect(target.basket[0]['qty'], 2);
      expect(target.basket[1]['category'], 'PAID');
      expect(target.balances['MILK - WHOLE']!['used'], 2);
      expect(target.balances['CHEESE']!['used'], 0);
      expect(target.balances['PAID']!['used'], 1);
      expect(target.balances['EGGS']!['used'], 0);
    });
  });

  group('lines a plan may not confuse', () {
    test(
      'a benefit line is reduced even when a PAID twin shares its UPC',
      () async {
        final target = FakeRepairTarget(
          basket: [
            rawLine(upc: '111', qty: 2),
            rawLine(
              upc: '111',
              category: 'PAID',
              originalBenefitCategory: 'MILK - WHOLE',
              qty: 1,
            ),
          ],
          balances: {
            'MILK - WHOLE': {'allowed': 2, 'used': 2},
            'PAID': {'allowed': null, 'used': 1},
          },
        );
        final applier = applierFor(target);

        final result = await applier.apply(
          planOf(fingerprintOf(target), [
            action(
              FixKind.reduceQuantity,
              index: 0,
              upc: '111',
              basketCategory: 'MILK - WHOLE',
              targetQuantity: 1,
            ),
          ]),
        );

        expect(result, ApplyPlanResult.applied);
        expect(target.basket[0]['category'], 'MILK - WHOLE');
        expect(target.basket[0]['qty'], 1);
        expect(target.basket[1]['category'], 'PAID');
        expect(target.basket[1]['qty'], 1);
        expect(target.balances['MILK - WHOLE']!['used'], 1);
        expect(target.balances['PAID']!['used'], 1);
      },
    );

    test(
      'self-pay merges into an existing PAID line for the same UPC',
      () async {
        final target = FakeRepairTarget(
          basket: [
            rawLine(upc: '111', qty: 2),
            rawLine(
              upc: '111',
              category: 'PAID',
              originalBenefitCategory: 'MILK - WHOLE',
              qty: 1,
            ),
          ],
          balances: {
            'MILK - WHOLE': {'allowed': 2, 'used': 2},
            'PAID': {'allowed': null, 'used': 1},
          },
        );
        final applier = applierFor(target);

        final result = await applier.apply(
          planOf(fingerprintOf(target), [
            action(
              FixKind.keepAsSelfPay,
              index: 0,
              upc: '111',
              basketCategory: 'MILK - WHOLE',
            ),
          ]),
        );

        expect(result, ApplyPlanResult.applied);
        expect(target.basket, hasLength(1));
        expect(target.basket.single['category'], 'PAID');
        expect(target.basket.single['qty'], 3);
        expect(target.balances['MILK - WHOLE']!['used'], 0);
        expect(target.balances['PAID']!['used'], 3);
      },
    );

    test('a category spelling variant still resolves to its line', () async {
      final target = FakeRepairTarget(
        basket: [rawLine(upc: '111', category: 'MILK - WHOLE', qty: 2)],
        balances: {
          'MILK - WHOLE': {'allowed': 2, 'used': 2},
        },
      );
      final applier = applierFor(target);

      final result = await applier.apply(
        planOf(fingerprintOf(target), [
          action(
            FixKind.reduceQuantity,
            index: 0,
            upc: '111',
            basketCategory: 'MILK-WHOLE',
            targetQuantity: 1,
          ),
        ]),
      );

      expect(result, ApplyPlanResult.applied);
      expect(target.basket.single['qty'], 1);
    });
  });

  group('operations the applier refuses', () {
    Future<ApplyPlanResult> applyAction(FixAction only) async {
      final target = milkBasket();
      final applier = applierFor(target);
      final result = await applier.apply(planOf(fingerprintOf(target), [only]));
      expect(target.commits, 0, reason: 'a refused plan must not be written');
      expect(target.basket.single['qty'], 3);
      return result;
    }

    test('a line key the applier did not issue', () async {
      expect(
        await applyAction(
          action(
            FixKind.removeLine,
            index: 0,
            upc: '111',
            basketCategory: 'MILK - WHOLE',
            lineKey: 'milk-line',
          ),
        ),
        ApplyPlanResult.unsupportedAction,
      );
    });

    test('a line index that is past the end of the basket', () async {
      expect(
        await applyAction(
          action(
            FixKind.removeLine,
            index: 7,
            upc: '111',
            basketCategory: 'MILK - WHOLE',
          ),
        ),
        ApplyPlanResult.unsupportedAction,
      );
    });

    test('a key whose UPC does not match the line it points at', () async {
      expect(
        await applyAction(
          action(
            FixKind.removeLine,
            index: 0,
            upc: '999',
            basketCategory: 'MILK - WHOLE',
          ),
        ),
        ApplyPlanResult.unsupportedAction,
      );
    });

    test('a reduction to zero, which is a removal in disguise', () async {
      expect(
        await applyAction(
          action(
            FixKind.reduceQuantity,
            index: 0,
            upc: '111',
            basketCategory: 'MILK - WHOLE',
            targetQuantity: 0,
          ),
        ),
        ApplyPlanResult.unsupportedAction,
      );
    });

    test('a reduction that would raise the quantity', () async {
      expect(
        await applyAction(
          action(
            FixKind.reduceQuantity,
            index: 0,
            upc: '111',
            basketCategory: 'MILK - WHOLE',
            targetQuantity: 5,
          ),
        ),
        ApplyPlanResult.unsupportedAction,
      );
    });

    test('a reduction with no target quantity', () async {
      expect(
        await applyAction(
          action(
            FixKind.reduceQuantity,
            index: 0,
            upc: '111',
            basketCategory: 'MILK - WHOLE',
          ),
        ),
        ApplyPlanResult.unsupportedAction,
      );
    });

    test('a replacement with no candidate attached', () async {
      expect(
        await applyAction(
          action(
            FixKind.replaceProduct,
            index: 0,
            upc: '111',
            basketCategory: 'MILK - WHOLE',
          ),
        ),
        ApplyPlanResult.unsupportedAction,
      );
    });

    test('a replacement by the product already on the line', () async {
      expect(
        await applyAction(
          action(
            FixKind.replaceProduct,
            index: 0,
            upc: '111',
            basketCategory: 'MILK - WHOLE',
            replacement: candidate(upc: '111'),
          ),
        ),
        ApplyPlanResult.unsupportedAction,
      );
    });

    test('moving a PAID line to self-pay, which it already is', () async {
      final target = FakeRepairTarget(
        basket: [
          rawLine(
            upc: '111',
            category: 'PAID',
            originalBenefitCategory: 'MILK - WHOLE',
            qty: 1,
          ),
        ],
        balances: {
          'PAID': {'allowed': null, 'used': 1},
        },
      );
      final applier = applierFor(target);

      final result = await applier.apply(
        planOf(fingerprintOf(target), [
          action(
            FixKind.keepAsSelfPay,
            index: 0,
            upc: '111',
            basketCategory: 'PAID',
          ),
        ]),
      );

      expect(result, ApplyPlanResult.unsupportedAction);
      expect(target.commits, 0);
    });

    test('two actions against the same line', () async {
      final target = milkBasket();
      final applier = applierFor(target);

      final result = await applier.apply(
        planOf(fingerprintOf(target), [
          action(
            FixKind.reduceQuantity,
            index: 0,
            upc: '111',
            basketCategory: 'MILK - WHOLE',
            targetQuantity: 2,
          ),
          action(
            FixKind.removeLine,
            index: 0,
            upc: '111',
            basketCategory: 'MILK - WHOLE',
          ),
        ]),
      );

      expect(result, ApplyPlanResult.unsupportedAction);
      expect(target.commits, 0);
      expect(target.basket.single['qty'], 3);
    });

    test('one unsupported action refuses the whole plan', () async {
      final target = FakeRepairTarget(
        basket: [
          rawLine(upc: '111', qty: 2),
          rawLine(upc: '222', qty: 1),
        ],
        balances: {
          'MILK - WHOLE': {'allowed': 2, 'used': 3},
        },
      );
      final applier = applierFor(target);

      final result = await applier.apply(
        planOf(fingerprintOf(target), [
          action(
            FixKind.removeLine,
            index: 0,
            upc: '111',
            basketCategory: 'MILK - WHOLE',
          ),
          action(
            FixKind.reduceQuantity,
            index: 1,
            upc: '222',
            basketCategory: 'MILK - WHOLE',
            targetQuantity: 4,
          ),
        ]),
      );

      expect(result, ApplyPlanResult.unsupportedAction);
      expect(target.commits, 0);
      expect(target.basket, hasLength(2));
      expect(target.basket[0]['qty'], 2);
    });
  });

  group('persistence', () {
    test('a failed write is reported, never as success', () async {
      final target = milkBasket();
      target.failCommit = true;
      final applier = applierFor(target);

      final result = await applier.apply(
        planOf(fingerprintOf(target), [
          action(
            FixKind.removeLine,
            index: 0,
            upc: '111',
            basketCategory: 'MILK - WHOLE',
          ),
        ]),
      );

      expect(result, ApplyPlanResult.persistenceFailed);
      expect(target.commits, 1);
      expect(target.basket, hasLength(1));
    });

    test('the plan can be retried after the write failed', () async {
      final target = milkBasket();
      target.failCommit = true;
      final applier = applierFor(target);
      final plan = planOf(fingerprintOf(target), [
        action(
          FixKind.removeLine,
          index: 0,
          upc: '111',
          basketCategory: 'MILK - WHOLE',
        ),
      ]);

      expect(await applier.apply(plan), ApplyPlanResult.persistenceFailed);

      target.failCommit = false;

      expect(await applier.apply(plan), ApplyPlanResult.applied);
      expect(target.basket, isEmpty);
    });
  });
}

/// A stand-in for the WolfGuard slice of `AppState`.
///
/// It holds the inherited basket and balance shapes in memory and records
/// every commit, so an apply test can assert on what would have been written
/// without a Firebase instance. [failCommit] makes the write report failure
/// the way `AppState.commitWolfGuardRepair` does when Firestore throws.
class FakeRepairTarget implements RepairTarget {
  FakeRepairTarget({
    List<Map<String, dynamic>>? basket,
    Map<String, Map<String, dynamic>>? balances,
  }) : basket = basket ?? <Map<String, dynamic>>[],
       balances = balances ?? <String, Map<String, dynamic>>{};

  @override
  final List<Map<String, dynamic>> basket;

  @override
  Map<String, Map<String, dynamic>> balances;

  /// When true, the next commit reports failure and changes nothing.
  bool failCommit = false;

  /// Lets a test hold a commit open, so a second apply arrives while the
  /// first is still running.
  Completer<void>? gate;

  /// How many commits were attempted, including failed ones.
  int commits = 0;

  @override
  Future<bool> commitWolfGuardRepair({
    required List<Map<String, dynamic>> basket,
    required Map<String, Map<String, dynamic>> balances,
  }) async {
    commits++;
    final held = gate;
    if (held != null) await held.future;
    if (failCommit) return false;
    this.basket
      ..clear()
      ..addAll(basket);
    this.balances = balances;
    return true;
  }
}
