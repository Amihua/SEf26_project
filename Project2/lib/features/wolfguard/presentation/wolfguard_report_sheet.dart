import 'package:flutter/material.dart';

import 'wolfguard_display_models.dart';

/// Opens the detailed WolfGuard report without changing the basket.
Future<void> showWolfGuardReportSheet(
  BuildContext context, {
  required WolfGuardReportViewData report,
  ValueChanged<WolfGuardLineViewData>? onLineAction,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        WolfGuardReportSheet(report: report, onLineAction: onLineAction),
  );
}

/// Read-only basket report with item-level outcomes and evidence.
class WolfGuardReportSheet extends StatelessWidget {
  const WolfGuardReportSheet({
    super.key,
    required this.report,
    this.onLineAction,
  });

  final WolfGuardReportViewData report;
  final ValueChanged<WolfGuardLineViewData>? onLineAction;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WolfGuard checkout preflight',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Review every non-covered or unknown item before checkout.',
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close WolfGuard report',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ReportSummary(summary: report.summary),
            const SizedBox(height: 12),
            for (final line in report.lines) ...[
              _LineReportCard(line: line, onAction: onLineAction),
              const SizedBox(height: 10),
            ],
            const Divider(height: 24),
            Text(
              'Expected coverage uses app-managed allowances and available '
              'evidence. Unknown means WolfGuard cannot safely decide; this is '
              'not an official WIC balance or checkout decision.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportSummary extends StatelessWidget {
  const _ReportSummary({required this.summary});

  final WolfGuardSummaryViewData summary;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: summary.semanticsLabel,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F8),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            Text('Covered ${summary.coveredUnits}'),
            Text('Self-paid ${summary.selfPayUnits}'),
            Text('Blocked ${summary.blockedUnits}'),
            Text('Unknown ${summary.unknownUnits}'),
          ],
        ),
      ),
    );
  }
}

class _LineReportCard extends StatelessWidget {
  const _LineReportCard({required this.line, this.onAction});

  final WolfGuardLineViewData line;
  final ValueChanged<WolfGuardLineViewData>? onAction;

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(line.status);
    return Semantics(
      container: true,
      label: line.semanticsLabel,
      child: Card(
        key: ValueKey('wolfguard-line-${line.lineKey}'),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: visual.color.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                          line.productName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${line.statusLabel} · quantity ${line.quantity}',
                          style: TextStyle(
                            color: visual.color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              for (final issue in line.issues) ...[
                const SizedBox(height: 12),
                Text(
                  issue.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(issue.explanation),
                const SizedBox(height: 5),
                Text(
                  'Next step: ${issue.suggestedNextStep}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                if (issue.evidenceLabels.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Evidence: ${issue.evidenceLabels.join(', ')}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ],
              if (line.actionLabel case final label?) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: onAction == null ? null : () => onAction!(line),
                  child: Text(label),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  _LineVisual _visualFor(WolfGuardLineStatus status) => switch (status) {
    WolfGuardLineStatus.covered => const _LineVisual(
      icon: Icons.check_circle_outline,
      color: Color(0xFF1B7F3A),
    ),
    WolfGuardLineStatus.selfPay => const _LineVisual(
      icon: Icons.payments_outlined,
      color: Colors.blueGrey,
    ),
    WolfGuardLineStatus.blocked => const _LineVisual(
      icon: Icons.block_outlined,
      color: Color(0xFFD1001C),
    ),
    WolfGuardLineStatus.unknown => const _LineVisual(
      icon: Icons.help_outline,
      color: Color(0xFF9A6700),
    ),
  };
}

class _LineVisual {
  const _LineVisual({required this.icon, required this.color});

  final IconData icon;
  final Color color;
}
