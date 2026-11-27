/// Shared WolfGuard domain contract (plan Section 6).
///
/// Every type here is pure Dart and immutable: no Flutter, Firebase, network,
/// or clock access. Collections are copied into unmodifiable views when a value
/// is constructed, so a caller cannot change a request or report afterwards.
///
/// Owners: Andy (M1). M2 (repair) and M3 (catalog) types live here too so all
/// four workstreams compile against one contract. Changing a public member
/// requires the contract-change procedure in plan Section 5.6.
library;

/// The inherited basket label for units the shopper pays for themselves.
///
/// `PAID` is a payment classification, never an original benefit category.
const String wolfGuardPaidCategory = 'PAID';

/// The expected outcome for one basket unit.
enum PreflightStatus {
  /// Expected coverage from the application-managed allowance.
  covered,

  /// The basket explicitly marks the unit as paid by the shopper.
  selfPay,

  /// Actionable: available evidence says the unit will not be covered.
  blocked,

  /// Evidence is missing, malformed, stale, or contradictory.
  unknown,
}

/// Why a line is not simply covered.
enum IssueCode {
  /// More units than the remaining application-managed allowance.
  allowanceExceeded,

  /// The product or its category has no current application benefit.
  notInCurrentBenefits,

  /// Explicit, comparable package evidence shows a different size.
  packageMismatch,

  /// A required fact is missing or unreadable.
  insufficientEvidence,

  /// Evidence exists but is marked stale.
  staleEvidence,

  /// Two pieces of evidence disagree, or a record is internally inconsistent.
  contradictoryEvidence,
}

/// A basket change a repair plan can propose (M2).
enum FixKind {
  /// Lower a line's quantity to [FixAction.targetQuantity].
  reduceQuantity,

  /// Remove a line from the basket.
  removeLine,

  /// Keep the excess units as self-paid.
  keepAsSelfPay,

  /// Swap the line's product for [FixAction.replacement].
  replaceProduct,
}

/// How trustworthy a piece of evidence is right now.
enum EvidenceFreshness {
  /// Read from its source for this evaluation.
  current,

  /// Known to be out of date.
  stale,

  /// Age or origin cannot be confirmed.
  unknown,
}

/// A package size taken from explicit evidence, for example `18 oz`.
///
/// WolfGuard never infers a size from a product name, UPC shape, nutrition
/// serving size, or the APL accounting unit.
final class PackageAmount {
  /// Creates a package size of [value] in [unit].
  const PackageAmount(this.value, this.unit);

  /// The numeric amount, exactly as supplied by the evidence source.
  final num value;

  /// The unit label, exactly as supplied by the evidence source.
  final String unit;

  @override
  bool operator ==(Object other) =>
      other is PackageAmount && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);

  @override
  String toString() => '$value $unit';
}

/// Catalog facts known about one basket product.
///
/// A null field means "not known"; it never means false or zero.
final class ProductEvidence {
  /// Creates product evidence from one named source.
  const ProductEvidence({
    required this.aplEligible,
    required this.canonicalCategory,
    required this.freshness,
    required this.sourceLabel,
    this.packageSize,
  });

  /// Whether the imported NC APL marks this exact UPC eligible.
  final bool? aplEligible;

  /// The APL category, already passed through `WicCategories.canonical`.
  final String? canonicalCategory;

  /// Explicit, verified package size. Usually null for live APL records.
  final PackageAmount? packageSize;

  /// How current this evidence is.
  final EvidenceFreshness freshness;

  /// Human-readable source shown in the report, e.g. `Imported NC APL`.
  final String sourceLabel;

  @override
  bool operator ==(Object other) =>
      other is ProductEvidence &&
      other.aplEligible == aplEligible &&
      other.canonicalCategory == canonicalCategory &&
      other.packageSize == packageSize &&
      other.freshness == freshness &&
      other.sourceLabel == sourceLabel;

