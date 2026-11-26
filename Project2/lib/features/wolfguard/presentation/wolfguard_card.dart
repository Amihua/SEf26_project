import 'package:flutter/material.dart';

import 'wolfguard_display_models.dart';

/// Basket-level WolfGuard status and entry point to the detailed report.
class WolfGuardCard extends StatelessWidget {
  const WolfGuardCard({
    super.key,
    required this.data,
    this.onReview,
    this.onRetry,
  });

  final WolfGuardSummaryViewData data;
  final VoidCallback? onReview;
  final VoidCallback? onRetry;

  static const Color _red = Color(0xFFD1001C);
  static const Color _green = Color(0xFF1B7F3A);
  static const Color _amber = Color(0xFF9A6700);

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(data.state);
    return Semantics(
      container: true,
      label: data.semanticsLabel,
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: visual.color.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(visual.icon, color: visual.color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          visual.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _message,
                          style: TextStyle(
                            height: 1.35,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (data.state
                  case WolfGuardCardState.ready ||
                      WolfGuardCardState.attention) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CountChip(
                      label: 'Covered',
                      count: data.coveredUnits,
                      color: _green,
                    ),
                    _CountChip(
                      label: 'Self-paid',
                      count: data.selfPayUnits,
                      color: Colors.blueGrey.shade700,
                    ),
                    _CountChip(
                      label: 'Blocked',
                      count: data.blockedUnits,
                      color: _red,
                    ),
                    _CountChip(
                      label: 'Unknown',
                      count: data.unknownUnits,
                      color: _amber,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: onReview,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Review with WolfGuard'),
                ),
              ],
              if (data.state == WolfGuardCardState.loading) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (data.state == WolfGuardCardState.error) ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry preflight'),
                ),
              ],
              if (data.state != WolfGuardCardState.empty) ...[
                const SizedBox(height: 12),
                Text(
                  'Expected coverage uses app-managed allowances and available '
                  'evidence; it is not an official checkout decision.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String get _message => switch (data.state) {
    WolfGuardCardState.empty =>
      'Add products to start a whole-basket checkout preflight.',
    WolfGuardCardState.loading =>
      'Checking the whole basket against the available evidence.',
    WolfGuardCardState.ready =>
      'No blocked or unknown units remain. Review self-paid items before checkout.',
    WolfGuardCardState.attention =>
      'Some items need a decision before the basket can be called reviewed.',
    WolfGuardCardState.error =>
      data.errorMessage ?? 'The basket could not be checked.',
  };

  _CardVisual _visualFor(WolfGuardCardState state) => switch (state) {
    WolfGuardCardState.empty => const _CardVisual(
      title: 'WolfGuard checkout preflight',
      icon: Icons.shield_outlined,
      color: Colors.blueGrey,
    ),
    WolfGuardCardState.loading => const _CardVisual(
      title: 'Checking basket',
      icon: Icons.shield_outlined,
      color: Colors.blueGrey,
    ),
    WolfGuardCardState.ready => const _CardVisual(
      title: 'Checkout preflight reviewed',
      icon: Icons.verified_user_outlined,
      color: _green,
    ),
    WolfGuardCardState.attention => const _CardVisual(
      title: 'Basket needs review',
      icon: Icons.gpp_maybe_outlined,
      color: _amber,
    ),
    WolfGuardCardState.error => const _CardVisual(
      title: 'Could not check basket',
      icon: Icons.error_outline,
      color: _red,
    ),
  };
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $count',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Text(
          '$label $count',
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _CardVisual {
  const _CardVisual({
    required this.title,
    required this.icon,
    required this.color,
  });

  final String title;
  final IconData icon;
  final Color color;
}
