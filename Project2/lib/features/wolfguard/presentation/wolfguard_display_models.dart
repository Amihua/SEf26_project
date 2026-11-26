/// Presentation-only states for the WolfGuard basket summary.
///
/// These types deliberately do not duplicate the shared business-domain
/// contract. The integration adapter maps the eventual preflight report into
/// this immutable display data.
enum WolfGuardCardState { empty, loading, ready, attention, error }

/// Display outcomes mapped from the shared preflight domain by the adapter.
enum WolfGuardLineStatus { covered, selfPay, blocked, unknown }

/// Whether comparable, explicit package evidence supports a candidate match.
enum WolfGuardPackageMatchView { verified, unknown }

/// Read-only replacement candidate mapped from the catalog provider.
class WolfGuardReplacementCandidateViewData {
  const WolfGuardReplacementCandidateViewData({
    required this.upc,
    required this.name,
    required this.canonicalCategory,
    required this.evidenceLabel,
    required this.packageMatch,
    this.packageEvidenceLabel,
  }) : assert(upc != ''),
       assert(name != ''),
       assert(canonicalCategory != ''),
       assert(
         packageMatch != WolfGuardPackageMatchView.verified ||
             packageEvidenceLabel != null,
         'A verified package match must name its explicit evidence.',
       );

  final String upc;
  final String name;
  final String canonicalCategory;
  final String evidenceLabel;
  final WolfGuardPackageMatchView packageMatch;
  final String? packageEvidenceLabel;

  String get packageStatusLabel => switch (packageMatch) {
    WolfGuardPackageMatchView.verified =>
      'Verified package match · $packageEvidenceLabel',
    WolfGuardPackageMatchView.unknown =>
      'Package match unknown · no verified comparable size evidence',
  };
}

/// Evidence-backed explanation shown for one product line.
class WolfGuardIssueViewData {
  const WolfGuardIssueViewData({
    required this.title,
    required this.explanation,
    required this.suggestedNextStep,
    this.evidenceLabels = const [],
  });

  final String title;
  final String explanation;
  final String suggestedNextStep;
  final List<String> evidenceLabels;
}

/// Presentation data for one line in the detailed preflight report.
class WolfGuardLineViewData {
  const WolfGuardLineViewData({
    required this.lineKey,
    required this.productName,
    required this.status,
    required this.quantity,
    required this.coveredUnits,
    required this.selfPayUnits,
    required this.blockedUnits,
    required this.unknownUnits,
    this.issues = const [],
    this.actionLabel,
  });

  final String lineKey;
  final String productName;
  final WolfGuardLineStatus status;
  final int quantity;
  final int coveredUnits;
  final int selfPayUnits;
  final int blockedUnits;
  final int unknownUnits;
  final List<WolfGuardIssueViewData> issues;
  final String? actionLabel;

  String get statusLabel => switch (status) {
    WolfGuardLineStatus.covered => 'Expected covered',
    WolfGuardLineStatus.selfPay => 'Self-paid',
    WolfGuardLineStatus.blocked => 'Blocked',
    WolfGuardLineStatus.unknown => 'Unknown',
  };

  String get semanticsLabel =>
      '$productName, quantity $quantity, $statusLabel. '
      '$coveredUnits covered, $selfPayUnits self-paid, '
      '$blockedUnits blocked, $unknownUnits unknown.';
}

/// Complete display input for the detailed WolfGuard report.
class WolfGuardReportViewData {
  const WolfGuardReportViewData({required this.summary, required this.lines});

  final WolfGuardSummaryViewData summary;
  final List<WolfGuardLineViewData> lines;
}