  @override
  int get hashCode => Object.hash(
    aplEligible,
    canonicalCategory,
    packageSize,
    freshness,
    sourceLabel,
  );
}

/// An immutable copy of one inherited basket line.
final class BasketLineSnapshot {
  /// Creates a line snapshot. [lineKey] must be unique within its request.
  const BasketLineSnapshot({
    required this.lineKey,
    required this.upc,
    required this.name,
    required this.basketCategory,
    required this.quantity,
    this.originalBenefitCategory,
    this.evidence,
  });

  /// Unique key within one request, e.g. `0:041303001234:MILK - WHOLE`.
  final String lineKey;

  /// Product UPC exactly as stored in the basket. May be blank.
  final String upc;

  /// Product display name.
  final String name;

  /// The basket's category label: a benefit category or `PAID`.
  final String basketCategory;

  /// The benefit category a `PAID` line overflowed from, when recorded.
  final String? originalBenefitCategory;

  /// Units on this line. Zero or negative is reported as unknown, not clamped.
  final int quantity;

  /// Catalog evidence for [upc], or null when none was supplied.
  final ProductEvidence? evidence;

  @override
  bool operator ==(Object other) =>
      other is BasketLineSnapshot &&
      other.lineKey == lineKey &&
      other.upc == upc &&
      other.name == name &&
      other.basketCategory == basketCategory &&
      other.originalBenefitCategory == originalBenefitCategory &&
      other.quantity == quantity &&
      other.evidence == evidence;

  @override
  int get hashCode => Object.hash(
    lineKey,
    upc,
    name,
    basketCategory,
    originalBenefitCategory,
    quantity,
    evidence,
  );
}

/// An immutable copy of one application-managed allowance category.
final class BenefitCategorySnapshot {
  /// Creates a category snapshot.
  const BenefitCategorySnapshot({
    required this.category,
    required this.allowed,
    required this.used,
    required this.freshness,
    this.permittedPackageSize,
  });

  /// Canonical category name.
  final String category;

  /// Units the prototype allows per month.
  ///
  /// Null means only that the prototype has no cap for this category. It is
  /// not an official unlimited benefit.
  final int? allowed;

  /// Units already consumed **outside the lines of this request**, such as
  /// earlier checkouts this month.
  ///
  /// The inherited `AppState` counter also includes units currently in the
  /// basket; `PreflightRequestBuilder` subtracts those. Remaining allowance
  /// for the request is therefore `allowed - used`.
  final int used;

  /// Package size the category permits, from explicit evidence only.
  final PackageAmount? permittedPackageSize;

  /// How current the allowance record is.
  final EvidenceFreshness freshness;

  @override
  bool operator ==(Object other) =>
      other is BenefitCategorySnapshot &&
      other.category == category &&
      other.allowed == allowed &&
      other.used == used &&
      other.permittedPackageSize == permittedPackageSize &&
      other.freshness == freshness;

  @override
  int get hashCode =>
      Object.hash(category, allowed, used, permittedPackageSize, freshness);
}

/// Everything the analyzer needs, frozen at one moment.
final class PreflightRequest {
  /// Creates a request, copying [lines] and [benefits] into unmodifiable views.
  PreflightRequest({
    required List<BasketLineSnapshot> lines,
    required Map<String, BenefitCategorySnapshot> benefits,
    required this.evaluatedAt,
  }) : lines = List.unmodifiable(lines),
       benefits = Map.unmodifiable(benefits);

  /// Basket lines in stable basket order.
  final List<BasketLineSnapshot> lines;

  /// Allowance records keyed by canonical category name.
  final Map<String, BenefitCategorySnapshot> benefits;

  /// When the snapshot was taken. Not part of [fingerprint].
  final DateTime evaluatedAt;

  /// Deterministic identity of the lines, evidence, and allowances.
  ///
  /// Two requests with the same content have the same fingerprint, whenever
  /// they were taken. Any change to a line, its evidence, or an allowance
  /// changes it, which lets a repair plan detect a stale basket.
  late final String fingerprint = _fingerprintOf(this);
}

