/// Builders and hand-written fakes shared by the M2 repair tests.
///
/// Section 5.6 of the plan asks for hand-written fakes rather than generated
/// mocks. Section 5.7 told M2 to develop against a fake `PreflightAnalyzer`
/// while M1 was in progress; now that `CheckoutPreflightEngine` is merged,
/// [RecordingAnalyzer] wraps the real engine instead, so the planner is
/// exercised against real allocation rules and the projected request it
/// produced is still observable.
library;

import 'package:wolfbite/features/wolfguard/domain/wolfguard_models.dart';
import 'package:wolfbite/features/wolfguard/domain/wolfguard_ports.dart';
import 'package:wolfbite/features/wolfguard/engine/checkout_preflight_engine.dart';
import 'package:wolfbite/features/wolfguard/repair/basket_fingerprint.dart';

/// Catalog evidence for a product that is eligible in [category].
ProductEvidence evidence({
  bool? aplEligible = true,
  String category = 'MILK - WHOLE',
  PackageAmount? packageSize,
  EvidenceFreshness freshness = EvidenceFreshness.current,
  String sourceLabel = 'Imported NC APL',
}) {
  return ProductEvidence(
    aplEligible: aplEligible,
    canonicalCategory: category,
    packageSize: packageSize,
    freshness: freshness,
    sourceLabel: sourceLabel,
  );
}

/// An evidence-safe alternative product.
ReplacementCandidate candidate({
  String upc = '99999999999',
  String name = 'Alternative product',
  String canonicalCategory = 'MILK - WHOLE',
  bool aplEligible = true,
  PackageAmount? verifiedPackageSize,
  EvidenceFreshness freshness = EvidenceFreshness.current,
  String evidenceLabel = 'Imported NC APL',
}) {
  return ReplacementCandidate(
    upc: upc,
    name: name,
    canonicalCategory: canonicalCategory,
    aplEligible: aplEligible,
    verifiedPackageSize: verifiedPackageSize,
    freshness: freshness,
    evidenceLabel: evidenceLabel,
  );
}

/// One raw `AppState.basket` entry, in the shape `AppState` documents.
Map<String, dynamic> rawLine({
  String upc = '00000000000',
  String name = 'Test product',
  String category = 'MILK - WHOLE',
  String? originalBenefitCategory,
  Object? qty = 1,
  Map<String, dynamic>? nutrition,
}) {
  return {
    'upc': upc,
    'name': name,
    'category': category,
    if (category != 'PAID' || originalBenefitCategory != null)
      'original_benefit_category': originalBenefitCategory ?? category,
    'qty': qty,
    'nutrition': nutrition,
  };
}

/// One raw `AppState.balances` row.
Map<String, dynamic> rawBalance({int? allowed = 3, int used = 0}) => {
  'allowed': allowed,
  'used': used,
};

/// The real engine, remembering every request it was handed.
///
/// The planner must produce its after-state by re-analysing a projected
/// basket rather than by adjusting counts, so a test needs to see the request
/// the planner projected. Wrapping rather than faking keeps the allocation
/// rules under test real.
class RecordingAnalyzer implements PreflightAnalyzer {
  RecordingAnalyzer([this._engine = const CheckoutPreflightEngine()]);

  final PreflightAnalyzer _engine;

  /// Every request analysed, in order.
  final List<PreflightRequest> seen = [];

  @override
  PreflightReport analyze(PreflightRequest request) {
    seen.add(request);
    return _engine.analyze(request);
  }
}

/// A plan carrying [actions], bound to [fingerprint].
///
/// Apply never reads the before/after reports, so they are left blank here;
/// the planner tests cover how those are built.
FixPlan planOf(String fingerprint, List<FixAction> actions) => FixPlan(
  planId: 'plan-$fingerprint-${actions.map((a) => a.actionId).join('|')}',
  sourceFingerprint: fingerprint,
  actions: actions,
  before: _blankReport(fingerprint),
  projectedAfter: _blankReport(fingerprint),
);

/// One action against the line at [index] of the basket.
FixAction action(
  FixKind kind, {
  required int index,
  required String upc,
  required String basketCategory,
  int? targetQuantity,
  ReplacementCandidate? replacement,
  String? lineKey,
}) {
  final key =
      lineKey ??
      BasketLineKey.of(index: index, upc: upc, basketCategory: basketCategory);
  return FixAction(
    actionId: '${kind.name}:$key',
    kind: kind,
    lineKey: key,
    targetQuantity: targetQuantity,
    replacement: replacement,
    shopperExplanation: 'Explanation for a ${kind.name} repair.',
  );
}

PreflightReport _blankReport(String fingerprint) =>
    PreflightReport(lines: const [], requestFingerprint: fingerprint);
