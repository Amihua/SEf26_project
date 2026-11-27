/// Pure rule helpers for the M1 checkout preflight engine.
///
/// Category normalization, package-size comparison, and the shopper-facing
/// wording of every preflight issue live here so the engine stays a small,
/// readable allocation loop. No Flutter, Firebase, network, or clock access.
library;

import 'package:wolfbite/utils/wic_categories.dart';

import '../domain/wolfguard_models.dart';

/// Category helpers built on the inherited `WicCategories.canonical`.
abstract final class PreflightCategories {
  /// The inherited canonical spelling of [raw] (trimmed, uppercased).
  static String canonical(Object? raw) => WicCategories.canonical(raw);

  /// Whether [raw] is the inherited `PAID` payment label.
  static bool isPaid(Object? raw) => canonical(raw) == wolfGuardPaidCategory;

  /// The canonical benefit category for [raw], or null when [raw] is blank,
  /// `UNKNOWN`, or `PAID` (a payment label, never a benefit category).
  static String? benefitCategory(Object? raw) {
    final category = canonical(raw);
    if (category.isEmpty ||
        category == 'UNKNOWN' ||
        category == wolfGuardPaidCategory) {
      return null;
    }
    return category;
  }
}

/// Result of comparing two explicit package sizes.
enum PackageComparison {
  /// Same supported unit and the same amount.
  match,

  /// Same supported unit, different amount.
  mismatch,

  /// Missing, malformed, unsupported, or different units. Never converted.
  notComparable,
}

/// Package-size rules. WolfGuard compares sizes only in the same unit.
abstract final class PackageRules {
  /// Units WolfGuard can compare, after [normalizeUnit].
  static const Set<String> supportedUnits = {
    'oz',
    'fl oz',
    'lb',
    'g',
    'kg',
    'ml',
    'l',
    'gal',
    'qt',
    'pt',
    'ct',
  };

  /// Trims, lowercases, and collapses whitespace. Does not translate units.
  static String normalizeUnit(String unit) =>
      unit.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Compares [selected] with [permitted] without converting units.
  ///
  /// Amounts that differ only by binary floating-point noise are a match.
  static PackageComparison compare(
    PackageAmount selected,
    PackageAmount permitted,
  ) {
    final unit = normalizeUnit(selected.unit);
    if (!supportedUnits.contains(unit) ||
        unit != normalizeUnit(permitted.unit) ||
        !_isPositiveFinite(selected.value) ||
        !_isPositiveFinite(permitted.value)) {
      return PackageComparison.notComparable;
    }
    final a = selected.value.toDouble();
    final b = permitted.value.toDouble();
    final scale = a.abs() > b.abs() ? a.abs() : b.abs();
    return (a - b).abs() <= 1e-9 * scale
        ? PackageComparison.match
        : PackageComparison.mismatch;
  }

  static bool _isPositiveFinite(num value) => value.isFinite && value > 0;
}

/// Shopper-facing wording for every preflight issue.
///
/// Uses the plan's evidence language: "expected coverage",
/// "application-managed allowance", and "unknown" rather than "safe".
abstract final class PreflightIssues {
  /// The name shown for [line] in explanations.
  static String productLabel(BasketLineSnapshot line) {
    final name = line.name.trim();
    if (name.isNotEmpty) return name;
    final upc = line.upc.trim();
    return upc.isEmpty ? 'Unnamed product' : 'UPC $upc';
  }

  /// A quantity that is not a positive whole number.
  static PreflightIssue invalidQuantity(BasketLineSnapshot line) =>
      PreflightIssue(
        code: IssueCode.insufficientEvidence,
        lineKey: line.lineKey,
        title: 'Quantity needs review',
        explanation:
            '${productLabel(line)} has quantity ${line.quantity} in the '
            'basket, which is not a positive whole number. WolfGuard counts '
            'it as one unknown unit instead of guessing.',
        suggestedNextStep: 'Remove the line or set its quantity again.',
        evidenceLabels: ['Basket quantity: ${line.quantity}'],
      );

  /// A basket line with no usable category.
  static PreflightIssue missingCategory(BasketLineSnapshot line) =>
      PreflightIssue(
        code: IssueCode.insufficientEvidence,
        lineKey: line.lineKey,
        title: 'Benefit category unknown',
        explanation:
            'The basket does not record a benefit category for '
            '${productLabel(line)}, so expected coverage cannot be checked.',
        suggestedNextStep: 'Remove the line and scan the product again.',
        evidenceLabels: ['Basket category: ${_shown(line.basketCategory)}'],
      );

