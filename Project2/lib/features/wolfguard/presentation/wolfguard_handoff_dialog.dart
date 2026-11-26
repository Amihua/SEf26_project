import 'package:flutter/material.dart';

import 'wolfguard_display_models.dart';

/// Shopper choice when checkout is requested before WolfGuard is ready.
enum WolfGuardHandoffDecision { proceed, review, cancel }

/// Returns `proceed` immediately for a reviewed basket; otherwise asks the
/// shopper to review or explicitly acknowledge the prototype limitation.
Future<WolfGuardHandoffDecision> requestWolfGuardHandoff(
  BuildContext context, {
  required WolfGuardSummaryViewData summary,
}) async {
  if (summary.readyForHandoff) return WolfGuardHandoffDecision.proceed;

  final decision = await showDialog<WolfGuardHandoffDecision>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _WolfGuardHandoffDialog(summary: summary),
  );
  return decision ?? WolfGuardHandoffDecision.cancel;
}

class _WolfGuardHandoffDialog extends StatefulWidget {
  const _WolfGuardHandoffDialog({required this.summary});

  final WolfGuardSummaryViewData summary;

  @override
  State<_WolfGuardHandoffDialog> createState() =>
      _WolfGuardHandoffDialogState();
}

class _WolfGuardHandoffDialogState extends State<_WolfGuardHandoffDialog> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.gpp_maybe_outlined, color: Color(0xFF9A6700)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Review before checkout',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'WolfGuard cannot call this basket reviewed yet.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                Text('Covered ${summary.coveredUnits}'),
                Text('Self-paid ${summary.selfPayUnits}'),
                Text('Blocked ${summary.blockedUnits}'),
                Text('Unknown ${summary.unknownUnits}'),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Review blocked or unknown items first. You may still continue '
              'because WolfGuard is guidance, not a payment gate.',
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _acknowledged,
              onChanged: (value) =>
                  setState(() => _acknowledged = value ?? false),
              title: const Text(
                'I understand this is not an official checkout decision.',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _acknowledged
                  ? () => Navigator.of(
                      context,
                    ).pop(WolfGuardHandoffDecision.proceed)
                  : null,
              child: const Text('Continue anyway'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () =>
                  Navigator.of(context).pop(WolfGuardHandoffDecision.review),
              child: const Text('Review report'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(WolfGuardHandoffDecision.cancel),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
