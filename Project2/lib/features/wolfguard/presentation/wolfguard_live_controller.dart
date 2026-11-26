import 'dart:async';

import 'package:flutter/material.dart';

import 'wolfguard_basket_panel.dart';
import 'wolfguard_display_models.dart';

/// Presentation port that reports basket changes and computes display data.
///
/// The integration adapter can listen to inherited application state and map
/// the shared preflight domain into an immutable [WolfGuardReportViewData].
abstract interface class WolfGuardLiveReportSource {
  Listenable get basketChanges;

  Future<WolfGuardReportViewData> analyze();
}

/// Keeps the displayed WolfGuard report synchronized with basket changes.
///
/// Overlapping analyses are safe: only the newest request may update the UI.
class WolfGuardLiveController extends ChangeNotifier {
  WolfGuardLiveController({
    required WolfGuardLiveReportSource source,
    bool loadImmediately = true,
  }) : _source = source {
    _source.basketChanges.addListener(_handleBasketChange);
    if (loadImmediately) unawaited(refresh());
  }

  final WolfGuardLiveReportSource _source;
  WolfGuardReportViewData? _report;
  Object? _error;
  bool _loading = false;
  bool _disposed = false;
  int _requestGeneration = 0;

  WolfGuardReportViewData? get report => _report;
  Object? get error => _error;
  bool get isLoading => _loading;

  WolfGuardSummaryViewData get summary {
    if (_loading) return const WolfGuardSummaryViewData.loading();
    if (_error != null) {
      return const WolfGuardSummaryViewData.error(
        'WolfGuard could not check the current basket.',
      );
    }
    return _report?.summary ??
        WolfGuardSummaryViewData.fromCounts(
          totalUnits: 0,
          coveredUnits: 0,
          selfPayUnits: 0,
          blockedUnits: 0,
          unknownUnits: 0,
        );
  }

  void _handleBasketChange() => unawaited(refresh());

  /// Requests a fresh report and ignores any older result that finishes later.
  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_requestGeneration;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final nextReport = await _source.analyze();
      if (_disposed || generation != _requestGeneration) return;
      _report = nextReport;
      _loading = false;
      notifyListeners();
    } catch (error) {
      if (_disposed || generation != _requestGeneration) return;
      _error = error;
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _requestGeneration++;
    _source.basketChanges.removeListener(_handleBasketChange);
    super.dispose();
  }
}

/// Reactive basket panel backed by a [WolfGuardLiveController].
class WolfGuardLiveBasketPanel extends StatelessWidget {
  const WolfGuardLiveBasketPanel({
    super.key,
    required this.controller,
    this.onPrepareFix,
    this.onLoadCandidates,
    this.onPrepareReplacementFix,
    this.onApplyFix,
    this.onRepairApplied,
  });

  final WolfGuardLiveController controller;
  final WolfGuardPrepareFixCallback? onPrepareFix;
  final WolfGuardLoadCandidatesCallback? onLoadCandidates;
  final WolfGuardPrepareReplacementFixCallback? onPrepareReplacementFix;
  final WolfGuardApplyPlanCallback? onApplyFix;
  final VoidCallback? onRepairApplied;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final report = controller.report;
        return WolfGuardBasketPanel(
          report: WolfGuardReportViewData(
            summary: controller.summary,
            lines: report?.lines ?? const [],
          ),
          onRetry: controller.refresh,
          onPrepareFix: onPrepareFix,
          onLoadCandidates: onLoadCandidates,
          onPrepareReplacementFix: onPrepareReplacementFix,
          onApplyFix: onApplyFix,
          onRepairApplied: () {
            unawaited(controller.refresh());
            onRepairApplied?.call();
          },
        );
      },
    );
  }
}
