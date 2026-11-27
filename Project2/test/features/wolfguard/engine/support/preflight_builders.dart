import 'package:wolfbite/features/wolfguard/domain/wolfguard_models.dart';

/// Fixed evaluation time; the engine never reads the clock.
final DateTime evaluatedAt = DateTime.utc(2026, 11, 26, 12);

/// Current, eligible APL evidence in [category].
ProductEvidence apl(
  String category, {
  bool? eligible = true,
  EvidenceFreshness freshness = EvidenceFreshness.current,
  PackageAmount? size,
  String source = 'Test APL',
}) => ProductEvidence(
  aplEligible: eligible,
  canonicalCategory: category,
  packageSize: size,
  freshness: freshness,
  sourceLabel: source,
);

/// A basket line. Defaults to current, eligible evidence in its category.
BasketLineSnapshot line(
  String key, {
  String upc = '000000000001',
  String? name,
  String category = 'MILK - WHOLE',
  String? original,
  bool useDefaultOriginal = true,
  int quantity = 1,
  ProductEvidence? evidence,
  bool noEvidence = false,
}) {
  final isPaid = category == wolfGuardPaidCategory;
  return BasketLineSnapshot(
    lineKey: key,
    upc: upc,
    name: name ?? 'Product $key',
    basketCategory: category,
    originalBenefitCategory:
        original ?? (useDefaultOriginal && !isPaid ? category : null),
    quantity: quantity,
    evidence: noEvidence ? null : evidence ?? (isPaid ? null : apl(category)),
  );
}

/// An application-managed allowance; [used] excludes this request's lines.
BenefitCategorySnapshot benefit(
  String category, {
  int? allowed = 3,
  int used = 0,
  EvidenceFreshness freshness = EvidenceFreshness.current,
  PackageAmount? package,
}) => BenefitCategorySnapshot(
  category: category,
  allowed: allowed,
  used: used,
  freshness: freshness,
  permittedPackageSize: package,
);

/// A request keyed by each benefit's category.
PreflightRequest request(
  List<BasketLineSnapshot> lines, [
  List<BenefitCategorySnapshot> benefits = const [],
]) => PreflightRequest(
  lines: lines,
  benefits: {for (final b in benefits) b.category: b},
  evaluatedAt: evaluatedAt,
);

/// Issue codes reported for [lineKey].
List<IssueCode> codesFor(PreflightReport report, String lineKey) => [
  for (final issue in report.lineFor(lineKey)!.issues) issue.code,
];
