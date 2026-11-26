import 'package:flutter/material.dart';

import 'wolfguard_display_models.dart';

typedef WolfGuardApplyCallback = Future<WolfGuardApplyViewOutcome> Function();

/// Opens a repair preview. `false` means cancel, `true` means applied.
Future<bool?> showWolfGuardFixSheet(
  BuildContext context, {
  required WolfGuardFixPlanViewData plan,
  required WolfGuardApplyCallback onApply,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    showDragHandle: true,
    builder: (_) => WolfGuardFixSheet(plan: plan, onApply: onApply),
  );
}

/// Shows a before/after repair preview and applies only after confirmation.
class WolfGuardFixSheet extends StatefulWidget {
  const WolfGuardFixSheet({
    super.key,
    required this.plan,
    required this.onApply,
  });

  final WolfGuardFixPlanViewData plan;
  final WolfGuardApplyCallback onApply;

  @override
  State<WolfGuardFixSheet> createState() => _WolfGuardFixSheetState();
}

class _WolfGuardFixSheetState extends State<WolfGuardFixSheet> {
  bool _applying = false;
  String? _error;

  Future<void> _apply() async {
    if (_applying) return;
    setState(() {
      _applying = true;
      _error = null;
    });

    final outcome = await widget.onApply();
    if (!mounted) return;
    if (outcome == WolfGuardApplyViewOutcome.applied) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _applying = false;
      _error = switch (outcome) {
        WolfGuardApplyViewOutcome.stalePlan =>
          'The basket changed after this preview. Close it and create a new plan.',
        WolfGuardApplyViewOutcome.unsupportedAction =>
          'This repair is no longer supported. The basket was not changed.',
        WolfGuardApplyViewOutcome.persistenceFailed =>
          'The repair could not be saved. Review the current basket before retrying.',
        WolfGuardApplyViewOutcome.applied => null,
      };
    });
  }

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
            const Text(
              'Preview basket repair',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text('Nothing changes until you select Apply repairs.'),
            const SizedBox(height: 18),
            _BeforeAfter(plan: widget.plan),
            const SizedBox(height: 18),
            Text(
              widget.plan.actions.length == 1
                  ? 'Proposed change'
                  : 'Proposed changes',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final action in widget.plan.actions) ...[
              Semantics(
                container: true,
                label: '${action.title}. ${action.description}',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.auto_fix_high_outlined),
                  title: Text(action.title),
                  subtitle: Text(action.description),
                ),
              ),
              const Divider(height: 1),
            ],
            if (_error case final error?) ...[
              const SizedBox(height: 14),
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: const TextStyle(
                    color: Color(0xFFD1001C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _applying ? null : _apply,
              icon: _applying
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_applying ? 'Applying repairs…' : 'Apply repairs'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _applying
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            const SizedBox(height: 12),
            Text(
              'This preview uses application-managed allowances and does not '
              'guarantee retailer acceptance.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeforeAfter extends StatelessWidget {
  const _BeforeAfter({required this.plan});

  final WolfGuardFixPlanViewData plan;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _SnapshotSummary(label: 'Before', data: plan.before),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 24),
          child: Icon(Icons.arrow_forward),
        ),
        Expanded(
          child: _SnapshotSummary(
            label: 'Projected after',
            data: plan.projectedAfter,
          ),
        ),
      ],
    );
  }
}

class _SnapshotSummary extends StatelessWidget {
  const _SnapshotSummary({required this.label, required this.data});

  final String label;
  final WolfGuardSummaryViewData data;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$label. ${data.semanticsLabel}',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Covered ${data.coveredUnits}'),
            Text('Self-paid ${data.selfPayUnits}'),
            Text('Blocked ${data.blockedUnits}'),
            Text('Unknown ${data.unknownUnits}'),
          ],
        ),
      ),
    );
  }
}
