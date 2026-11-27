import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/domain/wolfguard_models.dart';
import 'package:wolfbite/features/wolfguard/engine/checkout_preflight_engine.dart';

import 'support/preflight_builders.dart';

const engine = CheckoutPreflightEngine();
const milk = 'MILK - WHOLE';
const cereal = 'BREAKFAST CEREAL';
const cvb = 'FRUIT & VEGETABLE CVB';

T pick<T>(Random random, List<T> options) =>
    options[random.nextInt(options.length)];

/// A random, often malformed basket. Seeded, so failures are reproducible.
PreflightRequest randomRequest(Random random, {int maxLines = 8}) {
  final lines = <BasketLineSnapshot>[];
  final count = random.nextInt(maxLines + 1);
  for (var i = 0; i < count; i++) {
    final category = pick(random, [
      milk,
      milk,
      cereal,
      cvb,
      'JUICE 64',
      wolfGuardPaidCategory,
      'UNKNOWN',
    ]);
    final evidence = pick<ProductEvidence?>(random, [
      null,
      apl(category),
      apl(category),
      apl(category, freshness: EvidenceFreshness.stale),
      apl(category, eligible: false),
      apl(category, eligible: null),
      apl(cereal),
    ]);
    lines.add(
      line(
        'L$i',
        upc: pick(random, ['111', '222', '333', '']),
        category: category,
        original: category == wolfGuardPaidCategory
            ? pick<String?>(random, [milk, null])
            : null,
        quantity: random.nextInt(6) - 1,
        evidence: evidence,
        noEvidence: evidence == null,
      ),
    );
  }
  final benefits = [
    for (final category in [milk, cereal, cvb])
      if (random.nextInt(5) > 0)
        benefit(
          category,
          allowed: category == cvb ? null : pick<int?>(random, [0, 1, 2, 3, 4]),
          used: random.nextInt(6) - 1,
          freshness: pick(random, [
            EvidenceFreshness.current,
            EvidenceFreshness.current,
            EvidenceFreshness.current,
            EvidenceFreshness.stale,
          ]),
        ),
  ];
  return request(lines, benefits);
}

void main() {
  group('preflight invariants over 500 seeded random baskets', () {
    final requests = [
      for (var seed = 0; seed < 500; seed++) randomRequest(Random(seed)),
    ];

    test('every unit lands in exactly one outcome', () {
      for (final req in requests) {
        final report = engine.analyze(req);
        for (var i = 0; i < req.lines.length; i++) {
          final quantity = req.lines[i].quantity;
          expect(
            report.lines[i].accountedUnits,
            quantity > 0 ? quantity : 1,
            reason: req.fingerprint,
          );
        }
        expect(
          report.coveredUnits +
              report.selfPayUnits +
              report.blockedUnits +
              report.unknownUnits,
          report.totalUnits,
        );
      }
    });

    test('unknown or unsafe evidence is never counted as covered', () {
      for (final req in requests) {
        final report = engine.analyze(req);
        for (var i = 0; i < req.lines.length; i++) {
          final evidence = req.lines[i].evidence;
          final safe =
              evidence != null &&
              evidence.freshness == EvidenceFreshness.current &&
              evidence.aplEligible == true &&
              evidence.canonicalCategory == req.lines[i].basketCategory;
          if (!safe) {
            expect(report.lines[i].coveredUnits, 0, reason: req.fingerprint);
          }
        }
      }
    });

    test('covered units never exceed a capped remaining allowance', () {
      for (final req in requests) {
        final report = engine.analyze(req);
        for (final b in req.benefits.values) {
          final allowed = b.allowed;
          if (allowed == null) continue;
          var covered = 0;
          for (var i = 0; i < req.lines.length; i++) {
            if (req.lines[i].basketCategory == b.category) {
              covered += report.lines[i].coveredUnits;
            }
          }
          expect(
            covered,
            lessThanOrEqualTo(max(0, allowed - b.used)),
            reason: req.fingerprint,
          );
        }
      }
    });

    test('a line status always matches its unit counts', () {
      for (final req in requests) {
        for (final result in engine.analyze(req).lines) {
          final expected = result.unknownUnits > 0
              ? PreflightStatus.unknown
              : result.blockedUnits > 0
              ? PreflightStatus.blocked
              : result.selfPayUnits > 0
              ? PreflightStatus.selfPay
              : PreflightStatus.covered;
          expect(result.status, expected);
          if (result.status != PreflightStatus.covered) {
            expect(result.issues, isNotEmpty, reason: result.lineKey);
          }
        }
      }
    });

    test('analysis is deterministic for equal requests', () {
      for (var seed = 0; seed < 100; seed++) {
        final a = engine.analyze(randomRequest(Random(seed)));
        final b = engine.analyze(randomRequest(Random(seed)));
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      }
    });
  });

  group('purity', () {
    test('analysis leaves the request and its source lists unchanged', () {
      final lines = [line('a', quantity: 4), line('b', upc: '2')];
      final benefits = {milk: benefit(milk, allowed: 3)};
      final req = PreflightRequest(
        lines: lines,
        benefits: benefits,
        evaluatedAt: evaluatedAt,
      );
      final fingerprintBefore = req.fingerprint;

      engine.analyze(req);
      engine.analyze(req);

      expect(req.lines, [line('a', quantity: 4), line('b', upc: '2')]);
      expect(req.benefits, {milk: benefit(milk, allowed: 3)});
      expect(req.fingerprint, fingerprintBefore);
    });

    test('100-line analysis completes within 100 ms (NFR-1)', () {
      final lines = [
        for (var i = 0; i < 100; i++)
          line(
            'L$i',
            upc: '$i',
            category: i.isEven ? milk : cereal,
            quantity: 1 + i % 3,
          ),
      ];
      final req = request(lines, [
        benefit(milk, allowed: 60),
        benefit(cereal, allowed: 40),
      ]);
      engine.analyze(req);

      final stopwatch = Stopwatch()..start();
      final report = engine.analyze(req);
      stopwatch.stop();

      expect(report.lines, hasLength(100));
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });
  });
}
