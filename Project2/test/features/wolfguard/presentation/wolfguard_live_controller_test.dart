import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_display_models.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_live_controller.dart';

WolfGuardReportViewData _report({int covered = 1, int blocked = 0}) =>
    WolfGuardReportViewData(
      summary: WolfGuardSummaryViewData.fromCounts(
        totalUnits: covered + blocked,
        coveredUnits: covered,
        selfPayUnits: 0,
        blockedUnits: blocked,
        unknownUnits: 0,
      ),
      lines: const [],
    );

class _FakeSource extends ChangeNotifier implements WolfGuardLiveReportSource {
  final List<Future<WolfGuardReportViewData>> responses = [];
  var analyzeCalls = 0;

  bool get hasChangeListeners => hasListeners;

  @override
  Listenable get basketChanges => this;

  @override
  Future<WolfGuardReportViewData> analyze() {
    final response = responses[analyzeCalls];
    analyzeCalls++;
    return response;
  }

  void basketChanged() => notifyListeners();
}

Widget _host(WolfGuardLiveController controller) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: WolfGuardLiveBasketPanel(controller: controller),
    ),
  ),
);

void main() {
  testWidgets('loads a report immediately and publishes its card state', (
    tester,
  ) async {
    final response = Completer<WolfGuardReportViewData>();
    final source = _FakeSource()..responses.add(response.future);
    final controller = WolfGuardLiveController(source: source);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(controller));
    expect(find.text('Checking basket'), findsOneWidget);
    response.complete(_report());
    await tester.pumpAndSettle();

    expect(source.analyzeCalls, 1);
    expect(find.text('Checkout preflight reviewed'), findsOneWidget);
  });

  testWidgets('basket notification automatically requests a new report', (
    tester,
  ) async {
    final changedResponse = Completer<WolfGuardReportViewData>();
    final source = _FakeSource()
      ..responses.addAll([Future.value(_report()), changedResponse.future]);
    final controller = WolfGuardLiveController(source: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    source.basketChanged();
    await tester.pump();
    expect(find.text('Checking basket'), findsOneWidget);
    changedResponse.complete(_report(covered: 1, blocked: 1));
    await tester.pumpAndSettle();

    expect(source.analyzeCalls, 2);
    expect(find.text('Basket needs review'), findsOneWidget);
    expect(find.text('Blocked 1'), findsOneWidget);
  });

  test('an older analysis cannot replace a newer basket result', () async {
    final first = Completer<WolfGuardReportViewData>();
    final second = Completer<WolfGuardReportViewData>();
    final source = _FakeSource()
      ..responses.addAll([first.future, second.future]);
    final controller = WolfGuardLiveController(
      source: source,
      loadImmediately: false,
    );
    addTearDown(controller.dispose);

    final firstRefresh = controller.refresh();
    final secondRefresh = controller.refresh();
    second.complete(_report(covered: 1, blocked: 1));
    await secondRefresh;
    first.complete(_report(covered: 9));
    await firstRefresh;

    expect(controller.report?.summary.blockedUnits, 1);
    expect(controller.report?.summary.coveredUnits, 1);
  });

  testWidgets('failure is visible and retry can recover', (tester) async {
    final source = _FakeSource()
      ..responses.addAll([
        Future<WolfGuardReportViewData>.error(StateError('offline')),
        Future.value(_report()),
      ]);
    final controller = WolfGuardLiveController(source: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.text('Could not check basket'), findsOneWidget);
    await tester.tap(find.text('Retry preflight'));
    await tester.pumpAndSettle();

    expect(source.analyzeCalls, 2);
    expect(find.text('Checkout preflight reviewed'), findsOneWidget);
  });

  test('dispose detaches the inherited basket change listener', () {
    final source = _FakeSource();
    final controller = WolfGuardLiveController(
      source: source,
      loadImmediately: false,
    );
    expect(source.hasChangeListeners, isTrue);

    controller.dispose();
    expect(source.hasChangeListeners, isFalse);
    source.basketChanged();
    expect(source.analyzeCalls, 0);
  });
}
