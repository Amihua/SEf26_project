import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/domain/wolfguard_models.dart';

import 'support/preflight_builders.dart';

const milk = 'MILK - WHOLE';

LinePreflightResult result(
  String key, {
  int covered = 0,
  int selfPay = 0,
  int blocked = 0,
  int unknown = 0,
  PreflightStatus status = PreflightStatus.covered,
}) => LinePreflightResult(
  lineKey: key,
  status: status,
  quantity: covered + selfPay + blocked + unknown,
  coveredUnits: covered,
  selfPayUnits: selfPay,
  blockedUnits: blocked,
  unknownUnits: unknown,
);

void main() {
  group('shared WolfGuard contract', () {
    test('report totals are always the sum of its lines', () {
      final report = PreflightReport(
        lines: [
          result('a', covered: 2, blocked: 1, status: PreflightStatus.blocked),
          result('b', selfPay: 1, status: PreflightStatus.selfPay),
          result('c', unknown: 2, status: PreflightStatus.unknown),
        ],
        requestFingerprint: 'fp',
      );

      expect(report.totalUnits, 6);
      expect(report.coveredUnits, 2);
      expect(report.selfPayUnits, 1);
      expect(report.blockedUnits, 1);
      expect(report.unknownUnits, 2);
      expect(report.readyForHandoff, isFalse);
    });

    test('readiness counts only acknowledged self-paid units', () {
      final report = PreflightReport(
        lines: [
          result('a', covered: 2),
          result('b', selfPay: 2, status: PreflightStatus.selfPay),
        ],
        requestFingerprint: 'fp',
      );

      expect(report.readinessPercent(), 50);
      expect(report.readinessPercent(acknowledgedSelfPayUnits: 1), 75);
      expect(report.readinessPercent(acknowledgedSelfPayUnits: 9), 100);
    });

    test('fingerprint ignores evaluation time but tracks every input', () {
      final base = request([line('a', quantity: 2)], [benefit(milk)]);
      final later = PreflightRequest(
        lines: base.lines,
        benefits: base.benefits,
        evaluatedAt: evaluatedAt.add(const Duration(hours: 5)),
      );
      final changes = [
        request([line('a', quantity: 3)], [benefit(milk)]),
        request([line('a', quantity: 2, upc: '9')], [benefit(milk)]),
        request(
          [line('a', quantity: 2, evidence: apl(milk, eligible: false))],
          [benefit(milk)],
        ),
        request([line('a', quantity: 2)], [benefit(milk, used: 1)]),
        request(
          [line('a', quantity: 2)],
          [benefit(milk, freshness: EvidenceFreshness.stale)],
        ),
      ];

      expect(later.fingerprint, base.fingerprint);
      expect(base.fingerprint, startsWith('wg1-'));
      for (final changed in changes) {
        expect(changed.fingerprint, isNot(base.fingerprint));
      }
    });

    test('requests copy and freeze their collections', () {
      final lines = [line('a')];
      final benefits = {milk: benefit(milk)};
      final req = PreflightRequest(
        lines: lines,
        benefits: benefits,
        evaluatedAt: evaluatedAt,
      );

      lines.add(line('b', upc: '2'));
      benefits.clear();

      expect(req.lines, hasLength(1));
      expect(req.benefits, hasLength(1));
      expect(() => req.lines.add(line('c')), throwsUnsupportedError);
      expect(() => req.benefits.clear(), throwsUnsupportedError);
    });

    test('value types compare by value', () {
      expect(const PackageAmount(18, 'oz'), const PackageAmount(18.0, 'oz'));
      expect(
        const PackageAmount(18, 'oz').hashCode,
        const PackageAmount(18.0, 'oz').hashCode,
      );
      expect(line('a'), line('a'));
      expect(line('a'), isNot(line('a', quantity: 2)));
      expect(
        PreflightReport(
          lines: [result('a', covered: 1)],
          requestFingerprint: 'x',
        ),
        PreflightReport(
          lines: [result('a', covered: 1)],
          requestFingerprint: 'x',
        ),
      );
    });

    test('lineFor returns null for a key the report does not contain', () {
      final report = PreflightReport(lines: const [], requestFingerprint: 'x');

      expect(report.lineFor('missing'), isNull);
    });
  });
}
