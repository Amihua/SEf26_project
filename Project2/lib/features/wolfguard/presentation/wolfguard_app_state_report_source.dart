import 'package:flutter/foundation.dart';

import '../../../state/app_state.dart';
import '../domain/wolfguard_models.dart';
import '../domain/wolfguard_ports.dart';
import '../engine/checkout_preflight_engine.dart';
import '../engine/preflight_request_builder.dart';
import 'wolfguard_display_models.dart';
import 'wolfguard_domain_mapper.dart';
import 'wolfguard_live_controller.dart';

/// Looks up one exact UPC in the application's imported APL.
typedef WolfGuardAplLookup = Future<Map<String, dynamic>?> Function(String upc);

/// Production M1 report source backed by the inherited [AppState].
///
/// Each analysis snapshots basket and allowance maps before awaiting catalog
/// reads, so a report never combines lines from two different basket states.
/// [WolfGuardLiveController] handles a later AppState notification by starting
/// a new analysis and discarding the older UI result.
class WolfGuardAppStateReportSource implements WolfGuardLiveReportSource {
  WolfGuardAppStateReportSource({
    required this.state,
    PreflightAnalyzer analyzer = const CheckoutPreflightEngine(),
    WolfGuardAplLookup? aplLookup,
    DateTime Function()? now,
  }) : _analyzer = analyzer,
       _aplLookup = aplLookup ?? state.productCatalog.findByUpc,
       _now = now ?? DateTime.now;

  /// Inherited state listened to by the live controller.
  final AppState state;
  final PreflightAnalyzer _analyzer;
  final WolfGuardAplLookup _aplLookup;
  final DateTime Function() _now;

  Map<String, ProductEvidence> _latestEvidence = const {};
  PreflightRequest? _latestRequest;
  PreflightReport? _latestReport;

  /// Most recent request that completed analysis successfully.
  PreflightRequest? get latestRequest => _latestRequest;

  /// Most recent domain report that completed successfully.
  PreflightReport? get latestReport => _latestReport;

  @override
  Listenable get basketChanges => state;

  @override
  Future<WolfGuardReportViewData> analyze() async {
    final basket = _snapshotBasket();
    final balances = {
      for (final entry in state.balances.entries)
        entry.key: Map<String, Object?>.from(entry.value),
    };
    final evidence = await _loadEvidence(basket);
    final request = PreflightRequestBuilder.fromAppState(
      basket: basket,
      balances: balances,
      evaluatedAt: _now(),
      evidenceByUpc: evidence,
    );
    final report = _analyzer.analyze(request);

    _latestEvidence = Map.unmodifiable(evidence);
    _latestRequest = request;
    _latestReport = report;
    return WolfGuardDomainMapper.report(request, report);
  }

  /// Re-snapshots live state with the evidence used by the latest analysis.
  ///
  /// M2's applier uses this synchronous snapshot to reject a plan when basket
  /// or allowance state changed after preview. A newly introduced UPC has no
  /// cached evidence and therefore cannot accidentally inherit another item’s
  /// catalog facts.
  PreflightRequest snapshotWithLatestEvidence() {
    return PreflightRequestBuilder.fromAppState(
      basket: _snapshotBasket(),
      balances: {
        for (final entry in state.balances.entries)
          entry.key: Map<String, Object?>.from(entry.value),
      },
      evaluatedAt: _now(),
      evidenceByUpc: _latestEvidence,
    );
  }

  List<Map<String, Object?>> _snapshotBasket() {
    return [
      for (final item in state.basket)
        _lineWithExplicitBenefitOrigin(Map<String, Object?>.from(item)),
    ];
  }

  /// M2 carries a benefit line's origin onto a projected PAID line.
  ///
  /// Inherited state stores `original_benefit_category` only after a line has
  /// already moved to PAID. For an ordinary benefit line its current category
  /// is, by definition, the origin. Adding it to this immutable snapshot keeps
  /// M2's preview consistent with its applier without changing AppState data.
  Map<String, Object?> _lineWithExplicitBenefitOrigin(
    Map<String, Object?> line,
  ) {
    final category = line['category'];
    if (category is String &&
        category.trim().toUpperCase() != wolfGuardPaidCategory &&
        line['original_benefit_category'] == null) {
      line['original_benefit_category'] = category;
    }
    return line;
  }

  Future<Map<String, ProductEvidence>> _loadEvidence(
    List<Map<String, Object?>> basket,
  ) async {
    final upcs = <String>{
      for (final item in basket)
        if (item['upc'] case final String upc when upc.trim().isNotEmpty)
          upc.trim(),
    };
    final records = await Future.wait(
      upcs.map((upc) async => MapEntry(upc, await _aplLookup(upc))),
    );
    return {
      for (final entry in records)
        if (PreflightRequestBuilder.evidenceFromAplRecord(entry.value)
            case final evidence?)
          entry.key: evidence,
    };
  }
}
