/// Copies inherited `AppState` data into an immutable [PreflightRequest].
library;

import '../domain/wolfguard_models.dart';
import 'preflight_rules.dart';

/// Builds preflight requests from the inherited basket and balance maps.
///
/// The builder only reads its inputs; it never mutates the maps it is given.
/// Malformed raw values are kept visible for the engine to report as unknown:
///
/// - a non-`int` quantity (decimal, string, missing) becomes `0`, which the
///   engine reports as an unknown quantity. It is never parsed or clamped;
/// - a non-`String` UPC or category becomes blank;
/// - an allowance record with a missing or non-`int` counter is kept with
///   [EvidenceFreshness.unknown] instead of being treated as zero or uncapped.
abstract final class PreflightRequestBuilder {
  /// Snapshots `AppState.basket` and `AppState.balances`.
  ///
  /// [evidenceByUpc] supplies catalog evidence for exact UPCs, for example
  /// from [evidenceFromAplRecord]. Lines without evidence stay unknown.
  ///
  /// The inherited `used` counter includes units already in the basket. The
  /// snapshot's [BenefitCategorySnapshot.used] excludes them, so this method
  /// subtracts the basket's benefit units per category. A counter that is
  /// already over its cap is passed through unchanged so the engine reports
  /// the inconsistency instead of computing a misleading balance.
  static PreflightRequest fromAppState({
    required List<Map<String, Object?>> basket,
    required Map<String, Map<String, Object?>> balances,
    required DateTime evaluatedAt,
    Map<String, ProductEvidence> evidenceByUpc = const {},
  }) {
    final lines = <BasketLineSnapshot>[];
    final basketUnits = <String, int>{};
    for (var index = 0; index < basket.length; index++) {
      final raw = basket[index];
      final upc = _text(raw['upc']).trim();
      final category = PreflightCategories.canonical(_text(raw['category']));
      final originalRaw = raw['original_benefit_category'];
      final qtyRaw = raw['qty'];
      final quantity = qtyRaw is int ? qtyRaw : 0;
      lines.add(
        BasketLineSnapshot(
          lineKey: '$index:$upc:$category',
          upc: upc,
          name: _text(raw['name']),
          basketCategory: category,
          originalBenefitCategory: originalRaw is String
              ? PreflightCategories.canonical(originalRaw)
              : null,
          quantity: quantity,
          evidence: upc.isEmpty ? null : evidenceByUpc[upc],
        ),
      );
      final benefitCategory = PreflightCategories.benefitCategory(category);
      if (benefitCategory != null && quantity > 0) {
        basketUnits[benefitCategory] =
            (basketUnits[benefitCategory] ?? 0) + quantity;
      }
    }

    final benefits = <String, BenefitCategorySnapshot>{};
    balances.forEach((key, record) {
      final category = PreflightCategories.benefitCategory(key);
      if (category == null) return;
      final snapshot = _benefitSnapshot(
        category,
        record,
        basketUnits[category] ?? 0,
      );
      final existing = benefits[category];
      benefits[category] = existing == null
          ? snapshot
          : BenefitCategorySnapshot(
              category: category,
              allowed: existing.allowed,
              used: existing.used,
              freshness: EvidenceFreshness.unknown,
            );
    });

    return PreflightRequest(
      lines: lines,
      benefits: benefits,
      evaluatedAt: evaluatedAt,
    );
  }

  /// Evidence from one imported NC APL record (`AplService.findByUpc` shape).
  ///
  /// Returns null for a missing record: absence is not proof of ineligibility.
  /// The package size is always null because the APL accounting unit is not a
  /// verified package size.
  static ProductEvidence? evidenceFromAplRecord(
    Map<String, Object?>? record, {
    String sourceLabel = 'Imported NC APL',
  }) {
    if (record == null) return null;
    final eligible = record['eligible'];
    final category = PreflightCategories.benefitCategory(
      PreflightCategories.canonical(record['category']),
    );
    return ProductEvidence(
      aplEligible: eligible is bool ? eligible : null,
      canonicalCategory: category,
      freshness: EvidenceFreshness.current,
      sourceLabel: sourceLabel,
    );
  }

  static BenefitCategorySnapshot _benefitSnapshot(
    String category,
    Map<String, Object?> record,
    int unitsInBasket,
  ) {
    final allowed = record['allowed'];
    final used = record['used'];
    final readable =
        record.containsKey('allowed') &&
        (allowed == null || allowed is int) &&
        used is int;
    if (!readable) {
      return BenefitCategorySnapshot(
        category: category,
        allowed: allowed is int ? allowed : null,
        used: used is int ? used : 0,
        freshness: EvidenceFreshness.unknown,
      );
    }
    final cap = allowed as int?;
    final overCap = cap != null && used > cap;
    return BenefitCategorySnapshot(
      category: category,
      allowed: cap,
      used: overCap ? used : used - unitsInBasket,
      freshness: EvidenceFreshness.current,
    );
  }

  static String _text(Object? value) => value is String ? value : '';
}
