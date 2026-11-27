import '../domain/wolfguard_models.dart';
import '../domain/wolfguard_ports.dart';
import '../engine/preflight_rules.dart';
import 'basket_fingerprint.dart';

/// Builds the repair plan a shopper confirms before anything is changed.
///
/// The planner is pure: it reads a request and its report and returns a
/// proposal. It never touches application state, and nothing it returns has
/// any effect until [FixPlanApplier] is handed the plan.
///
/// ## How the after-state is produced
///
/// FR-4 requires the projected after-state to come from running the same
/// analyzer on a projected basket, never from adjusting the before-counts by
/// hand. So [propose] rewrites the line snapshots, hands the rewritten request
/// back to the analyzer, and reports whatever it says. When the engine's
/// allocation rules change, the preview changes with them.
///
/// ## Allowances are not re-derived here
///
/// `PreflightRequestBuilder` already subtracts the current basket from each
/// [BenefitCategorySnapshot.used], so a snapshot states the headroom available
/// *to this basket*. A projected basket therefore reuses the benefits
/// unchanged: removing a line must not hand units back to a counter that never
/// contained them.
///
/// ## One action per line
///
/// A plan holds at most one action per line, because every action in a plan is
/// applied together when the shopper confirms. Offering a choice between two
/// repairs for one line is a presentation concern, not a plan.
final class WolfGuardFixPlanner implements FixPlanner {
  const WolfGuardFixPlanner(this._analyzer);

  final PreflightAnalyzer _analyzer;

  @override
  FixPlan propose({
    required PreflightRequest request,
    required PreflightReport report,
    required Map<String, List<ReplacementCandidate>> candidatesByLine,
  }) {
    final fingerprint = BasketFingerprint.of(request);
    if (report.requestFingerprint != fingerprint) {
      throw ArgumentError.value(
        report.requestFingerprint,
        'report',
        'Report was computed from a different basket than the request. '
            'Re-run the analyzer before proposing a plan.',
      );
    }

    final linesByKey = {for (final l in request.lines) l.lineKey: l};
    final actions = <FixAction>[];
    for (final result in report.lines) {
      final line = linesByKey[result.lineKey];
      if (line == null) continue;
      final category = PreflightCategories.benefitCategory(
        line.originalBenefitCategory ?? line.basketCategory,
      );
      final action = _actionFor(
        line: line,
        result: result,
        category: category,
        benefit: category == null ? null : request.benefits[category],
        candidates: candidatesByLine[line.lineKey] ?? const [],
      );
      if (action != null) actions.add(action);
    }

    final projected = _project(request, actions);
    return FixPlan(
      planId: _planId(fingerprint, actions),
      sourceFingerprint: fingerprint,
      actions: List.unmodifiable(actions),
      before: report,
      projectedAfter: _analyzer.analyze(projected),
    );
  }