/// One proposed basket change shown before the shopper confirms it.
class WolfGuardFixActionViewData {
  const WolfGuardFixActionViewData({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;
}

/// Read-only repair-plan preview mapped from the shared repair domain.
class WolfGuardFixPlanViewData {
  const WolfGuardFixPlanViewData({
    required this.planId,
    required this.before,
    required this.projectedAfter,
    required this.actions,
  });

  final String planId;
  final WolfGuardSummaryViewData before;
  final WolfGuardSummaryViewData projectedAfter;
  final List<WolfGuardFixActionViewData> actions;
}

/// Presentation outcomes mapped from Wenbo's plan-application result.
enum WolfGuardApplyViewOutcome {
  applied,
  stalePlan,
  unsupportedAction,
  persistenceFailed,
}

/// Immutable data rendered by the WolfGuard readiness card.
class WolfGuardSummaryViewData {
  const WolfGuardSummaryViewData._({
    required this.state,
    required this.totalUnits,
    required this.coveredUnits,
    required this.selfPayUnits,
    required this.blockedUnits,
    required this.unknownUnits,
    required this.selfPayAcknowledged,
    this.errorMessage,
  });

  /// Builds a summary from already-computed outcome counts.
  factory WolfGuardSummaryViewData.fromCounts({
    required int totalUnits,
    required int coveredUnits,
    required int selfPayUnits,
    required int blockedUnits,
    required int unknownUnits,
    bool selfPayAcknowledged = false,
  }) {
    assert(totalUnits >= 0);
    assert(coveredUnits >= 0);
    assert(selfPayUnits >= 0);
    assert(blockedUnits >= 0);
    assert(unknownUnits >= 0);
    assert(
      coveredUnits + selfPayUnits + blockedUnits + unknownUnits == totalUnits,
      'Every basket unit must have exactly one displayed outcome.',
    );

    final WolfGuardCardState state;
    if (totalUnits == 0) {
      state = WolfGuardCardState.empty;
    } else if (blockedUnits > 0 ||
        unknownUnits > 0 ||
        (selfPayUnits > 0 && !selfPayAcknowledged)) {
      state = WolfGuardCardState.attention;
    } else {
      state = WolfGuardCardState.ready;
    }

    return WolfGuardSummaryViewData._(
      state: state,
      totalUnits: totalUnits,
      coveredUnits: coveredUnits,
      selfPayUnits: selfPayUnits,
      blockedUnits: blockedUnits,
      unknownUnits: unknownUnits,
      selfPayAcknowledged: selfPayAcknowledged,
    );
  }

  /// Summary shown while the application is computing a report.
  const WolfGuardSummaryViewData.loading()
    : this._(
        state: WolfGuardCardState.loading,
        totalUnits: 0,
        coveredUnits: 0,
        selfPayUnits: 0,
        blockedUnits: 0,
        unknownUnits: 0,
        selfPayAcknowledged: false,
      );

  /// Summary shown when the report could not be computed.
  const WolfGuardSummaryViewData.error(String message)
    : this._(
        state: WolfGuardCardState.error,
        totalUnits: 0,
        coveredUnits: 0,
        selfPayUnits: 0,
        blockedUnits: 0,
        unknownUnits: 0,
        selfPayAcknowledged: false,
        errorMessage: message,
      );

  final WolfGuardCardState state;
  final int totalUnits;
  final int coveredUnits;
  final int selfPayUnits;
  final int blockedUnits;
  final int unknownUnits;
  final bool selfPayAcknowledged;
  final String? errorMessage;

  bool get readyForHandoff => state == WolfGuardCardState.ready;

  String get semanticsLabel => switch (state) {
    WolfGuardCardState.empty =>
      'WolfGuard checkout preflight. Basket is empty.',
    WolfGuardCardState.loading =>
      'WolfGuard checkout preflight is checking the basket.',
    WolfGuardCardState.error =>
      'WolfGuard checkout preflight could not check the basket.',
    WolfGuardCardState.ready =>
      'WolfGuard checkout preflight reviewed. '
          '$coveredUnits covered, $selfPayUnits self-paid, '
          '$blockedUnits blocked, $unknownUnits unknown.',
    WolfGuardCardState.attention =>
      'WolfGuard checkout preflight needs review. '
          '$coveredUnits covered, $selfPayUnits self-paid, '
          '$blockedUnits blocked, $unknownUnits unknown.',
  };
}
