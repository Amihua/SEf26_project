import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_candidate_sheet.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_display_models.dart';

const _unknownCandidate = WolfGuardReplacementCandidateViewData(
  upc: '000111222333',
  name: 'Candidate Oats',
  canonicalCategory: 'Breakfast Cereal',
  evidenceLabel: 'NC APL exact UPC',
  packageMatch: WolfGuardPackageMatchView.unknown,
);

const _verifiedCandidate = WolfGuardReplacementCandidateViewData(
  upc: '999888777666',
  name: 'Candidate Corn Flakes',
  canonicalCategory: 'Breakfast Cereal',
  evidenceLabel: 'Synthetic rehearsal evidence',
  packageMatch: WolfGuardPackageMatchView.verified,
  packageEvidenceLabel: '18 oz explicit package evidence',
);

Widget _host({
  required WolfGuardCandidateLoader loader,
  ValueChanged<WolfGuardReplacementCandidateViewData?>? onResult,
}) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: TextButton(
        onPressed: () async {
          final result = await showWolfGuardCandidateSheet(
            context,
            productName: 'Original Cereal',
            loadCandidates: loader,
          );
          onResult?.call(result);
        },
        child: const Text('Find alternatives'),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Find alternatives'));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('shows loading until catalog evidence arrives', (tester) async {
    final response = Completer<List<WolfGuardReplacementCandidateViewData>>();
    await tester.pumpWidget(_host(loader: () => response.future));

    await _open(tester);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      find.text('Checking the available catalog evidence…'),
      findsOneWidget,
    );

    response.complete(const [_unknownCandidate]);
    await tester.pumpAndSettle();
    expect(find.text('Candidate Oats'), findsOneWidget);
  });

  testWidgets('distinguishes unknown and verified package evidence', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(loader: () async => const [_unknownCandidate, _verifiedCandidate]),
    );
    await _open(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('Package match unknown · no verified comparable size evidence'),
      findsOneWidget,
    );
    expect(
      find.text('Verified package match · 18 oz explicit package evidence'),
      findsOneWidget,
    );
    expect(find.textContaining('Same benefit category'), findsNWidgets(2));
  });

  testWidgets('selection returns the candidate with its exact UPC', (
    tester,
  ) async {
    WolfGuardReplacementCandidateViewData? selected;
    await tester.pumpWidget(
      _host(
        loader: () async => const [_unknownCandidate],
        onResult: (value) => selected = value,
      ),
    );
    await _open(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Use in repair preview'));
    await tester.pumpAndSettle();
    expect(selected?.upc, '000111222333');
  });

  testWidgets('empty result uses evidence-limited wording', (tester) async {
    await tester.pumpWidget(_host(loader: () async => const []));
    await _open(tester);
    await tester.pumpAndSettle();

    expect(find.text('No evidence-safe alternatives found.'), findsOneWidget);
    expect(
      find.textContaining('does not mean no alternatives exist'),
      findsOneWidget,
    );
  });

  testWidgets('source failure offers retry and does not invent candidates', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(
        loader: () async {
          calls++;
          if (calls == 1) throw StateError('offline');
          return const [_unknownCandidate];
        },
      ),
    );
    await _open(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
    expect(find.text('Candidate Oats'), findsNothing);
    await tester.tap(find.text('Retry alternatives'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Candidate Oats'), findsOneWidget);
  });

  testWidgets('closing without selection returns null', (tester) async {
    WolfGuardReplacementCandidateViewData? selected = _verifiedCandidate;
    await tester.pumpWidget(
      _host(
        loader: () async => const [_unknownCandidate],
        onResult: (value) => selected = value,
      ),
    );
    await _open(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Close replacement search'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
  });

  testWidgets('narrow large-text sheet remains scrollable and closable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2),
        ),
        child: _host(
          loader: () async => const [_unknownCandidate, _verifiedCandidate],
        ),
      ),
    );

    await _open(tester);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsOneWidget);
    expect(find.byTooltip('Close replacement search'), findsOneWidget);
  });
}
