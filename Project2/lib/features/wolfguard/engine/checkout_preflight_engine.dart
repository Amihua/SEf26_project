/// M1 whole-basket checkout preflight.
library;

import '../domain/wolfguard_models.dart';
import '../domain/wolfguard_ports.dart';
import 'preflight_rules.dart';

/// Deterministic whole-basket preflight over application-managed allowances.
///
/// The engine runs in two passes:
///
/// 1. **Evidence pass.** Each line is checked on its own: quantity, category,
///    UPC, catalog evidence, allowance record, and explicit package rules.
///    A line either reaches a final outcome (self-pay, blocked, unknown) or
///    becomes a candidate for expected coverage.
/// 2. **Allocation pass.** In stable basket order, candidates draw on the
///    remaining allowance (`allowed - used`) of their category. Units beyond it
///    are blocked; they are never silently rewritten as self-paid. A line with
///    unknown evidence still holds its share of a capped allowance, because the
///    register might count it, but its units stay unknown.
///
/// The engine never upgrades unknown to covered and never mutates its input.
/// It throws [ArgumentError] only for programmer-contract violations:
/// duplicate line keys, or two different allowance records whose keys share
/// one canonical category.
final class CheckoutPreflightEngine implements PreflightAnalyzer {
  /// Creates the stateless engine.
  const CheckoutPreflightEngine();

  @override
  PreflightReport analyze(PreflightRequest request) {
    _requireUniqueLineKeys(request.lines);
    final benefits = _canonicalBenefits(request.benefits);
    final verdicts = [
      for (final line in request.lines) _assess(line, request.lines, benefits),
    ];
    return PreflightReport(
      lines: _allocate(request.lines, verdicts, benefits),
      requestFingerprint: request.fingerprint,
    );
  }

  _Verdict _assess(
    BasketLineSnapshot line,
    List<BasketLineSnapshot> allLines,
    Map<String, BenefitCategorySnapshot> benefits,
  ) {
    if (line.quantity <= 0) {
      return _Final(
        _result(
          line,
          PreflightStatus.unknown,
          units: 1,
          issues: [PreflightIssues.invalidQuantity(line)],
        ),
      );
    }
    if (PreflightCategories.isPaid(line.basketCategory)) {
      return _assessPaid(line, allLines);
    }

    final category = PreflightCategories.benefitCategory(line.basketCategory);
    if (category == null) {
      return _unknown(line, PreflightIssues.missingCategory(line));
    }
    if (line.upc.trim().isEmpty) {
      return _Hold(category, PreflightIssues.blankUpc(line));
    }
    final original = line.originalBenefitCategory;
    if (original != null &&
        PreflightCategories.canonical(original).isNotEmpty &&
        PreflightCategories.benefitCategory(original) != category) {
      return _Hold(category, PreflightIssues.categoryConflict(line, category));
    }

    final evidence = line.evidence;
    if (evidence == null) {
      return _Hold(category, PreflightIssues.missingEvidence(line));
    }
    switch (evidence.freshness) {
      case EvidenceFreshness.stale:
        return _Hold(category, PreflightIssues.staleEvidence(line, evidence));
      case EvidenceFreshness.unknown:
        return _Hold(
          category,
          PreflightIssues.unconfirmedEvidence(line, evidence),
        );
      case EvidenceFreshness.current:
        break;
    }
    switch (evidence.aplEligible) {
      case null:
        return _Hold(
          category,
          PreflightIssues.eligibilityUnknown(line, evidence),
        );
      case false:
        return _blocked(line, PreflightIssues.ineligible(line, evidence));
      case true:
        break;
    }
    final evidenceCategory = PreflightCategories.benefitCategory(
      evidence.canonicalCategory,
    );
    if (evidenceCategory == null) {
      return _Hold(
        category,
        PreflightIssues.evidenceCategoryMissing(line, evidence),
      );
    }
    if (evidenceCategory != category) {
      return _Hold(
        category,
        PreflightIssues.evidenceCategoryConflict(
          line,
          category,
          evidenceCategory,
        ),
      );
    }

    final benefit = benefits[category];
    if (benefit == null) {
      return _blocked(line, PreflightIssues.noBenefit(line, category));
    }
    if (benefit.freshness != EvidenceFreshness.current) {
      return _unknown(line, PreflightIssues.allowanceNotCurrent(line, benefit));
    }
    if (!_isConsistent(benefit)) {
      return _unknown(
        line,
        PreflightIssues.allowanceInconsistent(line, benefit),
      );
    }

    final notes = <String>[];
    final permitted = benefit.permittedPackageSize;
    if (permitted != null) {
      final selected = evidence.packageSize;
      if (selected == null) {
        return _Hold(
          category,
          PreflightIssues.packageEvidenceMissing(line, category, permitted),
        );
      }
      switch (PackageRules.compare(selected, permitted)) {
        case PackageComparison.notComparable:
          return _Hold(
            category,
            PreflightIssues.packageNotComparable(line, selected, permitted),
          );
        case PackageComparison.mismatch:
          return _blocked(
            line,
            PreflightIssues.packageMismatch(
              line,
              category,
              evidence,
              selected,
              permitted,
            ),
          );
        case PackageComparison.match:
          notes.add(PreflightIssues.packageMatchNote(selected));
      }
    }
    return _Eligible(category, notes);
  }

