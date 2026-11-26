import 'package:flutter/material.dart';

import 'wolfguard_card.dart';
import 'wolfguard_display_models.dart';
import 'wolfguard_fix_sheet.dart';
import 'wolfguard_report_sheet.dart';

/// Presentation port for a fixture session backed by production WolfGuard logic.
///
/// The eventual integration adapter must create an isolated fixture request and
/// call the same analyzer/planner used by the real basket. It must never expose
/// or mutate the signed-in shopper's [AppState].
abstract interface class WolfGuardRehearsalDriver {
  Future<WolfGuardReportViewData> loadReport();

  Future<WolfGuardFixPlanViewData?> planFor(WolfGuardLineViewData line);

  Future<WolfGuardApplyViewOutcome> apply(WolfGuardFixPlanViewData plan);
}

/// Deterministic, clearly synthetic WolfGuard walkthrough entry point.
class WolfGuardRehearsalScreen extends StatefulWidget {
  const WolfGuardRehearsalScreen({super.key, required this.driver});

  final WolfGuardRehearsalDriver driver;

  @override
  State<WolfGuardRehearsalScreen> createState() =>
      _WolfGuardRehearsalScreenState();
}

class _WolfGuardRehearsalScreenState extends State<WolfGuardRehearsalScreen> {
  WolfGuardReportViewData? _report;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await widget.driver.loadReport();
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _openReport() async {
    final report = _report;
    if (report == null) return;
    await showWolfGuardReportSheet(
      context,
      report: report,
      onLineAction: _openRepair,
    );
  }

  Future<void> _openRepair(WolfGuardLineViewData line) async {
    Navigator.of(context).pop();
    final plan = await widget.driver.planFor(line);
    if (!mounted) return;
    if (plan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No safe repair is available for this sample item.'),
        ),
      );
      return;
    }

    final applied = await showWolfGuardFixSheet(
      context,
      plan: plan,
      onApply: () => widget.driver.apply(plan),
    );
    if (applied == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _loading
        ? const WolfGuardSummaryViewData.loading()
        : _error != null
        ? const WolfGuardSummaryViewData.error(
            'The synthetic rehearsal could not be loaded.',
          )
        : _report!.summary;

    return Scaffold(
      appBar: AppBar(title: const Text('Try WolfGuard rehearsal')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Semantics(
              container: true,
              label: 'Synthetic sample. Not live benefits.',
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF9A6700)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.science_outlined, color: Color(0xFF7A5200)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Synthetic sample — not live benefits. This isolated '
                        'basket demonstrates WolfGuard without changing your '
                        'shopping basket.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            WolfGuardCard(
              data: summary,
              onReview: _report == null ? null : _openReport,
              onRetry: _loading ? null : _load,
            ),
            const SizedBox(height: 16),
            Text(
              'This rehearsal uses fixture evidence. It does not contact '
              'Firebase, a retailer, or an official WIC benefit account.',
              style: TextStyle(color: Colors.grey.shade700, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