/// One explained reason why a line is not simply covered.
final class PreflightIssue {
  /// Creates an issue for [lineKey].
  PreflightIssue({
    required this.code,
    required this.lineKey,
    required this.title,
    required this.explanation,
    required this.suggestedNextStep,
    List<String> evidenceLabels = const [],
  }) : evidenceLabels = List.unmodifiable(evidenceLabels);

  /// Machine-readable reason.
  final IssueCode code;

  /// The affected line.
  final String lineKey;

  /// Short shopper-facing heading.
  final String title;

  /// What WolfGuard found, naming the affected product.
  final String explanation;

  /// A suggested repair, not the only correct action.
  final String suggestedNextStep;

  /// The facts the explanation relies on.
  final List<String> evidenceLabels;

  @override
  bool operator ==(Object other) =>
      other is PreflightIssue &&
      other.code == code &&
      other.lineKey == lineKey &&
      other.title == title &&
      other.explanation == explanation &&
      other.suggestedNextStep == suggestedNextStep &&
      _listEquals(other.evidenceLabels, evidenceLabels);

  @override
  int get hashCode => Object.hash(
    code,
    lineKey,
    title,
    explanation,
    suggestedNextStep,
    Object.hashAll(evidenceLabels),
  );
}

/// The analyzer's result for one basket line.
final class LinePreflightResult {
  /// Creates a line result.
  LinePreflightResult({
    required this.lineKey,
    required this.status,
    required this.quantity,
    required this.coveredUnits,
    required this.selfPayUnits,
    required this.blockedUnits,
    required this.unknownUnits,
    List<PreflightIssue> issues = const [],
    List<String> notes = const [],
  }) : issues = List.unmodifiable(issues),
       notes = List.unmodifiable(notes);

  /// The line this result describes.
  final String lineKey;

  /// The line's overall status.
  final PreflightStatus status;

  /// The quantity as supplied in the request, even when it is invalid.
  final int quantity;

  /// Units with expected coverage.
  final int coveredUnits;

  /// Units the basket marks as self-paid.
  final int selfPayUnits;

  /// Units available evidence says will not be covered.
  final int blockedUnits;

  /// Units whose outcome cannot be determined.
  final int unknownUnits;

  /// Explanations for every non-covered unit.
  final List<PreflightIssue> issues;

  /// Non-blocking context, e.g. that a category is prototype-uncapped.
  final List<String> notes;

  /// Units this result accounts for.
  ///
  /// Equals [quantity] for a valid line. A line with an unreadable quantity
  /// is counted as exactly one unknown unit so it cannot vanish from totals.
  int get accountedUnits =>
      coveredUnits + selfPayUnits + blockedUnits + unknownUnits;

  @override
  bool operator ==(Object other) =>
      other is LinePreflightResult &&
      other.lineKey == lineKey &&
      other.status == status &&
      other.quantity == quantity &&
      other.coveredUnits == coveredUnits &&
      other.selfPayUnits == selfPayUnits &&
      other.blockedUnits == blockedUnits &&
      other.unknownUnits == unknownUnits &&
      _listEquals(other.issues, issues) &&
      _listEquals(other.notes, notes);

  @override
  int get hashCode => Object.hash(
    lineKey,
    status,
    quantity,
    coveredUnits,
    selfPayUnits,
    blockedUnits,
    unknownUnits,
    Object.hashAll(issues),
    Object.hashAll(notes),
  );
}

/// The whole-basket checkout preflight result.
final class PreflightReport {
  /// Creates a report whose totals are always the sum of [lines].
  PreflightReport({
    required List<LinePreflightResult> lines,
    required this.requestFingerprint,
  }) : lines = List.unmodifiable(lines),
       coveredUnits = _sum(lines, (l) => l.coveredUnits),
       selfPayUnits = _sum(lines, (l) => l.selfPayUnits),
       blockedUnits = _sum(lines, (l) => l.blockedUnits),
       unknownUnits = _sum(lines, (l) => l.unknownUnits),
       totalUnits = _sum(lines, (l) => l.accountedUnits);

