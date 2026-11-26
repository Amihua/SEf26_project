import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_display_models.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_synthetic_rehearsal_driver.dart';

void main() {
  test('initial fixture contains every outcome exactly once', () async {
    final report = await WolfGuardSyntheticRehearsalDriver().loadReport();

    expect(report.summary.totalUnits, 4);
    expect(report.summary.coveredUnits, 1);
    expect(report.summary.selfPayUnits, 1);
    expect(report.summary.blockedUnits, 1);
    expect(report.summary.unknownUnits, 1);
    expect(
      report.lines.map((line) => line.status).toSet(),
      WolfGuardLineStatus.values.toSet(),
    );
  });

  test(
    'fixture reports evidence and action for the affected products',
    () async {
      final report = await WolfGuardSyntheticRehearsalDriver().loadReport();
      final blocked = report.lines.singleWhere(
        (line) => line.status == WolfGuardLineStatus.blocked,
      );
      final unknown = report.lines.singleWhere(
        (line) => line.status == WolfGuardLineStatus.unknown,
      );

      expect(blocked.actionLabel, 'Preview sample repair');
      expect(blocked.issues.single.title, contains('package mismatch'));
      expect(blocked.issues.single.evidenceLabels, hasLength(2));
      expect(unknown.issues.single.title, contains('evidence missing'));
    },
  );

  test('sample repair previews both conservative changes', () async {
    final driver = WolfGuardSyntheticRehearsalDriver();
    final report = await driver.loadReport();
    final blocked = report.lines.singleWhere(
      (line) => line.status == WolfGuardLineStatus.blocked,
    );

    final plan = await driver.planFor(blocked);
    expect(plan, isNotNull);
    expect(plan!.actions, hasLength(2));
    expect(plan.projectedAfter.readyForHandoff, isTrue);
    expect(plan.projectedAfter.unknownUnits, 0);
  });

  test('apply produces a reviewed four-unit fixture', () async {
    final driver = WolfGuardSyntheticRehearsalDriver();
    final before = await driver.loadReport();
    final plan = await driver.planFor(
      before.lines.singleWhere(
        (line) => line.status == WolfGuardLineStatus.blocked,
      ),
    );

    expect(await driver.apply(plan!), WolfGuardApplyViewOutcome.applied);
    final after = await driver.loadReport();
    expect(after.summary.readyForHandoff, isTrue);
    expect(after.summary.coveredUnits, 2);
    expect(after.summary.selfPayUnits, 2);
    expect(after.summary.blockedUnits, 0);
    expect(after.summary.unknownUnits, 0);
  });

  test('unknown plan and repeated apply are rejected as stale', () async {
    final driver = WolfGuardSyntheticRehearsalDriver();
    final report = await driver.loadReport();
    final plan = await driver.planFor(
      report.lines.singleWhere(
        (line) => line.status == WolfGuardLineStatus.blocked,
      ),
    );
    final foreignPlan = WolfGuardFixPlanViewData(
      planId: 'foreign-plan',
      before: plan!.before,
      projectedAfter: plan.projectedAfter,
      actions: plan.actions,
    );

    expect(
      await driver.apply(foreignPlan),
      WolfGuardApplyViewOutcome.stalePlan,
    );
    expect(await driver.apply(plan), WolfGuardApplyViewOutcome.applied);
    expect(await driver.apply(plan), WolfGuardApplyViewOutcome.stalePlan);
  });

  test('new sessions are deterministic and isolated', () async {
    final first = WolfGuardSyntheticRehearsalDriver();
    final second = WolfGuardSyntheticRehearsalDriver();
    final firstReport = await first.loadReport();
    final plan = await first.planFor(
      firstReport.lines.singleWhere(
        (line) => line.status == WolfGuardLineStatus.blocked,
      ),
    );
    await first.apply(plan!);

    final untouched = await second.loadReport();
    expect(untouched.summary.blockedUnits, 1);
    expect(untouched.summary.unknownUnits, 1);
  });
}