  /// The single repair proposed for one line, or null when WolfGuard has
  /// nothing honest to offer.
  FixAction? _actionFor({
    required BasketLineSnapshot line,
    required LinePreflightResult result,
    required String? category,
    required BenefitCategorySnapshot? benefit,
    required List<ReplacementCandidate> candidates,
  }) {
    // A covered line is already settled. The contract forbids an action here.
    if (result.status == PreflightStatus.covered) return null;

    // A PAID line is already the shopper's acknowledged self-pay choice. M2
    // does not repair a decision the shopper already made.
    if (PreflightCategories.isPaid(line.basketCategory)) return null;

    // A line the app cannot even read is not repairable by quantity or by
    // swap. Taking it out is the only honest offer, and the explanation says
    // so rather than implying WolfGuard knows what the item was.
    if (line.quantity <= 0 || line.upc.trim().isEmpty) {
      return _action(
        FixKind.removeLine,
        line,
        'This line is missing the product details WolfGuard needs to check '
        'it. Taking it out of the basket lets the rest be checked. You can '
        'scan the item again afterwards.',
      );
    }

    // Without a benefit category there is nothing to reduce into, swap
    // within, or carry onto a PAID line, so there is no honest proposal to
    // make. The report still explains what is wrong.
    if (category == null) return null;

    // Unknown means WolfGuard could not establish whether the item is
    // covered. FR-4 forbids an automatic replacement here, and a reduction
    // would be the same guess wearing a different label. Self-pay claims
    // nothing against the benefit, so it is the one repair that is honest
    // about not knowing, and it is what lets the rest of the basket be
    // handed off.
    if (result.status == PreflightStatus.unknown) {
      return _action(
        FixKind.keepAsSelfPay,
        line,
        'WolfGuard could not confirm expected coverage for '
        '${PreflightIssues.productLabel(line)} from current evidence. '
        'Keeping it as an item you pay for claims nothing against your '
        '$category benefit and lets the rest of the basket check out. If you '
        'believe it is covered, ask store staff before paying.',
      );
    }

    // Self-pay is already the shopper's informed choice; leave it alone.
    if (result.blockedUnits <= 0) return null;

    final outOfRoom = result.issues.any(
      (issue) => issue.code == IssueCode.allowanceExceeded,
    );

    if (outOfRoom) {
      // Some units still fit: keep exactly those and drop the overflow.
      if (result.coveredUnits > 0) {
        return _action(
          FixKind.reduceQuantity,
          line,
          'Expected coverage reaches ${_units(result.coveredUnits)} of '
          '${PreflightIssues.productLabel(line)}, not '
          '${_units(result.quantity)}. Keeping '
          '${_units(result.coveredUnits)} stays inside the '
          'application-managed $category allowance.',
          targetQuantity: result.coveredUnits,
        );
      }
      // No room left at all. A same-category swap cannot restore a spent
      // allowance, so the only truthful repair is to pay for the item.
      return _action(
        FixKind.keepAsSelfPay,
        line,
        'The application-managed $category allowance is already used up, so '
        'no swap would bring ${PreflightIssues.productLabel(line)} into '
        'expected coverage. Keeping it as an item you pay for lets the rest '
        'of the basket check out.',
      );
    }

    // The product itself is the problem. A replacement is only offered when
    // the evidence makes it safe.
    final replacement = _safeReplacement(
      line: line,
      result: result,
      category: category,
      benefit: benefit,
      candidates: candidates,
    );
    if (replacement != null) {
      return _action(
        FixKind.replaceProduct,
        line,
        'Swapping ${PreflightIssues.productLabel(line)} for '
        '${replacement.name} keeps the same $category benefit and is listed '
        'as eligible by ${replacement.evidenceLabel}.',
        replacement: replacement,
      );
    }

    return _action(
      FixKind.keepAsSelfPay,
      line,
      'WolfGuard found no eligible $category alternative with current '
      'evidence, so ${PreflightIssues.productLabel(line)} cannot be brought '
      'into expected coverage. Keeping it as an item you pay for lets the '
      'rest of the basket check out.',
    );
  }

  /// The first candidate that is safe to propose, preserving the order the
  /// catalog returned them in.
  ///
  /// Every rule here exists to stop WolfGuard from promising coverage it
  /// cannot evidence. A rejected candidate is not an error; it means the
  /// shopper is offered self-pay instead of a swap.
  ReplacementCandidate? _safeReplacement({
    required BasketLineSnapshot line,
    required LinePreflightResult result,
    required String category,
    required BenefitCategorySnapshot? benefit,
    required List<ReplacementCandidate> candidates,
  }) {
    // A swap inside a category with no room left would not bring the line
    // into expected coverage, however good the candidate is.
    if (benefit != null && _remaining(benefit) == 0) return null;

    final wrongSize = result.issues.any(
      (issue) => issue.code == IssueCode.packageMismatch,
    );

    for (final c in candidates) {
      if (!c.aplEligible) continue;
      if (PreflightCategories.benefitCategory(c.canonicalCategory) !=
          category) {
        continue;
      }
      if (c.upc.trim().isEmpty) continue;
      if (c.upc == line.upc) continue;
      // Stale or unrated evidence is not a basis for spending a benefit.
      if (c.freshness != EvidenceFreshness.current) continue;
      // When the size was the problem, an unverified or differently sized
      // package does not fix it.
      if (wrongSize) {
        final permitted = benefit?.permittedPackageSize;
        final offered = c.verifiedPackageSize;
        if (permitted == null || offered == null) continue;
        if (PackageRules.compare(offered, permitted) !=
            PackageComparison.match) {
          continue;
        }
      }
      return c;
    }
    return null;
  }

