import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wolfbite/services/apl_service.dart';

/// M3 (Feiyang): the read-only APL query behind WolfGuard replacements.
void main() {
  late FakeFirebaseFirestore db;
  late AplService apl;

  Future<void> put(String upc, Map<String, dynamic> data) =>
      db.collection('apl').doc(upc).set(data);

  setUp(() {
    db = FakeFirebaseFirestore();
    apl = AplService(db: db, useNutritionCollection: false);
  });

  test('returns document-ID UPCs exactly, including leading zeros', () async {
    await put('000743266', {
      'name': 'Whole milk gallon',
      'category': 'MILK - WHOLE',
      'categoryCode': '51',
      'eligible': true,
    });

    final results = await apl.eligibleReplacements('MILK - WHOLE');

    expect(results, hasLength(1));
    expect(results.single['upc'], '000743266');
    expect(results.single['category'], 'MILK - WHOLE');
    expect(results.single['sourceCategory'], 'MILK - WHOLE');
  });

  test(
    'finds spelling variants through the consistent category code',
    () async {
      await put('100', {
        'name': 'Variant label milk',
        'category': 'MILK-WHOLE',
        'categoryCode': '51',
        'eligible': true,
      });
      await put('101', {
        'name': 'Reduced fat milk',
        'category': 'MILK - FAT REDUCED',
        'categoryCode': '52',
        'eligible': true,
      });

      final results = await apl.eligibleReplacements('milk-whole');

      expect(results.map((r) => r['upc']), ['100']);
      expect(results.single['category'], 'MILK - WHOLE');
      expect(results.single['sourceCategory'], 'MILK-WHOLE');
    },
  );

  test('excludes records that are not Boolean-true eligible', () async {
    await put('200', {
      'name': 'Listed',
      'category': 'CHEESE',
      'eligible': true,
    });
    await put('201', {
      'name': 'Delisted',
      'category': 'CHEESE',
      'eligible': false,
    });
    await put('202', {
      'name': 'Text flag',
      'category': 'CHEESE',
      'eligible': 'true',
    });
    await put('203', {'name': 'No flag', 'category': 'CHEESE'});

    final results = await apl.eligibleReplacements('CHEESE');

    expect(results.map((r) => r['upc']), ['200']);
  });

  test(
    'rejects a label match whose category code means another category',
    () async {
      await put('300', {
        'name': 'Mislabelled yogurt',
        'category': 'CHEESE',
        'categoryCode': '50',
        'eligible': true,
      });
      await put('301', {
        'name': 'Real cheese',
        'category': 'CHEESE',
        'categoryCode': '02',
        'eligible': true,
      });

      final results = await apl.eligibleReplacements('CHEESE');

      expect(results.map((r) => r['upc']), ['301']);
    },
  );

  test('excludes the current UPC and removes duplicate UPCs', () async {
    // Matches both the code query and the label query.
    await put('400', {
      'name': 'Current cereal',
      'category': 'BREAKFAST CEREAL',
      'categoryCode': '05',
      'eligible': true,
    });
    await put('401', {
      'name': 'Other cereal',
      'category': 'BREAKFAST CEREAL',
      'categoryCode': '05',
      'eligible': true,
    });

    final results = await apl.eligibleReplacements(
      'BREAKFAST CEREAL',
      excludeUpc: '400',
    );

    expect(results.map((r) => r['upc']), ['401']);
  });

  test('skips a record whose stored UPC contradicts its document ID', () async {
    await put('500', {
      'upc': '999',
      'name': 'Contradictory eggs',
      'category': 'EGGS',
      'eligible': true,
    });
    await put('501', {
      'upc': '501',
      'name': 'Consistent eggs',
      'category': 'EGGS',
      'eligible': true,
    });

    final results = await apl.eligibleReplacements('EGGS');

    expect(results.map((r) => r['upc']), ['501']);
  });

  test(
    'caps results at max and returns nothing for blank or nonpositive input',
    () async {
      for (var i = 0; i < 8; i++) {
        await put('60$i', {
          'name': 'Bread $i',
          'category': 'WW BREAD OR WHOLE GRAINS',
          'eligible': true,
        });
      }

      expect(
        await apl.eligibleReplacements('WW BREAD OR WHOLE GRAINS', max: 3),
        hasLength(3),
      );
      expect(
        await apl.eligibleReplacements('WW BREAD OR WHOLE GRAINS', max: 0),
        isEmpty,
      );
      expect(await apl.eligibleReplacements('   '), isEmpty);
    },
  );

  test(
    'keeps the accounting unit as stored and invents no package size',
    () async {
      await put('700', {
        'name': 'Juice 64 OZ',
        'category': 'JUICE 64',
        'categoryCode': '54',
        'unitOfMeasure': 'OZ',
        'eligible': true,
      });

      final result = (await apl.eligibleReplacements('JUICE 64')).single;

      expect(result['unitOfMeasure'], 'OZ');
      expect(result.containsKey('packageSize'), isFalse);
      expect(result.containsKey('verifiedPackageSize'), isFalse);
    },
  );

  test('is read-only: the catalog is unchanged after a search', () async {
    await put('800', {
      'name': 'Beans',
      'category': 'LEGUMES',
      'eligible': true,
    });
    final before = db.dump();

    await apl.eligibleReplacements('LEGUMES', excludeUpc: '000');

    expect(db.dump(), before);
  });
}