  _Verdict _assessPaid(
    BasketLineSnapshot line,
    List<BasketLineSnapshot> allLines,
  ) {
    var original = PreflightCategories.benefitCategory(
      line.originalBenefitCategory,
    );
    var recovered = false;
    if (original == null) {
      final candidates = _recoverOriginalCategories(line, allLines);
      if (candidates.isEmpty) {
        return _unknown(line, PreflightIssues.paidOriginalMissing(line));
      }
      if (candidates.length > 1) {
        return _unknown(
          line,
          PreflightIssues.paidOriginalAmbiguous(line, candidates),
        );
      }
      original = candidates.single;
      recovered = true;
    }
    return _Final(
      _result(
        line,
        PreflightStatus.selfPay,
        units: line.quantity,
        issues: [
          PreflightIssues.selfPaid(line, original, recovered: recovered),
        ],
      ),
    );
  }

  /// Original categories proven by exact-UPC evidence, sorted.
  ///
  /// Sources: the line's own current catalog record, and other non-`PAID`
  /// lines with the same UPC. More than one result is ambiguous.
  List<String> _recoverOriginalCategories(
    BasketLineSnapshot line,
    List<BasketLineSnapshot> allLines,
  ) {
    final found = <String>{};
    final evidence = line.evidence;
    if (evidence != null && evidence.freshness == EvidenceFreshness.current) {
      final category = PreflightCategories.benefitCategory(
        evidence.canonicalCategory,
      );
      if (category != null) found.add(category);
    }
    final upc = line.upc.trim();
    if (upc.isNotEmpty) {
      for (final other in allLines) {
        if (identical(other, line) || other.upc.trim() != upc) continue;
        final category = PreflightCategories.benefitCategory(
          other.basketCategory,
        );
        if (category != null) found.add(category);
      }
    }
    return found.toList()..sort();
  }

