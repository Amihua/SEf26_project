/// Shared WolfGuard ports (plan Sections 6.4–6.6).
///
/// Each workstream depends on these interfaces, never on another owner's
/// concrete class, so M2 and M4 can build and test against fakes while M1 and
/// M3 are still in progress.
library;

import 'wolfguard_models.dart';

/// M1: classifies every basket unit as covered, self-pay, blocked, or unknown.
///
/// Implementations must be pure and deterministic: no Flutter, Firebase,
/// network, clock lookup, or mutation. Malformed shopper evidence becomes
/// [PreflightStatus.unknown]; only programmer-contract violations throw.
abstract interface class PreflightAnalyzer {
  /// Analyzes the whole basket in [request].
  PreflightReport analyze(PreflightRequest request);
}

/// M2: proposes a repair plan without changing any state.
abstract interface class FixPlanner {
  /// Builds a plan for the non-covered lines of [report].
  ///
  /// [candidatesByLine] maps a line key to evidence-safe replacements already
  /// fetched from a [CandidateProvider]. The plan's projected report must come
  /// from re-running a [PreflightAnalyzer] on a projected request.
  FixPlan propose({
    required PreflightRequest request,
    required PreflightReport report,
    required Map<String, List<ReplacementCandidate>> candidatesByLine,
  });
}

/// M2: applies a confirmed plan to application state.
abstract interface class FixPlanApplier {
  /// Applies [plan] only if the basket still matches its source fingerprint.
  ///
  /// Cancelling a preview never calls this method.
  Future<ApplyPlanResult> apply(FixPlan plan);
}

/// M3: finds read-only, evidence-safe replacements in the imported APL.
abstract interface class CandidateProvider {
  /// Returns up to [max] eligible candidates in [line]'s original category.
  ///
  /// Returns an empty list for a blank, `PAID`, or unknown original category.
  /// Source errors propagate so the presentation layer can offer Retry.
  Future<List<ReplacementCandidate>> findFor({
    required BasketLineSnapshot line,
    int max = 5,
  });
}
