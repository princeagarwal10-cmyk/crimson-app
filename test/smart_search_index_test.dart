import 'package:crimson_catalogue_studio/core/rules/catalogue_rules.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final roseGold = ProductDraft(
    id: 'rose-gold-product',
    name: 'W Astha',
    category: 'Cabinet Handles',
    subcategory: 'Welset',
    brand: 'Crimson',
    finishColor: 'Rose Gold',
    keywords: const ['premium handle'],
    variations: const [
      VariationDraft(size: '102MM', finish: 'Rose Gold', price: '495'),
    ],
  );
  final goldYellow = ProductDraft(
    id: 'gold-yellow-product',
    name: 'W Clavis',
    category: 'Cabinet Handles',
    subcategory: 'Welset',
    brand: 'Crimson',
    finishColor: 'Gold Yellow',
    variations: const [
      VariationDraft(size: '96MM', finish: 'Gold Yellow', price: '470'),
    ],
  );
  final products = [roseGold, goldYellow];

  test('search responds to unfinished letters', () {
    for (final query in ['r', 'ro', 'ros', 'rose']) {
      final matches = filterCatalogueProducts(
        products,
        CatalogueProductFilter(query: query),
      );
      expect(matches.map((product) => product.id), contains(roseGold.id));
    }
    final nameMatches = filterCatalogueProducts(
      products,
      const CatalogueProductFilter(query: 'ast'),
    );
    expect(nameMatches.single.id, roseGold.id);
  });

  test('rose gold abbreviations are equivalent without matching gold yellow',
      () {
    for (final query in ['RG', 'R/G', 'rosegold', 'rose gold', 'rose-gold']) {
      final matches = filterCatalogueProducts(
        products,
        CatalogueProductFilter(query: query),
      );
      expect(matches.map((product) => product.id), [roseGold.id]);
    }
  });

  test('custom business terminology is searchable immediately', () {
    const terminology = [
      SearchTerminologyDraft(
        canonical: 'Brushed Antique',
        aliases: ['BA', 'B/A', 'Antique Brush'],
      ),
    ];
    final customProduct = ProductDraft(
      id: 'custom-finish',
      name: 'W Custom',
      category: 'Cabinet Handles',
      subcategory: 'Welset',
      finishColor: 'Brushed Antique',
    );
    for (final query in ['BA', 'B/A', 'antique brush', 'brus']) {
      final matches = filterCatalogueProducts(
        [customProduct],
        CatalogueProductFilter(query: query),
        terminology: terminology,
      );
      expect(matches.single.id, customProduct.id);
    }
  });

  test('equivalent measurements use the indexed size token', () {
    final matches = filterCatalogueProducts(
      products,
      const CatalogueProductFilter(query: '4 inch'),
    );
    expect(matches.map((product) => product.id), contains(roseGold.id));
  });

  test('terminology survives catalogue serialization', () {
    const entry = SearchTerminologyDraft(
      canonical: 'Rose Gold',
      aliases: ['RG', 'R/G'],
    );
    final state = CatalogueState(
      products: products,
      searchTerminology: const [entry],
    );
    final restored = CatalogueState.fromJson(state.toJson());
    expect(restored.searchTerminology.single.canonical, 'Rose Gold');
    expect(restored.searchTerminology.single.aliases, ['RG', 'R/G']);
  });

  test('repeated prefix searches reuse the catalogue index', () {
    final largeCatalogue = List<ProductDraft>.generate(
      2500,
      (index) => ProductDraft(
        id: 'indexed-$index',
        name: 'Handle $index',
        category: 'Cabinet Handles',
        subcategory: 'Welset',
        finishColor: index.isEven ? 'Rose Gold' : 'Matt Black',
      ),
      growable: false,
    );
    final stopwatch = Stopwatch()..start();
    for (final query in ['r', 'ro', 'ros', 'rose', 'RG']) {
      final matches = filterCatalogueProducts(
        largeCatalogue,
        CatalogueProductFilter(query: query),
      );
      expect(matches.length, 1250);
    }
    stopwatch.stop();
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
  });
}
