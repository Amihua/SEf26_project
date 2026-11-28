import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/features/wolfguard/catalog/apl_candidate_provider.dart';
import 'package:wolfbite/features/wolfguard/domain/wolfguard_models.dart';
import 'package:wolfbite/features/wolfguard/domain/wolfguard_ports.dart';
import 'package:wolfbite/features/wolfguard/engine/checkout_preflight_engine.dart';
import 'package:wolfbite/features/wolfguard/repair/fix_planner.dart';
import 'package:wolfbite/services/apl_service.dart';

/// M3 (Feiyang): the concrete [AplCandidateProvider] behind the
/// [CandidateProvider] port.

const _milk = 'MILK - WHOLE';

BasketLineSnapshot _line({
  String upc = '000111',
  String category = _milk,
  String? original,
  ProductEvidence? evidence,
}) => BasketLineSnapshot(
  lineKey: '0:$upc:$category',
  upc: upc,
  name: 'Basket milk',
  basketCategory: category,
  originalBenefitCategory: original,
  quantity: 1,
  evidence: evidence,
);

/// An [AplService] whose replacement query is scripted, for contract checks
/// the provider must enforce even if the service misbehaves.
class _ScriptedAplService extends AplService {
  _ScriptedAplService(this.responses)
    : super(db: FakeFirebaseFirestore(), useNutritionCollection: false);

  final List<Object> responses;
  final List<({String category, String? excludeUpc, int max})> calls = [];

  @override
  Future<List<Map<String, dynamic>>> eligibleReplacements(
    String canonicalCategory, {
    String? excludeUpc,
    int max = 5,
  }) async {
    calls.add((category: canonicalCategory, excludeUpc: excludeUpc, max: max));
    final next = responses.length == 1
        ? responses.first
        : responses.removeAt(0);
    if (next is Exception) throw next;
    return [
      for (final record in next as List<Map<String, dynamic>>) {...record},
    ];
  }
}

Map<String, dynamic> _record(
  String upc, {
  String name = 'Candidate milk',
  String category = _milk,
  Object? eligible = true,
}) => {'upc': upc, 'name': name, 'category': category, 'eligible': eligible};