  /// The request as it would be after the plan is applied.
  ///
  /// Line keys are carried over unchanged. They name positions in the basket
  /// the plan was built from, and the projection is a hypothetical that is
  /// never applied through them; the applier resolves keys against live state
  /// instead.
  PreflightRequest _project(PreflightRequest request, List<FixAction> actions) {
    final byLine = {for (final action in actions) action.lineKey: action};
    final projected = <BasketLineSnapshot>[];
    for (final line in request.lines) {
      final action = byLine[line.lineKey];
      if (action == null) {
        projected.add(line);
        continue;
      }
      switch (action.kind) {
        case FixKind.removeLine:
          break;
        case FixKind.reduceQuantity:
          projected.add(_rewrite(line, quantity: action.targetQuantity));
        case FixKind.keepAsSelfPay:
          projected.add(_rewrite(line, basketCategory: wolfGuardPaidCategory));
        case FixKind.replaceProduct:
          final c = action.replacement!;
          projected.add(
            _rewrite(
              line,
              upc: c.upc,
              name: c.name,
              evidence: ProductEvidence(
                aplEligible: c.aplEligible,
                canonicalCategory: c.canonicalCategory,
                packageSize: c.verifiedPackageSize,
                freshness: c.freshness,
                sourceLabel: c.evidenceLabel,
              ),
            ),
          );
      }
    }
    return PreflightRequest(
      lines: List.unmodifiable(projected),
      benefits: request.benefits,
      evaluatedAt: request.evaluatedAt,
    );
  }

  /// [line] with selected fields replaced. The snapshot is immutable and the
  /// domain offers no `copyWith`, so the projection builds a new one.
  static BasketLineSnapshot _rewrite(
    BasketLineSnapshot line, {
    String? upc,
    String? name,
    String? basketCategory,
    int? quantity,
    ProductEvidence? evidence,
  }) {
    return BasketLineSnapshot(
      lineKey: line.lineKey,
      upc: upc ?? line.upc,
      name: name ?? line.name,
      basketCategory: basketCategory ?? line.basketCategory,
      originalBenefitCategory: line.originalBenefitCategory,
      quantity: quantity ?? line.quantity,
      evidence: evidence ?? line.evidence,
    );
  }

  /// Units still available in [benefit], never negative even when the
  /// inherited record reports more used than allowed. Null when uncapped.
  static int? _remaining(BenefitCategorySnapshot benefit) {
    final cap = benefit.allowed;
    if (cap == null) return null;
    final left = cap - benefit.used;
    return left < 0 ? 0 : left;
  }

  FixAction _action(
    FixKind kind,
    BasketLineSnapshot line,
    String explanation, {
    int? targetQuantity,
    ReplacementCandidate? replacement,
  }) {
    return FixAction(
      actionId: '${kind.name}:${line.lineKey}',
      kind: kind,
      lineKey: line.lineKey,
      targetQuantity: targetQuantity,
      replacement: replacement,
      shopperExplanation: explanation,
    );
  }

  /// Deterministic, so the same basket and the same candidates always propose
  /// the same plan. Tests and the synthetic rehearsal depend on that.
  static String _planId(String fingerprint, List<FixAction> actions) {
    var hash = 17;
    for (final unit in actions.map((a) => a.actionId).join('|').codeUnits) {
      hash = (hash * 31 + unit) & 0x3fffffff;
    }
    return 'plan-$fingerprint-${hash.toRadixString(16).padLeft(8, '0')}';
  }

  static String _units(int count) => count == 1 ? '1 unit' : '$count units';
}
