import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/domain/wolfguard_models.dart';
import 'package:wolfbite/features/wolfguard/engine/checkout_preflight_engine.dart';

import 'support/preflight_builders.dart';

const engine = CheckoutPreflightEngine();
const milk = 'MILK - WHOLE';
const cereal = 'BREAKFAST CEREAL';

void main() {
  group('whole-basket allowance allocation (FR-1, FR-3)', () {
    test('units within the remaining allowance are expected covered', () {
      final report = engine.analyze(
        request([line('a', quantity: 2)], [benefit(milk, allowed: 3)]),
      );

      final a = report.lineFor('a')!;
      expect(a.status, PreflightStatus.covered);
      expect(a.coveredUnits, 2);
      expect(a.issues, isEmpty);
      expect(report.readyForHandoff, isTrue);
    });

    test('units beyond the remaining allowance are blocked, not self-paid', () {
      final report = engine.analyze(
        request([line('a', quantity: 3)], [benefit(milk, allowed: 3, used: 1)]),
      );

      final a = report.lineFor('a')!;
      expect(a.status, PreflightStatus.blocked);
      expect(a.coveredUnits, 2);
      expect(a.blockedUnits, 1);
      expect(a.selfPayUnits, 0);
      expect(codesFor(report, 'a'), [IssueCode.allowanceExceeded]);
      expect(a.issues.single.explanation, contains('Product a'));
      expect(
        a.issues.single.suggestedNextStep,
        contains('Reduce the quantity'),
      );
      expect(report.readyForHandoff, isFalse);
    });

    test('allowance is shared across lines in stable basket order', () {
      final report = engine.analyze(
        request(
          [
            line('first', upc: '1', quantity: 2),
            line('second', upc: '2', quantity: 2),
          ],
          [benefit(milk, allowed: 3)],
        ),
      );

      expect(report.lineFor('first')!.coveredUnits, 2);
      expect(report.lineFor('second')!.coveredUnits, 1);
      expect(report.lineFor('second')!.blockedUnits, 1);
    });

    test('reordering lines moves the blocked unit to the later line', () {
      final report = engine.analyze(
        request(
          [
            line('second', upc: '2', quantity: 2),
            line('first', upc: '1', quantity: 2),
          ],
          [benefit(milk, allowed: 3)],
        ),
      );

      expect(report.lineFor('second')!.blockedUnits, 0);
      expect(report.lineFor('first')!.blockedUnits, 1);
    });

    test('categories draw on separate allowances', () {
      final report = engine.analyze(
        request(
          [
            line('milk', upc: '1', quantity: 3),
            line('cereal', upc: '2', category: cereal, quantity: 2),
          ],
          [benefit(milk, allowed: 3), benefit(cereal, allowed: 2)],
        ),
      );

      expect(report.coveredUnits, 5);
      expect(report.blockedUnits, 0);
    });

    test('an allowance of zero is explicit evidence and blocks every unit', () {
      final report = engine.analyze(
        request([line('a', quantity: 1)], [benefit(milk, allowed: 0, used: 0)]),
      );

      final a = report.lineFor('a')!;
      expect(a.status, PreflightStatus.blocked);
      expect(a.blockedUnits, 1);
      expect(a.issues.single.suggestedNextStep, contains('Remove the line'));
    });

    test('prototype-uncapped categories are covered and labeled', () {
      const cvb = 'FRUIT & VEGETABLE CVB';
      final report = engine.analyze(
        request(
          [line('fv', category: cvb, quantity: 40)],
          [benefit(cvb, allowed: null)],
        ),
      );

      final fv = report.lineFor('fv')!;
      expect(fv.status, PreflightStatus.covered);
      expect(fv.coveredUnits, 40);
      expect(fv.notes.single, contains('Prototype-uncapped'));
      expect(fv.notes.single, contains('not an official unlimited benefit'));
    });

    test('a category missing from the allowance is blocked', () {
      final report = engine.analyze(request([line('a')], const []));

      expect(report.lineFor('a')!.status, PreflightStatus.blocked);
      expect(codesFor(report, 'a'), [IssueCode.notInCurrentBenefits]);
    });
  });

  group('PAID lines (FR-1, FR-2)', () {
    test('covered and PAID lines with the same UPC stay distinct', () {
      final report = engine.analyze(
        request(
          [
            line('benefit', upc: '41303', quantity: 3),
            line(
              'paid',
              upc: '41303',
              category: wolfGuardPaidCategory,
              original: milk,
              quantity: 1,
            ),
          ],
          [benefit(milk, allowed: 3)],
        ),
      );

      expect(report.lines, hasLength(2));
      expect(report.lineFor('benefit')!.coveredUnits, 3);
      final paid = report.lineFor('paid')!;
      expect(paid.status, PreflightStatus.selfPay);
      expect(paid.selfPayUnits, 1);
      expect(
        paid.issues.single.evidenceLabels,
        contains('Original benefit category: $milk'),
      );
      expect(report.readyForHandoff, isTrue);
    });

    test('PAID lines never consume the benefit allowance', () {
      final report = engine.analyze(
        request(
          [
            line(
              'paid',
              upc: '1',
              category: wolfGuardPaidCategory,
              original: milk,
              quantity: 5,
            ),
            line('benefit', upc: '2', quantity: 3),
          ],
          [benefit(milk, allowed: 3)],
        ),
      );

      expect(report.lineFor('benefit')!.coveredUnits, 3);
      expect(report.selfPayUnits, 5);
    });

    test('a PAID line without its original category is unknown', () {
      final report = engine.analyze(
        request([
          line(
            'paid',
            upc: '9',
            category: wolfGuardPaidCategory,
            useDefaultOriginal: false,
          ),
        ]),
      );

      expect(report.lineFor('paid')!.status, PreflightStatus.unknown);
      expect(codesFor(report, 'paid'), [IssueCode.insufficientEvidence]);
    });

    test(
      'a missing original category is recovered from exact-UPC evidence',
      () {
        final report = engine.analyze(
          request([
            line(
              'paid',
              upc: '9',
              category: wolfGuardPaidCategory,
              useDefaultOriginal: false,
              evidence: apl(cereal),
            ),
          ]),
        );

        final paid = report.lineFor('paid')!;
        expect(paid.status, PreflightStatus.selfPay);
        expect(
          paid.issues.single.evidenceLabels.last,
          contains('recovered from exact-UPC evidence'),
        );
      },
    );

    test('conflicting exact-UPC evidence leaves the PAID line unknown', () {
      final report = engine.analyze(
        request(
          [
            line('benefit', upc: '9', quantity: 1),
            line(
              'paid',
              upc: '9',
              category: wolfGuardPaidCategory,
              useDefaultOriginal: false,
              evidence: apl(cereal),
            ),
          ],
          [benefit(milk)],
        ),
      );

      expect(report.lineFor('paid')!.status, PreflightStatus.unknown);
      expect(codesFor(report, 'paid'), [IssueCode.contradictoryEvidence]);
    });
  });

  group('basket-level accounting', () {
    test('category spelling variants share one canonical allowance', () {
      final report = engine.analyze(
        request(
          [
            line(
              'a',
              upc: '1',
              category: 'MILK-WHOLE',
              evidence: apl(milk),
              quantity: 2,
            ),
            line(
              'b',
              upc: '2',
              category: 'milk - whole',
              evidence: apl('MILK-WHOLE'),
              quantity: 2,
            ),
          ],
          [benefit(milk, allowed: 3)],
        ),
      );

      expect(report.coveredUnits, 3);
      expect(report.lineFor('b')!.blockedUnits, 1);
    });

    test('an unknown line holds its share of a capped allowance', () {
      final report = engine.analyze(
        request(
          [
            line(
              'stale',
              upc: '1',
              quantity: 2,
              evidence: apl(milk, freshness: EvidenceFreshness.stale),
            ),
            line('fresh', upc: '2', quantity: 2),
          ],
          [benefit(milk, allowed: 3)],
        ),
      );

      expect(report.lineFor('stale')!.unknownUnits, 2);
      final fresh = report.lineFor('fresh')!;
      expect(fresh.coveredUnits, 1);
      expect(fresh.blockedUnits, 1);
      expect(fresh.issues.single.explanation, contains('held for earlier'));
    });

    test('an empty basket has no readiness and is not ready for handoff', () {
      final report = engine.analyze(request(const [], [benefit(milk)]));

      expect(report.totalUnits, 0);
      expect(report.readyForHandoff, isFalse);
      expect(report.readinessPercent(), isNull);
    });

    test('report fingerprint is the request fingerprint', () {
      final req = request([line('a')], [benefit(milk)]);

      expect(engine.analyze(req).requestFingerprint, req.fingerprint);
    });
  });
}