  List<LinePreflightResult> _allocate(
    List<BasketLineSnapshot> lines,
    List<_Verdict> verdicts,
    Map<String, BenefitCategorySnapshot> benefits,
  ) {
    final remaining = <String, int>{};
    final held = <String, int>{};

    /// Remaining units of a usable, capped allowance; null when uncapped or
    /// unusable (missing, not current, or inconsistent).
    int? remainingFor(String category) {
      final benefit = benefits[category];
      if (benefit == null ||
          benefit.allowed == null ||
          benefit.freshness != EvidenceFreshness.current ||
          !_isConsistent(benefit)) {
        return null;
      }
      return remaining.putIfAbsent(
        category,
        () => benefit.allowed! - benefit.used,
      );
    }

    final results = <LinePreflightResult>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      switch (verdicts[i]) {
        case _Final(:final result):
          results.add(result);
        case _Hold(:final category, :final issue):
          final available = remainingFor(category);
          if (available != null) {
            final take = available < line.quantity ? available : line.quantity;
            remaining[category] = available - take;
            held[category] = (held[category] ?? 0) + take;
          }
          results.add(
            _result(
              line,
              PreflightStatus.unknown,
              units: line.quantity,
              issues: [issue],
            ),
          );
        case _Eligible(:final category, :final notes):
          final benefit = benefits[category]!;
          final available = remainingFor(category);
          if (available == null) {
            results.add(
              _result(
                line,
                PreflightStatus.covered,
                units: line.quantity,
                notes: [
                  ...notes,
                  PreflightIssues.prototypeUncappedNote(category),
                ],
              ),
            );
            continue;
          }
          final covered = available < line.quantity ? available : line.quantity;
          final blocked = line.quantity - covered;
          remaining[category] = available - covered;
          if (blocked == 0) {
            results.add(
              _result(
                line,
                PreflightStatus.covered,
                units: covered,
                notes: notes,
              ),
            );
            continue;
          }
          results.add(
            LinePreflightResult(
              lineKey: line.lineKey,
              status: PreflightStatus.blocked,
              quantity: line.quantity,
              coveredUnits: covered,
              selfPayUnits: 0,
              blockedUnits: blocked,
              unknownUnits: 0,
              issues: [
                PreflightIssues.allowanceExceeded(
                  line: line,
                  benefit: benefit,
                  remainingBefore: available,
                  blockedUnits: blocked,
                  heldForUnknown: held[category] ?? 0,
                ),
              ],
              notes: notes,
            ),
          );
      }
    }
    return results;
  }

  static bool _isConsistent(BenefitCategorySnapshot benefit) {
    final allowed = benefit.allowed;
    if (benefit.used < 0) return false;
    if (allowed == null) return true;
    return allowed >= 0 && benefit.used <= allowed;
  }

  static void _requireUniqueLineKeys(List<BasketLineSnapshot> lines) {
    final seen = <String>{};
    for (final line in lines) {
      if (!seen.add(line.lineKey)) {
        throw ArgumentError.value(
          line.lineKey,
          'request.lines',
          'Line keys must be unique within a request',
        );
      }
    }
  }

  static Map<String, BenefitCategorySnapshot> _canonicalBenefits(
    Map<String, BenefitCategorySnapshot> raw,
  ) {
    final result = <String, BenefitCategorySnapshot>{};
    raw.forEach((key, benefit) {
      final category = PreflightCategories.canonical(key);
      final existing = result[category];
      if (existing != null && existing != benefit) {
        throw ArgumentError.value(
          key,
          'request.benefits',
          'Two different allowance records share canonical category $category',
        );
      }
      result[category] = benefit;
    });
    return result;
  }

  static _Final _unknown(BasketLineSnapshot line, PreflightIssue issue) =>
      _Final(
        _result(
          line,
          PreflightStatus.unknown,
          units: line.quantity,
          issues: [issue],
        ),
      );

  static _Final _blocked(BasketLineSnapshot line, PreflightIssue issue) =>
      _Final(
        _result(
          line,
          PreflightStatus.blocked,
          units: line.quantity,
          issues: [issue],
        ),
      );

  /// A result whose [units] all share one [status].
  static LinePreflightResult _result(
    BasketLineSnapshot line,
    PreflightStatus status, {
    required int units,
    List<PreflightIssue> issues = const [],
    List<String> notes = const [],
  }) => LinePreflightResult(
    lineKey: line.lineKey,
    status: status,
    quantity: line.quantity,
    coveredUnits: status == PreflightStatus.covered ? units : 0,
    selfPayUnits: status == PreflightStatus.selfPay ? units : 0,
    blockedUnits: status == PreflightStatus.blocked ? units : 0,
    unknownUnits: status == PreflightStatus.unknown ? units : 0,
    issues: issues,
    notes: notes,
  );
}

/// Outcome of the evidence pass for one line.
sealed class _Verdict {
  const _Verdict();
}

/// The line's outcome is already decided.
final class _Final extends _Verdict {
  const _Final(this.result);
  final LinePreflightResult result;
}

/// Unknown evidence; still holds its share of [category]'s capped allowance.
final class _Hold extends _Verdict {
  const _Hold(this.category, this.issue);
  final String category;
  final PreflightIssue issue;
}

/// Passed every evidence check; competes for [category]'s allowance.
final class _Eligible extends _Verdict {
  const _Eligible(this.category, this.notes);
  final String category;
  final List<String> notes;
}
