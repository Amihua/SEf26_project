import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../screens/basket_screen.dart';
import '../../../state/app_state.dart';
import '../domain/wolfguard_ports.dart';
import 'wolfguard_app_state_repair_coordinator.dart';
import 'wolfguard_app_state_report_source.dart';
import 'wolfguard_basket_integration.dart';
import 'wolfguard_domain_rehearsal_driver.dart';
import 'wolfguard_live_controller.dart';

/// Composes production WolfGuard dependencies around the inherited basket.
///
/// The inherited screen remains responsible for basket layout and navigation.
/// This wrapper owns the live controller lifecycle and injects M1 analysis and
/// M2 repair callbacks through [WolfGuardBasketIntegration].
class WolfGuardBasketScreen extends StatefulWidget {
  const WolfGuardBasketScreen({super.key, this.candidateProvider});

  /// Optional M3 catalog implementation supplied by the composition root.
  ///
  /// When absent, the production route keeps the verified M1/M2 flow and does
  /// not expose a replacement search backed by fabricated data.
  final CandidateProvider? candidateProvider;

  @override
  State<WolfGuardBasketScreen> createState() => _WolfGuardBasketScreenState();
}

class _WolfGuardBasketScreenState extends State<WolfGuardBasketScreen> {
  AppState? _boundState;
  CandidateProvider? _boundCandidateProvider;
  WolfGuardLiveController? _controller;
  WolfGuardBasketIntegration? _integration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind(context.read<AppState>());
  }

  @override
  void didUpdateWidget(covariant WolfGuardBasketScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.candidateProvider, widget.candidateProvider)) {
      _bind(context.read<AppState>());
    }
  }

  void _bind(AppState state) {
    if (identical(state, _boundState) &&
        identical(widget.candidateProvider, _boundCandidateProvider)) {
      return;
    }

    _controller?.dispose();
    final source = WolfGuardAppStateReportSource(state: state);
    final controller = WolfGuardLiveController(source: source);
    final repair = WolfGuardAppStateRepairCoordinator(
      source: source,
      candidateProvider: widget.candidateProvider,
    );
    _boundState = state;
    _boundCandidateProvider = widget.candidateProvider;
    _controller = controller;
    _integration = WolfGuardBasketIntegration(
      controller: controller,
      onPrepareFix: repair.prepare,
      onLoadCandidates: repair.supportsCandidates
          ? repair.loadCandidates
          : null,
      onPrepareReplacementFix: repair.supportsCandidates
          ? repair.prepareReplacement
          : null,
      onApplyFix: repair.apply,
      rehearsalDriver: WolfGuardDomainRehearsalDriver(),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BasketScreen(wolfGuard: _integration);
  }
}
