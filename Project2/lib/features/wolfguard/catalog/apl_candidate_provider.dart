/// M3: evidence-safe replacement search backed by the inherited NC APL.
///
/// Owner: Feiyang. This adapter is read-only. It turns
/// [AplService.eligibleReplacements] records into domain
/// [ReplacementCandidate]s and never decides coverage: M2's planner and M1's
/// analyzer still judge whether a candidate actually repairs a line.
library;

import '../../../services/apl_service.dart';
import '../domain/wolfguard_models.dart';
import '../domain/wolfguard_ports.dart';
import '../engine/preflight_rules.dart';

/// Finds eligible same-category alternatives in the imported NC APL.
///
/// Contract (plan Section 6.6):
///
/// - read-only, with no basket or balance mutation;
/// - a blank, `PAID`, or `UNKNOWN` original category returns an empty list;
/// - the current product's exact UPC is excluded;
/// - only records with `eligible == true` are returned;
/// - each candidate's category is canonical and equal to the line's original
///   benefit category;
/// - candidate UPCs are the Firestore document IDs, unique and unmodified;
/// - package size stays null, because the APL accounting unit is not a
///   verified package size;
/// - catalog errors propagate so the presentation layer can offer Retry.
final class AplCandidateProvider implements CandidateProvider {
  /// Searches [apl] for replacements.
  AplCandidateProvider(this._apl);

  final AplService _apl;

  /// Source shown with every candidate this provider returns.
  static const String sourceLabel = 'Imported NC APL';

  /// The evidence label for a candidate from this provider.
  ///
  /// It says "same-category candidate" and never "verified package match":
  /// the imported APL cannot prove a package size.
  static const String candidateEvidenceLabel =
      '$sourceLabel: same-category candidate; package size not verified';

  @override
  Future<List<ReplacementCandidate>> findFor({
    required BasketLineSnapshot line,
    int max = 5,
  }) async {
    final category = originalBenefitCategory(line);
    if (category == null || max <= 0) return const [];

    final records = await _apl.eligibleReplacements(
      category,
      excludeUpc: line.upc,
      max: max,
    );

    final byUpc = <String, ReplacementCandidate>{};
    for (final record in records) {
      final candidate = _candidateFrom(record, category: category, line: line);
      if (candidate == null) continue;
      byUpc.putIfAbsent(candidate.upc, () => candidate);
      if (byUpc.length == max) break;
    }
    return List.unmodifiable(byUpc.values);
  }

  /// The benefit category replacements must share with [line], or null.
  ///
  /// A `PAID` line is searched in the category it overflowed from. A `PAID`
  /// line with no recorded origin, or any blank or `UNKNOWN` category, has
  /// no safe search category.
  static String? originalBenefitCategory(BasketLineSnapshot line) =>
      PreflightCategories.benefitCategory(
        line.originalBenefitCategory ?? line.basketCategory,
      );

  /// Re-checks one APL record against the contract before trusting it.
  ReplacementCandidate? _candidateFrom(
    Map<String, dynamic> record, {
    required String category,
    required BasketLineSnapshot line,
  }) {
    final upc = record['upc'];
    if (upc is! String || upc.trim().isEmpty || upc == line.upc) return null;
    if (record['eligible'] != true) return null;
    if (PreflightCategories.benefitCategory(record['category']) != category) {
      return null;
    }
    final rawName = record['name'];
    final name = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim()
        : 'UPC $upc';
    return ReplacementCandidate(
      upc: upc,
      name: name,
      canonicalCategory: category,
      aplEligible: true,
      freshness: EvidenceFreshness.current,
      evidenceLabel: candidateEvidenceLabel,
    );
  }
}
