import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/domain/wolfguard_models.dart';
import 'package:wolfbite/features/wolfguard/engine/checkout_preflight_engine.dart';

import 'support/scenario_loader.dart';

const engine = CheckoutPreflightEngine();

void main() {
  final scenarios = loadScenarios();

  group('wolfguard_scenarios.json', () {
    test('is labeled synthetic and provides both M0-WG trial scenarios', () {
      final file = loadScenarioFile();

      expect(file['schema'], 'wolfguard-scenarios-v1');
      expect(file['label'], 'Synthetic sample; not live benefits.');
      expect(scenarios.where((s) => s.use == 'm0-trial').map((s) => s.id), [
        'WG-S1',
        'WG-S2',
      ]);
      expect(scenarios.map((s) => s.id).toSet(), hasLength(scenarios.length));
    });

    for (final scenario in scenarios) {
      test('${scenario.id} produces its expected report', () {
        final report = engine.analyze(scenario.request);
        final expected = scenario.expected;

        expect(report.totalUnits, expected['totalUnits']);
        expect(report.coveredUnits, expected['coveredUnits']);
        expect(report.selfPayUnits, expected['selfPayUnits']);
        expect(report.blockedUnits, expected['blockedUnits']);
        expect(report.unknownUnits, expected['unknownUnits']);
        expect(report.readyForHandoff, expected['readyForHandoff']);
        expect({
          for (final line in report.lines) line.lineKey: line.status.name,
        }, expected['lineStatus']);
        expect({
          for (final line in report.lines)
            if (line.issues.isNotEmpty)
              line.lineKey: [for (final issue in line.issues) issue.code.name],
        }, expected['issueCodes']);
      });
    }

    test('M0-WG oracles agree with the engine', () {
      for (final scenario in scenarios.where((s) => s.oracle != null)) {
        final report = engine.analyze(scenario.request);
        final oracle = scenario.oracle!;
        final blocked = {
          for (final line in report.lines)
            if (line.status == PreflightStatus.blocked) line.lineKey,
        };
        final unknown = {
          for (final line in report.lines)
            if (line.status == PreflightStatus.unknown) line.lineKey,
        };
        final actionable = oracle['actionableIssues'] as List;

        expect(
          {for (final issue in actionable) (issue as Map)['lineKey']},
          blocked,
          reason: scenario.id,
        );
        for (final issue in actionable.cast<Map<String, dynamic>>()) {
          final codes = report.lineFor(issue['lineKey'] as String)!.issues;
          expect(codes.map((i) => i.code.name), contains(issue['code']));
          for (final repair in issue['acceptableRepairs'] as List) {
            expect(FixKind.values.map((k) => k.name), contains(repair));
          }
        }
        expect(oracle['unknownRequiringReview'], unknown.toList());
      }
    });
  });
}
