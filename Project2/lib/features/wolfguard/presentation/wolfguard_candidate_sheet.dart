import 'package:flutter/material.dart';

import 'wolfguard_display_models.dart';

typedef WolfGuardCandidateLoader =
    Future<List<WolfGuardReplacementCandidateViewData>> Function();

/// Opens an evidence-safe replacement search without mutating the basket.
Future<WolfGuardReplacementCandidateViewData?> showWolfGuardCandidateSheet(
  BuildContext context, {
  required String productName,
  required WolfGuardCandidateLoader loadCandidates,
}) {
  return showModalBottomSheet<WolfGuardReplacementCandidateViewData>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => WolfGuardCandidateSheet(
      productName: productName,
      loadCandidates: loadCandidates,
    ),
  );
}

/// Retryable catalog-candidate UI that returns a selection to the planner.
class WolfGuardCandidateSheet extends StatefulWidget {
  const WolfGuardCandidateSheet({
    super.key,
    required this.productName,
    required this.loadCandidates,
  });

  final String productName;
  final WolfGuardCandidateLoader loadCandidates;

  @override
  State<WolfGuardCandidateSheet> createState() =>
      _WolfGuardCandidateSheetState();
}

class _WolfGuardCandidateSheetState extends State<WolfGuardCandidateSheet> {
  List<WolfGuardReplacementCandidateViewData>? _candidates;
  Object? _error;
  bool _loading = true;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final candidates = await widget.loadCandidates();
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _candidates = List.unmodifiable(candidates);
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Evidence-safe alternatives',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Same-category candidates for ${widget.productName}',
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close replacement search',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              const Text('Checking the available catalog evidence…'),
            ] else if (_error != null) ...[
              Semantics(
                liveRegion: true,
                child: const Text(
                  'Replacement evidence is temporarily unavailable. The '
                  'basket has not changed.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry alternatives'),
              ),
            ] else if (_candidates!.isEmpty) ...[
              const Text(
                'No evidence-safe alternatives found.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'This does not mean no alternatives exist; the current source '
                'did not provide a candidate WolfGuard can safely suggest.',
              ),
            ] else
              for (final candidate in _candidates!) ...[
                _CandidateCard(
                  candidate: candidate,
                  onSelected: () => Navigator.of(context).pop(candidate),
                ),
                const SizedBox(height: 10),
              ],
            const SizedBox(height: 14),
            Text(
              'Candidates share the application benefit category and catalog '
              'evidence. A same-category candidate is not an official checkout '
              'guarantee, and missing package evidence remains unknown.',
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

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.candidate, required this.onSelected});

  final WolfGuardReplacementCandidateViewData candidate;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final verified =
        candidate.packageMatch == WolfGuardPackageMatchView.verified;
    return Semantics(
      container: true,
      label:
          '${candidate.name}. Same benefit category: '
          '${candidate.canonicalCategory}. ${candidate.packageStatusLabel}.',
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade300),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                candidate.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              Text('Same benefit category · ${candidate.canonicalCategory}'),
              const SizedBox(height: 5),
              Text(
                candidate.packageStatusLabel,
                style: TextStyle(
                  color: verified
                      ? const Color(0xFF1B7F3A)
                      : const Color(0xFF9A6700),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Evidence: ${candidate.evidenceLabel}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onSelected,
                child: const Text('Use in repair preview'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
