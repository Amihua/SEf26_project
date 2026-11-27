import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/domain/wolfguard_models.dart';
import 'package:wolfbite/features/wolfguard/engine/checkout_preflight_engine.dart';
import 'package:wolfbite/features/wolfguard/engine/preflight_rules.dart';

import 'support/preflight_builders.dart';

const engine = CheckoutPreflightEngine();
const milk = 'MILK - WHOLE';
const cereal = 'BREAKFAST CEREAL';

PreflightReport analyzeOne(
  BasketLineSnapshot basketLine, {
  BenefitCategorySnapshot? allowance,
}) => engine.analyze(request([basketLine], [allowance ?? benefit(milk)]));

void main() {
  group('conservative evidence handling (FR-2)', () {
    test('missing APL evidence cannot produce covered', () {
      final report = analyzeOne(line('a', noEvidence: true));

      expect(report.lineFor('a')!.status, PreflightStatus.unknown);
      expect(report.coveredUnits, 0);
      expect(codesFor(report, 'a'), [IssueCode.insufficientEvidence]);
    });

    test('stale catalog evidence produces a named stale issue', () {
      final report = analyzeOne(
        line('a', evidence: apl(milk, freshness: EvidenceFreshness.stale)),
      );

      expect(report.lineFor('a')!.status, PreflightStatus.unknown);
      expect(codesFor(report, 'a'), [IssueCode.staleEvidence]);
    });

    test('evidence of unconfirmed freshness stays unknown', () {
      final report = analyzeOne(
        line('a', evidence: apl(milk, freshness: EvidenceFreshness.unknown)),
      );

      expect(report.lineFor('a')!.status, PreflightStatus.unknown);
    });

    test('APL ineligible evidence blocks the line', () {
      final report = analyzeOne(
        line('a', evidence: apl(milk, eligible: false)),
      );

      final a = report.lineFor('a')!;
      expect(a.status, PreflightStatus.blocked);
      expect(codesFor(report, 'a'), [IssueCode.notInCurrentBenefits]);
      expect(
        a.issues.single.evidenceLabels.single,
        contains('eligible = false'),
      );
    });

    test('evidence without an eligibility flag stays unknown', () {
      final report = analyzeOne(line('a', evidence: apl(milk, eligible: null)));

      expect(report.lineFor('a')!.status, PreflightStatus.unknown);
    });

    test('catalog category that contradicts the basket is unknown', () {
      final report = analyzeOne(line('a', evidence: apl(cereal)));

      expect(report.lineFor('a')!.status, PreflightStatus.unknown);
      expect(codesFor(report, 'a'), [IssueCode.contradictoryEvidence]);
    });

    test(
      'basket and recorded benefit categories that disagree are unknown',
      () {
        final report = analyzeOne(line('a', original: cereal));

        expect(codesFor(report, 'a'), [IssueCode.contradictoryEvidence]);
      },
    );

    test('a blank UPC cannot be matched to the APL', () {
      final report = analyzeOne(line('a', upc: '   '));

      expect(report.lineFor('a')!.status, PreflightStatus.unknown);
      expect(report.lineFor('a')!.issues.single.title, 'Product code missing');
    });

    for (final raw in ['UNKNOWN', '   ', '']) {
      test('basket category "$raw" is unknown, not covered', () {
        final report = analyzeOne(
          line(
            'a',
            category: raw,
            useDefaultOriginal: false,
            evidence: apl(milk),
          ),
        );

        expect(report.lineFor('a')!.status, PreflightStatus.unknown);
        expect(codesFor(report, 'a'), [IssueCode.insufficientEvidence]);
      });
    }

    for (final quantity in [0, -2]) {
      test('quantity $quantity is one unknown unit, never clamped', () {
        final report = analyzeOne(line('a', quantity: quantity));

        final a = report.lineFor('a')!;
        expect(a.status, PreflightStatus.unknown);
        expect(a.quantity, quantity);
        expect(a.unknownUnits, 1);
        expect(report.totalUnits, 1);
        expect(report.readyForHandoff, isFalse);
      });
    }
  });

  group('allowance record checks (FR-3)', () {
    test(
      'used greater than allowed is contradictory, not a negative balance',
      () {
        final report = analyzeOne(
          line('a'),
          allowance: benefit(milk, allowed: 3, used: 4),
        );

        final a = report.lineFor('a')!;
        expect(a.status, PreflightStatus.unknown);
        expect(codesFor(report, 'a'), [IssueCode.contradictoryEvidence]);
        expect(a.issues.single.explanation, contains('4 used of 3 allowed'));
      },
    );

    test('a negative used counter is contradictory', () {
      final report = analyzeOne(
        line('a'),
        allowance: benefit(milk, allowed: null, used: -1),
      );

      expect(codesFor(report, 'a'), [IssueCode.contradictoryEvidence]);
    });

    test('a stale allowance record produces a named stale issue', () {
      final report = analyzeOne(
        line('a'),
        allowance: benefit(milk, freshness: EvidenceFreshness.stale),
      );

      expect(report.lineFor('a')!.status, PreflightStatus.unknown);
      expect(codesFor(report, 'a'), [IssueCode.staleEvidence]);
    });
  });

  group('explicit package evidence (FR-2)', () {
    BenefitCategorySnapshot cerealRule() =>
        benefit(cereal, allowed: 2, package: const PackageAmount(18, 'oz'));

    test('a different size in the same unit is a package mismatch', () {
      final report = analyzeOne(
        line(
          'c',
          category: cereal,
          evidence: apl(cereal, size: const PackageAmount(24, 'oz')),
        ),
        allowance: cerealRule(),
      );

      final c = report.lineFor('c')!;
      expect(c.status, PreflightStatus.blocked);
      expect(codesFor(report, 'c'), [IssueCode.packageMismatch]);
      expect(c.issues.single.explanation, contains('24 oz'));
      expect(c.issues.single.explanation, contains('18 oz'));
    });

    test('sizes that differ only by floating-point noise match', () {
      final report = analyzeOne(
        line(
          'c',
          category: cereal,
          evidence: apl(cereal, size: const PackageAmount(0.1 + 0.2, 'OZ')),
        ),
        allowance: benefit(
          cereal,
          allowed: 2,
          package: const PackageAmount(0.3, 'oz'),
        ),
      );

      final c = report.lineFor('c')!;
      expect(c.status, PreflightStatus.covered);
      expect(c.notes.single, contains('matches explicit evidence'));
    });

    test('different units are unknown; no conversion is guessed', () {
      final report = analyzeOne(
        line(
          'c',
          category: cereal,
          evidence: apl(cereal, size: const PackageAmount(510, 'g')),
        ),
        allowance: cerealRule(),
      );

      expect(report.lineFor('c')!.status, PreflightStatus.unknown);
      expect(
        report.lineFor('c')!.issues.single.explanation,
        contains('does not convert between units'),
      );
    });

    test('a missing selected package size stays unknown', () {
      final report = analyzeOne(
        line('c', category: cereal, evidence: apl(cereal)),
        allowance: cerealRule(),
      );

      expect(report.lineFor('c')!.status, PreflightStatus.unknown);
      expect(report.lineFor('c')!.issues.single.title, 'Package size unknown');
    });

    test('no package rule means package evidence is not required', () {
      final report = analyzeOne(line('a'));

      expect(report.lineFor('a')!.status, PreflightStatus.covered);
    });

    test('unsupported units and nonpositive sizes are not comparable', () {
      const permitted = PackageAmount(18, 'oz');

      expect(
        PackageRules.compare(const PackageAmount(1, 'box'), permitted),
        PackageComparison.notComparable,
      );
      expect(
        PackageRules.compare(const PackageAmount(0, 'oz'), permitted),
        PackageComparison.notComparable,
      );
      expect(
        PackageRules.compare(const PackageAmount(double.nan, 'oz'), permitted),
        PackageComparison.notComparable,
      );
      expect(
        PackageRules.compare(const PackageAmount(18, ' Oz '), permitted),
        PackageComparison.match,
      );
    });
  });

  group('programmer-contract violations', () {
    test('duplicate line keys throw', () {
      expect(
        () => engine.analyze(
          request(
            [line('dup', upc: '1'), line('dup', upc: '2')],
            [benefit(milk)],
          ),
        ),
        throwsArgumentError,
      );
    });

    test('two different records for one canonical category throw', () {
      final req = PreflightRequest(
        lines: [line('a')],
        benefits: {
          'MILK - WHOLE': benefit(milk, allowed: 3),
          'MILK-WHOLE': benefit(milk, allowed: 4),
        },
        evaluatedAt: evaluatedAt,
      );

      expect(() => engine.analyze(req), throwsArgumentError);
    });
  });
}