  /// A benefit line without a UPC.
  static PreflightIssue blankUpc(BasketLineSnapshot line) => PreflightIssue(
    code: IssueCode.insufficientEvidence,
    lineKey: line.lineKey,
    title: 'Product code missing',
    explanation:
        '${productLabel(line)} has no UPC in the basket, so WolfGuard cannot '
        'match it to the imported NC APL.',
    suggestedNextStep: 'Scan the product again so its UPC is recorded.',
    evidenceLabels: const ['UPC: (blank)'],
  );

  /// A benefit line whose two recorded categories disagree.
  static PreflightIssue categoryConflict(
    BasketLineSnapshot line,
    String basketCategory,
  ) => PreflightIssue(
    code: IssueCode.contradictoryEvidence,
    lineKey: line.lineKey,
    title: 'Basket categories disagree',
    explanation:
        '${productLabel(line)} is listed under $basketCategory, but its '
        'recorded benefit category is '
        '${_shown(line.originalBenefitCategory)}.',
    suggestedNextStep: 'Remove the line and add the product again.',
    evidenceLabels: [
      'Basket category: $basketCategory',
      'Recorded benefit category: ${_shown(line.originalBenefitCategory)}',
    ],
  );

  /// No catalog evidence was supplied for the line.
  static PreflightIssue missingEvidence(BasketLineSnapshot line) =>
      PreflightIssue(
        code: IssueCode.insufficientEvidence,
        lineKey: line.lineKey,
        title: 'No catalog evidence',
        explanation:
            'WolfGuard has no imported NC APL record for '
            '${productLabel(line)} (UPC ${line.upc.trim()}), so it cannot '
            'expect coverage.',
        suggestedNextStep:
            'Check the product at the store or keep it self-paid.',
        evidenceLabels: const ['APL record: not supplied'],
      );

  /// Product evidence marked stale.
  static PreflightIssue staleEvidence(
    BasketLineSnapshot line,
    ProductEvidence evidence,
  ) => PreflightIssue(
    code: IssueCode.staleEvidence,
    lineKey: line.lineKey,
    title: 'Catalog evidence is stale',
    explanation:
        'The catalog evidence for ${productLabel(line)} is marked stale, so '
        'WolfGuard does not rely on it.',
    suggestedNextStep:
        'Refresh the product information, or review it at checkout.',
    evidenceLabels: ['${evidence.sourceLabel}: stale'],
  );

  /// Product evidence whose age or origin cannot be confirmed.
  static PreflightIssue unconfirmedEvidence(
    BasketLineSnapshot line,
    ProductEvidence evidence,
  ) => PreflightIssue(
    code: IssueCode.insufficientEvidence,
    lineKey: line.lineKey,
    title: 'Catalog evidence unconfirmed',
    explanation:
        'WolfGuard cannot confirm when the evidence for '
        '${productLabel(line)} was read.',
    suggestedNextStep:
        'Refresh the product information, or review it at checkout.',
    evidenceLabels: ['${evidence.sourceLabel}: freshness unknown'],
  );

  /// Evidence that does not state APL eligibility.
  static PreflightIssue eligibilityUnknown(
    BasketLineSnapshot line,
    ProductEvidence evidence,
  ) => PreflightIssue(
    code: IssueCode.insufficientEvidence,
    lineKey: line.lineKey,
    title: 'Eligibility not recorded',
    explanation:
        'The catalog record for ${productLabel(line)} does not say whether '
        'it is APL eligible.',
    suggestedNextStep: 'Check the product at the store or keep it self-paid.',
    evidenceLabels: ['${evidence.sourceLabel}: eligibility missing'],
  );

  /// The APL explicitly marks the product ineligible.
  static PreflightIssue ineligible(
    BasketLineSnapshot line,
    ProductEvidence evidence,
  ) => PreflightIssue(
    code: IssueCode.notInCurrentBenefits,
    lineKey: line.lineKey,
    title: 'Not eligible in the APL',
    explanation:
        'The imported NC APL marks ${productLabel(line)} (UPC '
        '${line.upc.trim()}) as not eligible, so WolfGuard does not expect '
        'it to be covered.',
    suggestedNextStep:
        'Remove it, keep it self-paid, or choose an eligible same-category '
        'alternative.',
    evidenceLabels: ['${evidence.sourceLabel}: eligible = false'],
  );

  /// Evidence without a catalog category.
  static PreflightIssue evidenceCategoryMissing(
    BasketLineSnapshot line,
    ProductEvidence evidence,
  ) => PreflightIssue(
    code: IssueCode.insufficientEvidence,
    lineKey: line.lineKey,
    title: 'APL category not recorded',
    explanation:
        'The catalog record for ${productLabel(line)} has no category, so '
        'WolfGuard cannot confirm the basket category.',
    suggestedNextStep: 'Check the product at the store or keep it self-paid.',
    evidenceLabels: ['${evidence.sourceLabel}: category missing'],
  );

