import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_display_models.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_domain_rehearsal_driver.dart';

void main() {
  test('production engine produces all four synthetic outcomes', () async {
    final report = await WolfGuardDomainRehearsalDriver().loadReport();

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
    'production engine explains explicit package mismatch evidence',
    () async {
      final report = await WolfGuardDomainRehearsalDriver().loadReport();
      final blocked = report.lines.singleWhere(
        (line) => line.status == WolfGuardLineStatus.blocked,
      );

      expect(blocked.productName, 'Synthetic blocked cereal');
      expect(blocked.issues.single.title, contains('Package size'));
      expect(blocked.issues.single.explanation, contains('24 oz'));
      expect(blocked.issues.single.explanation, contains('18 oz'));
      expect(blocked.issues.single.evidenceLabels, isNotEmpty);
    },
  );

  test('production planner previews both conservative repairs', () async {
    final driver = WolfGuardDomainRehearsalDriver();
    final report = await driver.loadReport();
    final blocked = report.lines.singleWhere(
      (line) => line.status == WolfGuardLineStatus.blocked,
    );

    final plan = await driver.planFor(blocked);

    expect(plan, isNotNull);
    expect(plan!.actions, hasLength(2));
    expect(
      plan.actions.every((action) => action.title == 'Keep item self-paid'),
      isTrue,
    );
    expect(plan.projectedAfter.coveredUnits, 1);
    expect(plan.projectedAfter.selfPayUnits, 3);
    expect(plan.projectedAfter.readyForHandoff, isTrue);
  });

  test('production applier changes only isolated rehearsal state', () async {
    final driver = WolfGuardDomainRehearsalDriver();
    final before = await driver.loadReport();
    final plan = await driver.planFor(
      before.lines.singleWhere(
        (line) => line.status == WolfGuardLineStatus.blocked,
      ),
    );

    expect(await driver.apply(plan!), WolfGuardApplyViewOutcome.applied);
    final after = await driver.loadReport();

    expect(after.summary.coveredUnits, 1);
    expect(after.summary.selfPayUnits, 3);
    expect(after.summary.blockedUnits, 0);
    expect(after.summary.unknownUnits, 0);
    expect(after.summary.readyForHandoff, isTrue);
  });

  test('unknown and repeated plans are rejected as stale', () async {
    final driver = WolfGuardDomainRehearsalDriver();
    final report = await driver.loadReport();
    final plan = await driver.planFor(
      report.lines.singleWhere(
        (line) => line.status == WolfGuardLineStatus.blocked,
      ),
    );
    final foreign = WolfGuardFixPlanViewData(
      planId: 'foreign-plan',
      before: plan!.before,
      projectedAfter: plan.projectedAfter,
      actions: plan.actions,
    );

    expect(await driver.apply(foreign), WolfGuardApplyViewOutcome.stalePlan);
    expect(await driver.apply(plan), WolfGuardApplyViewOutcome.applied);
    expect(await driver.apply(plan), WolfGuardApplyViewOutcome.stalePlan);
  });

  test('new rehearsal sessions are deterministic and isolated', () async {
    final first = WolfGuardDomainRehearsalDriver();
    final second = WolfGuardDomainRehearsalDriver();
    final report = await first.loadReport();
    final plan = await first.planFor(
      report.lines.singleWhere(
        (line) => line.status == WolfGuardLineStatus.blocked,
      ),
    );
    await first.apply(plan!);

    final untouched = await second.loadReport();

    expect(untouched.summary.blockedUnits, 1);
    expect(untouched.summary.unknownUnits, 1);
  });
}
