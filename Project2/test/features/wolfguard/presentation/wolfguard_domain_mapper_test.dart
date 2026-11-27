import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/domain/wolfguard_models.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_display_models.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_domain_mapper.dart';

const _line = BasketLineSnapshot(
  lineKey: '0:111:MILK',
  upc: '111',
  name: 'Test milk',
  basketCategory: 'MILK',
  quantity: 4,
);

PreflightRequest _request() => PreflightRequest(
  lines: const [_line],
  benefits: const {},
  evaluatedAt: DateTime.utc(2026, 11, 27),
);

LinePreflightResult _result({
  required PreflightStatus status,
  int covered = 0,
  int selfPay = 0,
  int blocked = 0,
  int unknown = 0,
  List<PreflightIssue> issues = const [],
}) => LinePreflightResult(
  lineKey: _line.lineKey,
  status: status,
  quantity: covered + selfPay + blocked + unknown,
  coveredUnits: covered,
  selfPayUnits: selfPay,
  blockedUnits: blocked,
  unknownUnits: unknown,
  issues: issues,
);

PreflightReport _report(LinePreflightResult result) => PreflightReport(
  lines: [result],
  requestFingerprint: _request().fingerprint,
);

void main() {
  test('report mapping preserves counts, product, issue, and evidence', () {
    final issue = PreflightIssue(
      code: IssueCode.packageMismatch,
      lineKey: _line.lineKey,
      title: 'Package mismatch',
      explanation: 'Test milk is 24 oz; the evidence permits 18 oz.',
      suggestedNextStep: 'Choose a verified 18 oz package.',
      evidenceLabels: ['selected: 24 oz', 'permitted: 18 oz'],
    );
    final request = _request();
    final domain = PreflightReport(
      lines: [
        _result(
          status: PreflightStatus.blocked,
          covered: 1,
          blocked: 3,
          issues: [issue],
        ),
      ],
      requestFingerprint: request.fingerprint,
    );

    final view = WolfGuardDomainMapper.report(request, domain);

    expect(view.summary.totalUnits, 4);
    expect(view.summary.coveredUnits, 1);
    expect(view.summary.blockedUnits, 3);
    expect(view.summary.state, WolfGuardCardState.attention);
    expect(view.lines.single.productName, 'Test milk');
    expect(view.lines.single.status, WolfGuardLineStatus.blocked);
    expect(view.lines.single.actionLabel, 'Preview safe repair');
    expect(view.lines.single.issues.single.title, 'Package mismatch');
    expect(view.lines.single.issues.single.evidenceLabels, [
      'selected: 24 oz',
      'permitted: 18 oz',
    ]);
  });

  test('explicit self-pay domain result is ready for handoff', () {
    final request = _request();
    final view = WolfGuardDomainMapper.report(
      request,
      PreflightReport(
        lines: [_result(status: PreflightStatus.selfPay, selfPay: 4)],
        requestFingerprint: request.fingerprint,
      ),
    );

    expect(view.summary.selfPayAcknowledged, isTrue);
    expect(view.summary.readyForHandoff, isTrue);
    expect(view.lines.single.status, WolfGuardLineStatus.selfPay);
    expect(view.lines.single.actionLabel, isNull);
  });

  test('empty report maps to the empty card state', () {
    final request = PreflightRequest(
      lines: const [],
      benefits: const {},
      evaluatedAt: DateTime.utc(2026, 11, 27),
    );
    final report = PreflightReport(
      lines: const [],
      requestFingerprint: request.fingerprint,
    );

    expect(
      WolfGuardDomainMapper.report(request, report).summary.state,
      WolfGuardCardState.empty,
    );
  });

  test('fix plan maps every action and projected counts', () {
    final before = _report(
      _result(status: PreflightStatus.unknown, unknown: 4),
    );
    final after = _report(_result(status: PreflightStatus.selfPay, selfPay: 4));
    final plan = FixPlan(
      planId: 'plan-1',
      sourceFingerprint: before.requestFingerprint,
      actions: const [
        FixAction(
          actionId: 'keep-paid',
          kind: FixKind.keepAsSelfPay,
          lineKey: '0:111:MILK',
          shopperExplanation: 'Keep Test milk self-paid.',
        ),
      ],
      before: before,
      projectedAfter: after,
    );

    final view = WolfGuardDomainMapper.fixPlan(plan);

    expect(view.planId, 'plan-1');
    expect(view.before.unknownUnits, 4);
    expect(view.projectedAfter.selfPayUnits, 4);
    expect(view.projectedAfter.readyForHandoff, isTrue);
    expect(view.actions.single.title, 'Keep item self-paid');
    expect(view.actions.single.description, 'Keep Test milk self-paid.');
  });

  test('apply outcomes map one-to-one without losing failures', () {
    expect(
      ApplyPlanResult.values.map(WolfGuardDomainMapper.applyOutcome),
      WolfGuardApplyViewOutcome.values,
    );
  });
}
