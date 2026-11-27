import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_app_state_report_source.dart';
import 'package:wolfbite/features/wolfguard/presentation/wolfguard_display_models.dart';
import 'package:wolfbite/state/app_state.dart';

AppState _state(FakeFirebaseFirestore db) {
  final state = AppState(db: db);
  state.balances['MILK'] = {'allowed': 3, 'used': 1};
  state.basket.add({
    'upc': '111',
    'name': 'Test milk',
    'category': 'MILK',
    'qty': 1,
  });
  return state;
}

Map<String, dynamic> _eligibleMilk() => {
  'upc': '111',
  'name': 'Test milk',
  'category': 'MILK',
  'eligible': true,
};

void main() {
  test('real analyzer maps live AppState and exact APL evidence', () async {
    final db = FakeFirebaseFirestore();
    final state = _state(db);
    final source = WolfGuardAppStateReportSource(
      state: state,
      aplLookup: (_) async => _eligibleMilk(),
      now: () => DateTime.utc(2026, 11, 27),
    );

    final report = await source.analyze();

    expect(report.summary.state, WolfGuardCardState.ready);
    expect(report.summary.coveredUnits, 1);
    expect(report.lines.single.productName, 'Test milk');
    expect(report.lines.single.status, WolfGuardLineStatus.covered);
    expect(source.latestRequest?.lines.single.evidence?.aplEligible, isTrue);
    expect(source.latestReport?.coveredUnits, 1);
  });

  test('duplicate basket UPC is looked up once per analysis', () async {
    final db = FakeFirebaseFirestore();
    final state = _state(db);
    state.basket.add({
      'upc': '111',
      'name': 'Test milk paid',
      'category': 'PAID',
      'original_benefit_category': 'MILK',
      'qty': 1,
    });
    state.balances['PAID'] = {'allowed': null, 'used': 1};
    var calls = 0;
    final source = WolfGuardAppStateReportSource(
      state: state,
      aplLookup: (_) async {
        calls++;
        return _eligibleMilk();
      },
    );

    final report = await source.analyze();

    expect(calls, 1);
    expect(report.summary.coveredUnits, 1);
    expect(report.summary.selfPayUnits, 1);
    expect(report.summary.readyForHandoff, isTrue);
  });

  test(
    'missing APL record stays unknown instead of becoming covered',
    () async {
      final state = _state(FakeFirebaseFirestore());
      final source = WolfGuardAppStateReportSource(
        state: state,
        aplLookup: (_) async => null,
      );

      final report = await source.analyze();

      expect(report.summary.unknownUnits, 1);
      expect(report.summary.state, WolfGuardCardState.attention);
      expect(report.lines.single.status, WolfGuardLineStatus.unknown);
      expect(report.lines.single.issues, isNotEmpty);
    },
  );

  test(
    'catalog failure propagates and does not publish partial state',
    () async {
      final state = _state(FakeFirebaseFirestore());
      final source = WolfGuardAppStateReportSource(
        state: state,
        aplLookup: (_) async => throw StateError('APL unavailable'),
      );

      await expectLater(source.analyze(), throwsStateError);

      expect(source.latestRequest, isNull);
      expect(source.latestReport, isNull);
    },
  );

  test(
    'snapshot detects a live basket change after successful analysis',
    () async {
      final state = _state(FakeFirebaseFirestore());
      final source = WolfGuardAppStateReportSource(
        state: state,
        aplLookup: (_) async => _eligibleMilk(),
        now: () => DateTime.utc(2026, 11, 27),
      );
      await source.analyze();
      final analyzedFingerprint = source.latestRequest!.fingerprint;

      state.basket.single['qty'] = 2;
      final liveSnapshot = source.snapshotWithLatestEvidence();

      expect(liveSnapshot.fingerprint, isNot(analyzedFingerprint));
      expect(liveSnapshot.lines.single.quantity, 2);
    },
  );

  test('default lookup reads the inherited AplService', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('apl').doc('111').set(_eligibleMilk());
    final source = WolfGuardAppStateReportSource(
      state: _state(db),
      now: () => DateTime.utc(2026, 11, 27),
    );

    final report = await source.analyze();

    expect(report.summary.coveredUnits, 1);
    expect(report.lines.single.status, WolfGuardLineStatus.covered);
  });
}