void main() {
  group('AplCandidateProvider with fake Firestore', () {
    late FakeFirebaseFirestore db;
    late AplCandidateProvider provider;

    setUp(() async {
      db = FakeFirebaseFirestore();
      provider = AplCandidateProvider(
        AplService(db: db, useNutritionCollection: false),
      );
      final apl = db.collection('apl');
      await apl.doc('000111').set({
        'name': 'Current milk',
        'category': _milk,
        'categoryCode': '51',
        'eligible': true,
      });
      await apl.doc('000222').set({
        'name': ' Variant label milk ',
        'category': 'MILK-WHOLE',
        'categoryCode': '51',
        'unitOfMeasure': 'GAL',
        'eligible': true,
      });
      await apl.doc('000333').set({
        'name': 'Delisted milk',
        'category': _milk,
        'categoryCode': '51',
        'eligible': false,
      });
      await apl.doc('000444').set({
        'name': 'Reduced fat milk',
        'category': 'MILK - FAT REDUCED',
        'categoryCode': '52',
        'eligible': true,
      });
    });

    test(
      'maps eligible same-category records into honest candidates',
      () async {
        final candidates = await provider.findFor(line: _line());

        expect(candidates, [
          const ReplacementCandidate(
            upc: '000222',
            name: 'Variant label milk',
            canonicalCategory: _milk,
            aplEligible: true,
            freshness: EvidenceFreshness.current,
            evidenceLabel: AplCandidateProvider.candidateEvidenceLabel,
          ),
        ]);
        expect(candidates.single.verifiedPackageSize, isNull);
        expect(
          candidates.single.evidenceLabel,
          allOf(contains('same-category candidate'), contains('not verified')),
        );
      },
    );

    test(
      'a PAID overflow line searches its original benefit category',
      () async {
        final candidates = await provider.findFor(
          line: _line(category: 'PAID', original: 'milk-whole'),
        );

        expect(candidates.map((c) => c.upc), ['000222']);
        expect(candidates.single.canonicalCategory, _milk);
      },
    );

    test('result list is unmodifiable', () async {
      final candidates = await provider.findFor(line: _line());

      expect(() => candidates.add(candidates.first), throwsUnsupportedError);
    });

    test('search leaves the catalog and the line snapshot unchanged', () async {
      final line = _line();
      final before = db.dump();

      await provider.findFor(line: line);

      expect(db.dump(), before);
      expect(line, _line());
    });
  });

  group('AplCandidateProvider contract guards', () {
    for (final (label, line) in [
      ('PAID without origin', _line(category: 'PAID')),
      ('blank category', _line(category: '   ')),
      ('UNKNOWN category', _line(category: 'UNKNOWN')),
      ('PAID origin', _line(category: 'PAID', original: 'paid')),
    ]) {
      test('$label returns no candidates and never queries', () async {
        final apl = _ScriptedAplService([
          [_record('222')],
        ]);

        final candidates = await AplCandidateProvider(apl).findFor(line: line);

        expect(candidates, isEmpty);
        expect(apl.calls, isEmpty);
      });
    }

    test('passes the canonical category, current UPC, and max', () async {
      final apl = _ScriptedAplService([<Map<String, dynamic>>[]]);

      await AplCandidateProvider(apl).findFor(
        line: _line(upc: '0042', category: 'milk-whole'),
        max: 3,
      );

      expect(apl.calls.single, (category: _milk, excludeUpc: '0042', max: 3));
    });

    test('re-checks eligibility, category, UPC, and self exclusion', () async {
      final apl = _ScriptedAplService([
        [
          _record('000111'), // the current product
          _record('201', eligible: false),
          _record('202', eligible: 'true'),
          _record('203', category: 'CHEESE'),
          _record('   '),
          {'name': 'No UPC', 'category': _milk, 'eligible': true},
          _record('204'),
        ],
      ]);

      final candidates = await AplCandidateProvider(apl).findFor(line: _line());

      expect(candidates.map((c) => c.upc), ['204']);
      expect(candidates.every((c) => c.aplEligible), isTrue);
    });

    test('deduplicates by UPC, keeps first, and caps at max', () async {
      final apl = _ScriptedAplService([
        [
          _record('301', name: 'First'),
          _record('301', name: 'Duplicate'),
          _record('302'),
          _record('303'),
        ],
      ]);
      final provider = AplCandidateProvider(apl);

      final two = await provider.findFor(line: _line(), max: 2);
      final none = await provider.findFor(line: _line(), max: 0);

      expect(two.map((c) => (c.upc, c.name)), [
        ('301', 'First'),
        ('302', 'Candidate milk'),
      ]);
      expect(none, isEmpty);
      expect(apl.calls, hasLength(1));
    });

    test('a blank product name falls back to its UPC', () async {
      final apl = _ScriptedAplService([
        [_record('401', name: '  ')],
      ]);

      final candidates = await AplCandidateProvider(apl).findFor(line: _line());

      expect(candidates.single.name, 'UPC 401');
    });

    test('a catalog error propagates and a retry can recover', () async {
      final apl = _ScriptedAplService([
        [_record('501')],
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        [_record('502')],
      ]);
      final provider = AplCandidateProvider(apl);

      expect((await provider.findFor(line: _line())).single.upc, '501');
      await expectLater(
        provider.findFor(line: _line()),
        throwsA(isA<FirebaseException>()),
      );
      expect((await provider.findFor(line: _line())).single.upc, '502');
    });
  });

  group('AplCandidateProvider with the M2 planner', () {
    const engine = CheckoutPreflightEngine();
    final planner = WolfGuardFixPlanner(engine);

    PreflightRequest request({required int allowed, required int used}) =>
        PreflightRequest(
          lines: [
            _line(
              evidence: const ProductEvidence(
                aplEligible: false,
                canonicalCategory: _milk,
                freshness: EvidenceFreshness.current,
                sourceLabel: 'Imported NC APL',
              ),
            ),
          ],
          benefits: {
            _milk: BenefitCategorySnapshot(
              category: _milk,
              allowed: allowed,
              used: used,
              freshness: EvidenceFreshness.current,
            ),
          },
          evaluatedAt: DateTime.utc(2026, 11, 27),
        );

    Future<FixPlan> plan(PreflightRequest request) async {
      final line = request.lines.single;
      final candidates = await AplCandidateProvider(
        _ScriptedAplService([
          [_record('000777', name: 'Listed milk')],
        ]),
      ).findFor(line: line);
      return planner.propose(
        request: request,
        report: engine.analyze(request),
        candidatesByLine: {line.lineKey: candidates},
      );
    }

    test(
      'an ineligible product gets a replacement with the exact UPC',
      () async {
        final fix = await plan(request(allowed: 2, used: 0));

        final action = fix.actions.single;
        expect(action.kind, FixKind.replaceProduct);
        expect(action.replacement?.upc, '000777');
        expect(fix.before.blockedUnits, 1);
        expect(fix.projectedAfter.coveredUnits, 1);
        expect(fix.projectedAfter.blockedUnits, 0);
      },
    );

    test(
      'an exhausted allowance is never "repaired" by a same-category swap',
      () async {
        final fix = await plan(request(allowed: 1, used: 1));

        expect(
          fix.actions.where((a) => a.kind == FixKind.replaceProduct),
          isEmpty,
        );
      },
    );
  });
}