  /// The catalog category disagrees with the basket category.
  static PreflightIssue evidenceCategoryConflict(
    BasketLineSnapshot line,
    String basketCategory,
    String evidenceCategory,
  ) => PreflightIssue(
    code: IssueCode.contradictoryEvidence,
    lineKey: line.lineKey,
    title: 'Catalog category disagrees',
    explanation:
        'The basket lists ${productLabel(line)} under $basketCategory, but '
        'the catalog places it in $evidenceCategory.',
    suggestedNextStep: 'Remove the line and scan the product again.',
    evidenceLabels: [
      'Basket category: $basketCategory',
      'APL category: $evidenceCategory',
    ],
  );

  /// The application-managed allowance has no record for the category.
  static PreflightIssue noBenefit(BasketLineSnapshot line, String category) =>
      PreflightIssue(
        code: IssueCode.notInCurrentBenefits,
        lineKey: line.lineKey,
        title: 'No current allowance for this category',
        explanation:
            'The application-managed allowance has no $category category, so '
            '${productLabel(line)} is not expected to be covered.',
        suggestedNextStep: 'Remove it or keep it self-paid.',
        evidenceLabels: ['Application-managed allowance: no $category record'],
      );

  /// The allowance record is stale or its freshness is unknown.
  static PreflightIssue allowanceNotCurrent(
    BasketLineSnapshot line,
    BenefitCategorySnapshot benefit,
  ) {
    final stale = benefit.freshness == EvidenceFreshness.stale;
    return PreflightIssue(
      code: stale ? IssueCode.staleEvidence : IssueCode.insufficientEvidence,
      lineKey: line.lineKey,
      title: stale
          ? 'Allowance record is stale'
          : 'Allowance record unconfirmed',
      explanation:
          'The application-managed ${benefit.category} allowance is '
          '${stale ? 'marked stale' : 'not confirmed'}, so expected coverage '
          'for ${productLabel(line)} cannot be checked.',
      suggestedNextStep: 'Reload the allowance before relying on it.',
      evidenceLabels: [
        '${benefit.category} allowance: ${benefit.freshness.name}',
      ],
    );
  }

  /// The allowance record cannot be right (negative, or used over allowed).
  static PreflightIssue allowanceInconsistent(
    BasketLineSnapshot line,
    BenefitCategorySnapshot benefit,
  ) => PreflightIssue(
    code: IssueCode.contradictoryEvidence,
    lineKey: line.lineKey,
    title: 'Allowance record is inconsistent',
    explanation:
        'The application-managed ${benefit.category} allowance reports '
        '${benefit.used} used of ${benefit.allowed ?? 'no cap'} allowed, which '
        'cannot be right. WolfGuard will not calculate a negative balance.',
    suggestedNextStep: 'Reload the allowance before relying on it.',
    evidenceLabels: [
      'Allowed: ${benefit.allowed ?? 'no cap'}',
      'Used outside this basket: ${benefit.used}',
    ],
  );

  /// The category has a package rule but the product has no explicit size.
  static PreflightIssue packageEvidenceMissing(
    BasketLineSnapshot line,
    String category,
    PackageAmount permitted,
  ) => PreflightIssue(
    code: IssueCode.insufficientEvidence,
    lineKey: line.lineKey,
    title: 'Package size unknown',
    explanation:
        'The $category category permits $permitted packages, but there is no '
        'explicit package size for ${productLabel(line)}.',
    suggestedNextStep: 'Check the package size on the shelf before checkout.',
    evidenceLabels: [
      'Permitted package: $permitted',
      'Selected package: unknown',
    ],
  );

  /// Package sizes in different or unsupported units.
  static PreflightIssue packageNotComparable(
    BasketLineSnapshot line,
    PackageAmount selected,
    PackageAmount permitted,
  ) => PreflightIssue(
    code: IssueCode.insufficientEvidence,
    lineKey: line.lineKey,
    title: 'Package sizes cannot be compared',
    explanation:
        '${productLabel(line)} is listed as $selected but the category rule '
        'is $permitted. WolfGuard does not convert between units.',
    suggestedNextStep: 'Check the package size on the shelf before checkout.',
    evidenceLabels: [
      'Selected package: $selected',
      'Permitted package: $permitted',
    ],
  );

