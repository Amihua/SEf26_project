import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/domain/wolfguard_models.dart';
import 'package:wolfbite/features/wolfguard/engine/preflight_request_builder.dart';
import 'package:wolfbite/features/wolfguard/repair/basket_fingerprint.dart';
import 'package:wolfbite/features/wolfguard/repair/fix_planner.dart';

import 'repair_test_fixtures.dart';

void main() {
  late RecordingAnalyzer analyzer;
  late WolfGuardFixPlanner planner;

  setUp(() {
    analyzer = RecordingAnalyzer();
    planner = WolfGuardFixPlanner(analyzer);
  });

  /// Analyses [request] with the real engine and proposes against the result,
  /// which is the order the presentation layer uses.
  FixPlan planFor(
    PreflightRequest request, {
    Map<String, List<ReplacementCandidate>> candidates = const {},
  }) {
    final report = analyzer.analyze(request);
    return planner.propose(
      request: request,
      report: report,
      candidatesByLine: candidates,
    );
  }

  /// A request snapshotted from raw `AppState` maps, the way the app builds
  /// one.
  PreflightRequest fromState({
    required List<Map<String, dynamic>> basket,
    Map<String, Map<String, dynamic>> balances = const {},
    Map<String, ProductEvidence> evidenceByUpc = const {},
  }) {
    return PreflightRequestBuilder.fromAppState(
      basket: basket,
      balances: balances,
      evaluatedAt: DateTime.utc(2026, 11, 27),
      evidenceByUpc: evidenceByUpc,
    );
  }

  /// A request built directly, for a state the inherited app cannot reach
  /// through `AppState` but the domain contract allows.
  PreflightRequest handBuilt({
    required int quantity,
    required int allowed,
    int used = 0,
    String upc = '111',
    String name = 'Whole milk',
  }) {
    return PreflightRequest(
      lines: [
        BasketLineSnapshot(
          lineKey: BasketLineKey.of(
            index: 0,
            upc: upc,
            basketCategory: 'MILK - WHOLE',
          ),
          upc: upc,
          name: name,
          basketCategory: 'MILK - WHOLE',
          originalBenefitCategory: 'MILK - WHOLE',
          quantity: quantity,
          evidence: evidence(),
        ),
      ],
      benefits: {
        'MILK - WHOLE': BenefitCategorySnapshot(
          category: 'MILK - WHOLE',
          allowed: allowed,
          used: used,
          freshness: EvidenceFreshness.current,
        ),
      },
      evaluatedAt: DateTime.utc(2026, 11, 27),
    );
  }

  group('proposals by fix kind', () {
    test('reduceQuantity keeps the units expected coverage reaches', () {
      final plan = planFor(handBuilt(quantity: 3, allowed: 2));

      final action = plan.actions.single;
      expect(action.kind, FixKind.reduceQuantity);
      expect(action.targetQuantity, 2);
      expect(action.shopperExplanation, contains('2 units'));
      expect(action.shopperExplanation, contains('application-managed'));
    });

    test('keepAsSelfPay is proposed when the allowance is fully spent', () {
      final plan = planFor(handBuilt(quantity: 1, allowed: 1, used: 1));

      expect(plan.actions.single.kind, FixKind.keepAsSelfPay);
      expect(plan.actions.single.shopperExplanation, contains('used up'));
    });

    test('replaceProduct is proposed for an ineligible product', () {
      final plan = planFor(
        fromState(
          basket: [rawLine(upc: '111', name: 'Flavoured milk')],
          balances: {'MILK - WHOLE': rawBalance(used: 1)},
          evidenceByUpc: {'111': evidence(aplEligible: false)},
        ),
        candidates: {
          '0:111:MILK - WHOLE': [
            candidate(upc: '222', name: 'Plain whole milk'),
          ],
        },
      );

      final action = plan.actions.single;
      expect(action.kind, FixKind.replaceProduct);
      expect(action.replacement?.upc, '222');
      expect(action.shopperExplanation, contains('Plain whole milk'));
    });

    test('removeLine is proposed for a line the app cannot read', () {
      final plan = planFor(
        fromState(
          basket: [rawLine(upc: '')],
          balances: {'MILK - WHOLE': rawBalance()},
        ),
      );

      expect(plan.actions.single.kind, FixKind.removeLine);
      expect(plan.actions.single.targetQuantity, isNull);
    });

    test('a nonpositive quantity is removed, not silently clamped', () {
      final plan = planFor(
        fromState(
          basket: [rawLine(upc: '111', qty: 0)],
          balances: {'MILK - WHOLE': rawBalance()},
        ),
      );

      expect(plan.actions.single.kind, FixKind.removeLine);
    });

    test('a quantity that is not an integer is removed as unreadable', () {
      final plan = planFor(
        fromState(
          basket: [rawLine(upc: '111', qty: '2')],
          balances: {'MILK - WHOLE': rawBalance()},
        ),
      );

      expect(plan.actions.single.kind, FixKind.removeLine);
    });

    test('every action carries an explanation and a derived id', () {
      final plan = planFor(
        fromState(
          basket: [
            rawLine(upc: '111'),
            rawLine(upc: '222'),
          ],
          balances: {'MILK - WHOLE': rawBalance(allowed: 3, used: 2)},
          evidenceByUpc: {'111': evidence(aplEligible: false)},
        ),
      );

      expect(plan.actions, isNotEmpty);
      for (final action in plan.actions) {
        expect(action.shopperExplanation.trim(), isNotEmpty);
        expect(action.actionId, '${action.kind.name}:${action.lineKey}');
      }
    });
  });

  group('unknown evidence', () {
    PreflightRequest unverified({Map<String, ProductEvidence> ev = const {}}) {
      return fromState(
        basket: [rawLine(upc: '111', name: 'Whole milk')],
        balances: {'MILK - WHOLE': rawBalance(used: 1)},
        evidenceByUpc: ev,
      );
    }

    test('an unverified line is offered self-pay, never a replacement', () {
      final plan = planFor(
        unverified(),
        candidates: {
          '0:111:MILK - WHOLE': [candidate(upc: '222')],
        },
      );

      final action = plan.actions.single;
      expect(action.kind, FixKind.keepAsSelfPay);
      expect(action.replacement, isNull);
      expect(action.shopperExplanation, contains('could not confirm'));
      expect(action.shopperExplanation, contains('ask store staff'));
    });

    test('stale evidence is treated as unverified, not as proof', () {
      final plan = planFor(
        unverified(ev: {'111': evidence(freshness: EvidenceFreshness.stale)}),
      );

      expect(plan.actions.single.kind, FixKind.keepAsSelfPay);
    });

    test('unanswered eligibility is treated as unverified', () {
      final plan = planFor(
        unverified(ev: {'111': evidence(aplEligible: null)}),
      );

      expect(plan.actions.single.kind, FixKind.keepAsSelfPay);
    });

    test('self-pay makes an unverified basket ready for handoff', () {
      final plan = planFor(unverified());

      expect(plan.before.readyForHandoff, isFalse);
      expect(plan.before.unknownUnits, 1);
      expect(plan.projectedAfter.readyForHandoff, isTrue);
      expect(plan.projectedAfter.selfPayUnits, 1);
    });
  });

  group('lines the planner must leave alone', () {
    test('a covered line gets no action', () {
      final plan = planFor(
        fromState(
          basket: [rawLine(upc: '111')],
          balances: {'MILK - WHOLE': rawBalance(allowed: 3, used: 1)},
          evidenceByUpc: {'111': evidence()},
        ),
      );

      expect(plan.before.readyForHandoff, isTrue);
      expect(plan.actions, isEmpty);
    });

    test('an acknowledged self-pay line is not repaired again', () {
      final plan = planFor(
        fromState(
          basket: [
            rawLine(
              upc: '111',
              category: 'PAID',
              originalBenefitCategory: 'MILK - WHOLE',
            ),
          ],
          balances: {'PAID': rawBalance(allowed: null, used: 1)},
          evidenceByUpc: {'111': evidence()},
        ),
      );

      expect(plan.actions, isEmpty);
    });

    test('a PAID line of unknown origin is left to the report', () {
      final plan = planFor(
        fromState(
          basket: [
            {'upc': '111', 'name': 'Milk', 'category': 'PAID', 'qty': 1},
          ],
          balances: {'PAID': rawBalance(allowed: null, used: 1)},
        ),
      );

      expect(plan.before.unknownUnits, 1);
      expect(plan.actions, isEmpty);
    });

    test('a line with no benefit category gets no action', () {
      final plan = planFor(
        fromState(
          basket: [rawLine(upc: '111', category: 'UNKNOWN')],
          balances: const {},
        ),
      );

      expect(plan.actions, isEmpty);
    });
  });

  group('replacement safety', () {
    const lineKey = '0:111:MILK - WHOLE';

    /// An ineligible product, built directly so the test controls the
    /// remaining allowance exactly. `PreflightRequestBuilder` subtracts the
    /// basket from `used`, so raw numbers cannot express "no room left while
    /// this line is in the basket" without also looking inconsistent.
    PreflightRequest ineligible({int allowed = 3, int used = 0}) {
      return PreflightRequest(
        lines: [
          BasketLineSnapshot(
            lineKey: lineKey,
            upc: '111',
            name: 'Flavoured milk',
            basketCategory: 'MILK - WHOLE',
            originalBenefitCategory: 'MILK - WHOLE',
            quantity: 1,
            evidence: evidence(aplEligible: false),
          ),
        ],
        benefits: {
          'MILK - WHOLE': BenefitCategorySnapshot(
            category: 'MILK - WHOLE',
            allowed: allowed,
            used: used,
            freshness: EvidenceFreshness.current,
          ),
        },
        evaluatedAt: DateTime.utc(2026, 11, 27),
      );
    }

    test(
      'an exhausted allowance gets self-pay, never a same-category swap',
      () {
        final plan = planFor(
          ineligible(allowed: 1, used: 1),
          candidates: {
            lineKey: [candidate(upc: '222')],
          },
        );

        expect(plan.actions.single.kind, FixKind.keepAsSelfPay);
      },
    );

    test('an ineligible candidate is rejected', () {
      final plan = planFor(
        ineligible(),
        candidates: {
          lineKey: [candidate(upc: '222', aplEligible: false)],
        },
      );

      expect(plan.actions.single.kind, FixKind.keepAsSelfPay);
    });

    test('a candidate from another category is rejected', () {
      final plan = planFor(
        ineligible(),
        candidates: {
          lineKey: [candidate(upc: '222', canonicalCategory: 'CHEESE')],
        },
      );

      expect(plan.actions.single.kind, FixKind.keepAsSelfPay);
    });

    test('a candidate whose evidence is stale is rejected', () {
      final plan = planFor(
        ineligible(),
        candidates: {
          lineKey: [candidate(upc: '222', freshness: EvidenceFreshness.stale)],
        },
      );

      expect(plan.actions.single.kind, FixKind.keepAsSelfPay);
    });

    test('the product already on the line is never its own fix', () {
      final plan = planFor(
        ineligible(),
        candidates: {
          lineKey: [candidate(upc: '111'), candidate(upc: '222')],
        },
      );

      expect(plan.actions.single.replacement?.upc, '222');
    });

    test('candidate order from the catalog is preserved', () {
      final plan = planFor(
        ineligible(),
        candidates: {
          lineKey: [
            candidate(upc: '222', name: 'First'),
            candidate(upc: '333', name: 'Second'),
          ],
        },
      );

      expect(plan.actions.single.replacement?.name, 'First');
    });

    test('an empty candidate list falls back to self-pay', () {
      final plan = planFor(ineligible(), candidates: const {lineKey: []});

      expect(plan.actions.single.kind, FixKind.keepAsSelfPay);
      expect(plan.actions.single.shopperExplanation, contains('no eligible'));
    });
  });

  group('preview', () {
    test('the after-state comes from re-analysing a projected basket', () {
      final plan = planFor(handBuilt(quantity: 3, allowed: 2));

      // One analysis for the before-report, one for the projection.
      expect(analyzer.seen, hasLength(2));
      expect(analyzer.seen.last.lines.single.quantity, 2);
      expect(plan.before.blockedUnits, 1);
      expect(plan.projectedAfter.blockedUnits, 0);
      expect(plan.projectedAfter.readyForHandoff, isTrue);
    });

    test('a removed line is absent from the projection', () {
      planFor(
        fromState(
          basket: [
            rawLine(upc: ''),
            rawLine(upc: '222'),
          ],
          balances: {'MILK - WHOLE': rawBalance(used: 2)},
          evidenceByUpc: {'222': evidence()},
        ),
      );

      expect(analyzer.seen.last.lines, hasLength(1));
      expect(analyzer.seen.last.lines.single.upc, '222');
    });

    test(
      'a self-pay projection moves the line to PAID and keeps its origin',
      () {
        planFor(handBuilt(quantity: 1, allowed: 1, used: 1));

        final projected = analyzer.seen.last.lines.single;
        expect(projected.basketCategory, 'PAID');
        expect(projected.originalBenefitCategory, 'MILK - WHOLE');
      },
    );

    test('a replacement projection carries the candidate evidence', () {
      planFor(
        fromState(
          basket: [rawLine(upc: '111')],
          balances: {'MILK - WHOLE': rawBalance(used: 1)},
          evidenceByUpc: {'111': evidence(aplEligible: false)},
        ),
        candidates: {
          '0:111:MILK - WHOLE': [
            candidate(upc: '222', name: 'Plain whole milk'),
          ],
        },
      );

      final projected = analyzer.seen.last.lines.single;
      expect(projected.upc, '222');
      expect(projected.name, 'Plain whole milk');
      expect(projected.evidence?.aplEligible, isTrue);
    });

    test('proposing never mutates the request it was given', () {
      final request = handBuilt(quantity: 3, allowed: 2);
      final original = request.lines.single;

      planFor(request);

      expect(request.lines, hasLength(1));
      expect(identical(request.lines.single, original), isTrue);
      expect(original.quantity, 3);
      expect(request.benefits['MILK - WHOLE']?.used, 0);
    });

    test('an empty plan still previews the unchanged basket', () {
      final plan = planFor(
        fromState(
          basket: [rawLine(upc: '111')],
          balances: {'MILK - WHOLE': rawBalance(used: 1)},
          evidenceByUpc: {'111': evidence()},
        ),
      );

      expect(plan.actions, isEmpty);
      expect(plan.projectedAfter, plan.before);
    });
  });

  group('plan identity', () {
    test('the plan is bound to the basket it was proposed from', () {
      final request = handBuilt(quantity: 3, allowed: 2);
      final plan = planFor(request);

      expect(plan.sourceFingerprint, BasketFingerprint.of(request));
      expect(BasketFingerprint.matches(plan, plan.sourceFingerprint), isTrue);
    });

    test('the same basket proposes an identical plan every time', () {
      final first = planFor(handBuilt(quantity: 3, allowed: 2));
      final second = planFor(handBuilt(quantity: 3, allowed: 2));

      expect(first.planId, second.planId);
      expect(
        first.actions.map((a) => a.actionId),
        second.actions.map((a) => a.actionId),
      );
    });

    test('different repairs on the same basket get different plan ids', () {
      PreflightRequest build() => fromState(
        basket: [rawLine(upc: '111')],
        balances: {'MILK - WHOLE': rawBalance(used: 1)},
        evidenceByUpc: {'111': evidence(aplEligible: false)},
      );

      final withSwap = planFor(
        build(),
        candidates: {
          '0:111:MILK - WHOLE': [candidate(upc: '222')],
        },
      );
      final withoutSwap = planFor(build());

      expect(withSwap.sourceFingerprint, withoutSwap.sourceFingerprint);
      expect(withSwap.planId, isNot(withoutSwap.planId));
    });

    test('a report from a different basket is refused', () {
      final staleReport = analyzer.analyze(handBuilt(quantity: 1, allowed: 2));

      expect(
        () => planner.propose(
          request: handBuilt(quantity: 3, allowed: 2),
          report: staleReport,
          candidatesByLine: const {},
        ),
        throwsArgumentError,
      );
    });
  });
}
