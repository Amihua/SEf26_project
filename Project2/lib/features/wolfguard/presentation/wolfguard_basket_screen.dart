import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../screens/basket_screen.dart';
import '../../../state/app_state.dart';
import 'wolfguard_app_state_repair_coordinator.dart';
import 'wolfguard_app_state_report_source.dart';
import 'wolfguard_basket_integration.dart';
import 'wolfguard_live_controller.dart';

/// Composes production WolfGuard dependencies around the inherited basket.
///
/// The inherited screen remains responsible for basket layout and navigation.
/// This wrapper owns the live controller lifecycle and injects M1 analysis and
/// M2 repair callbacks through [WolfGuardBasketIntegration].
class WolfGuardBasketScreen extends StatefulWidget {
  const WolfGuardBasketScreen({super.key});

  @override
  State<WolfGuardBasketScreen> createState() => _WolfGuardBasketScreenState();
}

class _WolfGuardBasketScreenState extends State<WolfGuardBasketScreen> {
  AppState? _boundState;
  WolfGuardLiveController? _controller;
  WolfGuardBasketIntegration? _integration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.read<AppState>();
    if (identical(state, _boundState)) return;

    _controller?.dispose();
    final source = WolfGuardAppStateReportSource(state: state);
    final controller = WolfGuardLiveController(source: source);
    final repair = WolfGuardAppStateRepairCoordinator(source: source);
    _boundState = state;
    _controller = controller;
    _integration = WolfGuardBasketIntegration(
      controller: controller,
      onPrepareFix: repair.prepare,
      onApplyFix: repair.apply,
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