  /// Explicit, comparable package evidence shows a different size.
  static PreflightIssue packageMismatch(
    BasketLineSnapshot line,
    String category,
    ProductEvidence evidence,
    PackageAmount selected,
    PackageAmount permitted,
  ) => PreflightIssue(
    code: IssueCode.packageMismatch,
    lineKey: line.lineKey,
    title: 'Package size does not match',
    explanation:
        '${productLabel(line)} is $selected; the $category category permits '
        '$permitted.',
    suggestedNextStep:
        'Replace it with a $permitted package or keep it self-paid.',
    evidenceLabels: [
      'Selected package: $selected (${evidence.sourceLabel})',
      'Permitted package: $permitted',
    ],
  );

  /// Some units exceed the remaining application-managed allowance.
  static PreflightIssue allowanceExceeded({
    required BasketLineSnapshot line,
    required BenefitCategorySnapshot benefit,
    required int remainingBefore,
    required int blockedUnits,
    required int heldForUnknown,
  }) {
    final coveredUnits = line.quantity - blockedUnits;
    final held = heldForUnknown == 0
        ? ''
        : ' $heldForUnknown ${_units(heldForUnknown)} of that allowance '
              '${heldForUnknown == 1 ? 'is' : 'are'} held for earlier lines '
              'whose evidence is unknown.';
    return PreflightIssue(
      code: IssueCode.allowanceExceeded,
      lineKey: line.lineKey,
      title: 'Over the allowance',
      explanation:
          '$blockedUnits of ${line.quantity} ${productLabel(line)} '
          '${_units(line.quantity)} exceed the remaining application-managed '
          '${benefit.category} allowance ($remainingBefore of '
          '${benefit.allowed} left before this line).$held',
      suggestedNextStep: coveredUnits > 0
          ? 'Reduce the quantity to $coveredUnits, or keep $blockedUnits as '
                'self-paid.'
          : 'Remove the line, or keep it as self-paid.',
      evidenceLabels: [
        'Allowed: ${benefit.allowed}',
        'Used outside this basket: ${benefit.used}',
        'Remaining before this line: $remainingBefore',
      ],
    );
  }

  /// A `PAID` line the shopper will pay for.
  static PreflightIssue selfPaid(
    BasketLineSnapshot line,
    String originalCategory, {
    required bool recovered,
  }) => PreflightIssue(
    code: IssueCode.allowanceExceeded,
    lineKey: line.lineKey,
    title: 'Marked self-paid',
    explanation:
        'The basket marks ${line.quantity} ${productLabel(line)} '
        '${_units(line.quantity)} as PAID, so WolfGuard expects the shopper '
        'to pay for ${line.quantity == 1 ? 'it' : 'them'}.',
    suggestedNextStep:
        'Keep as self-paid, or reduce the quantity if you do not want to pay.',
    evidenceLabels: [
      'Basket category: PAID',
      'Original benefit category: $originalCategory'
          '${recovered ? ' (recovered from exact-UPC evidence)' : ''}',
    ],
  );

  /// A `PAID` line whose original benefit category cannot be recovered.
  static PreflightIssue paidOriginalMissing(BasketLineSnapshot line) =>
      PreflightIssue(
        code: IssueCode.insufficientEvidence,
        lineKey: line.lineKey,
        title: 'Original category unknown',
        explanation:
            'The PAID line for ${productLabel(line)} does not record which '
            'benefit category it came from, and no exact-UPC evidence '
            'recovers it.',
        suggestedNextStep: 'Remove the PAID line and add the product again.',
        evidenceLabels: const ['Original benefit category: not recorded'],
      );

  /// Exact-UPC evidence points to more than one original category.
  static PreflightIssue paidOriginalAmbiguous(
    BasketLineSnapshot line,
    List<String> categories,
  ) => PreflightIssue(
    code: IssueCode.contradictoryEvidence,
    lineKey: line.lineKey,
    title: 'Original category ambiguous',
    explanation:
        'Exact-UPC evidence for the PAID ${productLabel(line)} line points to '
        'more than one benefit category: ${categories.join(', ')}.',
    suggestedNextStep: 'Remove the PAID line and add the product again.',
    evidenceLabels: [for (final c in categories) 'Candidate category: $c'],
  );

  /// Note for a covered line in a category the prototype does not cap.
  static String prototypeUncappedNote(String category) =>
      'Prototype-uncapped category: the application sets no cap for '
      '$category. This is not an official unlimited benefit.';

  /// Note for a covered line whose package matches explicit evidence.
  static String packageMatchNote(PackageAmount selected) =>
      'Package size matches explicit evidence: $selected.';

  static String _units(int count) => count == 1 ? 'unit' : 'units';

  static String _shown(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '(missing)' : text;
  }
}
