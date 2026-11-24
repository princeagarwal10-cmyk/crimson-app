import 'package:flutter_test/flutter_test.dart';

import 'package:crimson_catalogue_studio/features/catalogue/presentation/manual_price_matrix.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';

void main() {
  test('manual matrix omits unavailable finish and size combinations', () {
    const prices = <String, String>{
      'Black\u001f96MM': '300',
      'Black\u001f160MM': '495',
      'Black\u001f224MM': '',
      'Black\u001f288MM': '0',
      'Rose Gold\u001f96MM': '-',
      'Rose Gold\u001f160MM': '520',
      'Rose Gold\u001f224MM': '740',
      'Rose Gold\u001f288MM': '0.00',
    };

    final variations = buildManualPriceMatrixVariations(
      finishes: const ['Black', 'Rose Gold'],
      sizes: const ['96MM', '160MM', '224MM', '288MM'],
      priceFor: (finish, size) => prices['$finish\u001f$size'] ?? '',
    );

    expect(variations, hasLength(4));
    expect(
      variations.map((item) => '${item.finish}/${item.size}/${item.price}'),
      [
        'Black/96MM/300.00',
        'Black/160MM/495.00',
        'Rose Gold/160MM/520.00',
        'Rose Gold/224MM/740.00',
      ],
    );
  });

  test('manual matrix returns no variations when every cell is unavailable',
      () {
    final variations = buildManualPriceMatrixVariations(
      finishes: const ['Black'],
      sizes: const ['96MM', '160MM', '224MM'],
      priceFor: (_, size) => switch (size) {
        '96MM' => '',
        '160MM' => '0',
        _ => '-',
      },
    );

    expect(variations, isEmpty);
  });

  test('manual matrix still rejects non-numeric prices', () {
    expect(
      () => buildManualPriceMatrixVariations(
        finishes: const ['Black'],
        sizes: const ['96MM'],
        priceFor: (_, __) => 'not a price',
      ),
      throwsFormatException,
    );
  });

  test('editing photos and another field keeps existing zero-priced rows', () {
    const existing = [
      VariationDraft(
        finish: 'GOLD / ANTIK',
        size: 'CY',
        price: '0.00',
        sku: 'CY-GA',
        notes: 'Original imported variation',
      ),
      VariationDraft(finish: 'BLACK', size: 'CY', price: '0.00'),
    ];

    final result = buildManualPriceMatrixVariations(
      finishes: const ['GOLD / ANTIK', 'BLACK'],
      sizes: const ['CY'],
      priceFor: (_, __) => '0',
      existingVariations: existing,
    );

    expect(result, hasLength(2));
    expect(result.first.price, '0.00');
    expect(result.first.sku, 'CY-GA');
    expect(result.first.notes, 'Original imported variation');
  });

  test('blanking a price still removes that combination', () {
    const existing = [
      VariationDraft(finish: 'BLACK', size: 'CY', price: '250.00'),
      VariationDraft(finish: 'GOLD', size: 'CY', price: '0.00'),
    ];
    final result = buildManualPriceMatrixVariations(
      finishes: const ['BLACK', 'GOLD'],
      sizes: const ['CY'],
      priceFor: (finish, _) => finish == 'BLACK' ? '' : '0',
      existingVariations: existing,
    );
    expect(result.map((item) => item.finish), ['GOLD']);
  });
}