  /// Line results in request order.
  final List<LinePreflightResult> lines;

  /// Every accounted unit; equals the sum of the four outcome counts.
  final int totalUnits;

  /// Units with expected coverage.
  final int coveredUnits;

  /// Units the basket marks as self-paid.
  final int selfPayUnits;

  /// Units that need an actionable repair.
  final int blockedUnits;

  /// Units whose evidence needs review.
  final int unknownUnits;

  /// [PreflightRequest.fingerprint] of the analyzed request.
  final String requestFingerprint;

  /// Whether nothing is blocked or unknown. An empty basket is never ready.
  bool get readyForHandoff =>
      totalUnits > 0 && blockedUnits == 0 && unknownUnits == 0;

  /// `(coveredUnits + acknowledgedSelfPayUnits) / totalUnits * 100`.
  ///
  /// Null for an empty basket, which has no readiness percentage. Always show
  /// blocked and unknown counts next to this number.
  double? readinessPercent({int acknowledgedSelfPayUnits = 0}) {
    if (totalUnits == 0) return null;
    final acknowledged = acknowledgedSelfPayUnits.clamp(0, selfPayUnits);
    return (coveredUnits + acknowledged) / totalUnits * 100;
  }

  /// The result for [lineKey], or null when the report has no such line.
  LinePreflightResult? lineFor(String lineKey) {
    for (final line in lines) {
      if (line.lineKey == lineKey) return line;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PreflightReport &&
      other.requestFingerprint == requestFingerprint &&
      _listEquals(other.lines, lines);

  @override
  int get hashCode => Object.hash(requestFingerprint, Object.hashAll(lines));
}

/// An eligible same-category product found in the imported APL (M3).
final class ReplacementCandidate {
  /// Creates a replacement candidate.
  const ReplacementCandidate({
    required this.upc,
    required this.name,
    required this.canonicalCategory,
    required this.aplEligible,
    required this.freshness,
    required this.evidenceLabel,
    this.verifiedPackageSize,
  });

  /// The candidate's Firestore document UPC, preserved exactly.
  final String upc;

  /// Display name.
  final String name;

  /// Canonical category; equals the original line's benefit category.
  final String canonicalCategory;

  /// APL eligibility. Providers return only `true` candidates.
  final bool aplEligible;

  /// Explicit, verified package size, or null when not known.
  final PackageAmount? verifiedPackageSize;

  /// How current the candidate record is.
  final EvidenceFreshness freshness;

  /// Honest label, e.g. `Same-category candidate; package size unknown`.
  final String evidenceLabel;

  @override
  bool operator ==(Object other) =>
      other is ReplacementCandidate &&
      other.upc == upc &&
      other.name == name &&
      other.canonicalCategory == canonicalCategory &&
      other.aplEligible == aplEligible &&
      other.verifiedPackageSize == verifiedPackageSize &&
      other.freshness == freshness &&
      other.evidenceLabel == evidenceLabel;

  @override
  int get hashCode => Object.hash(
    upc,
    name,
    canonicalCategory,
    aplEligible,
    verifiedPackageSize,
    freshness,
    evidenceLabel,
  );
}

/// One proposed basket change (M2).
final class FixAction {
  /// Creates a proposed action.
  const FixAction({
    required this.actionId,
    required this.kind,
    required this.lineKey,
    required this.shopperExplanation,
    this.targetQuantity,
    this.replacement,
  });

  /// Stable identifier within its plan.
  final String actionId;

  /// What the action does.
  final FixKind kind;

  /// The line the action changes.
  final String lineKey;

  /// New quantity for [FixKind.reduceQuantity].
  final int? targetQuantity;

  /// Replacement product for [FixKind.replaceProduct].
  final ReplacementCandidate? replacement;

  /// Plain-language description shown before confirmation.
  final String shopperExplanation;

  @override
  bool operator ==(Object other) =>
      other is FixAction &&
      other.actionId == actionId &&
      other.kind == kind &&
      other.lineKey == lineKey &&
      other.targetQuantity == targetQuantity &&
      other.replacement == replacement &&
      other.shopperExplanation == shopperExplanation;

  @override
  int get hashCode => Object.hash(
    actionId,
    kind,
    lineKey,
    targetQuantity,
    replacement,
    shopperExplanation,
  );
}

/// A previewable set of actions with its projected outcome (M2).
final class FixPlan {
  /// Creates a plan, copying [actions] into an unmodifiable list.
  FixPlan({
    required this.planId,
    required this.sourceFingerprint,
    required List<FixAction> actions,
    required this.before,
    required this.projectedAfter,
  }) : actions = List.unmodifiable(actions);

  /// Stable plan identifier.
  final String planId;

  /// Fingerprint of the request the plan was built from.
  final String sourceFingerprint;

  /// Actions in the order they would be applied.
  final List<FixAction> actions;

  /// The report the plan starts from.
  final PreflightReport before;

  /// The analyzer's report for the projected basket.
  final PreflightReport projectedAfter;

  @override
  bool operator ==(Object other) =>
      other is FixPlan &&
      other.planId == planId &&
      other.sourceFingerprint == sourceFingerprint &&
      _listEquals(other.actions, actions) &&
      other.before == before &&
      other.projectedAfter == projectedAfter;

  @override
  int get hashCode => Object.hash(
    planId,
    sourceFingerprint,
    Object.hashAll(actions),
    before,
    projectedAfter,
  );
}

/// The outcome of trying to apply a [FixPlan] (M2).
enum ApplyPlanResult {
  /// Every action was applied and persisted.
  applied,

  /// The basket changed after the plan was built; nothing was changed.
  stalePlan,

  /// The plan contains an action the applier cannot perform.
  unsupportedAction,

  /// State changed in memory but could not be saved.
  persistenceFailed,
}

int _sum(
  List<LinePreflightResult> lines,
  int Function(LinePreflightResult) units,
) => lines.fold(0, (total, line) => total + units(line));

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _fingerprintOf(PreflightRequest request) {
  final buffer = StringBuffer();
  void field(Object? value) {
    final text = value?.toString() ?? '\u0000';
    buffer
      ..write(text.length)
      ..write(':')
      ..write(text);
  }

  void package(PackageAmount? amount) {
    field(amount?.value);
    field(amount?.unit);
  }

  field(request.lines.length);
  for (final line in request.lines) {
    field(line.lineKey);
    field(line.upc);
    field(line.name);
    field(line.basketCategory);
    field(line.originalBenefitCategory);
    field(line.quantity);
    final evidence = line.evidence;
    field(evidence == null ? 'no-evidence' : 'evidence');
    if (evidence != null) {
      field(evidence.aplEligible);
      field(evidence.canonicalCategory);
      package(evidence.packageSize);
      field(evidence.freshness.name);
      field(evidence.sourceLabel);
    }
  }
  final keys = request.benefits.keys.toList()..sort();
  field(keys.length);
  for (final key in keys) {
    final benefit = request.benefits[key]!;
    field(key);
    field(benefit.category);
    field(benefit.allowed);
    field(benefit.used);
    package(benefit.permittedPackageSize);
    field(benefit.freshness.name);
  }

  // Two 30-bit polynomial hashes keep every intermediate value below 2^53,
  // so the result is identical on the Dart VM and on the web.
  final canonical = buffer.toString();
  var a = 7;
  var b = 11;
  for (final unit in canonical.codeUnits) {
    a = (a * 31 + unit) & 0x3fffffff;
    b = (b * 131 + unit) & 0x3fffffff;
  }
  String hex(int value) => value.toRadixString(16).padLeft(8, '0');
  return 'wg1-${hex(a)}${hex(b)}-${canonical.length}';
}
