import 'dart:io';

import 'package:crimson_catalogue_studio/features/catalogue/data/multi_product_export_service.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final products = List.generate(
    5,
    (index) => ProductDraft(
      id: 'product-$index',
      name: 'Handle ${1400 + index}',
      category: 'Cabinet Handles',
      subcategory: 'Monza',
      brand: 'Crimson',
      variations: const [
        VariationDraft(size: '96MM', finish: 'Antique Brass', price: '210'),
        VariationDraft(size: '160MM', finish: 'Antique Brass', price: '260'),
        VariationDraft(size: '224MM', finish: 'Antique Brass', price: '310'),
        VariationDraft(size: '96MM', finish: 'Matte Black', price: '190'),
        VariationDraft(size: '160MM', finish: 'Matte Black', price: '240'),
        VariationDraft(size: '224MM', finish: 'Matte Black', price: '290'),
      ],
    ),
  );

  test('five selected products create two three-row catalogue pages', () {
    final html = const MultiProductExportService().buildHtml(products);
    expect(
        RegExp(r'class="catalogue-page(?: two-up)?"').allMatches(html).length,
        2);
    expect(RegExp('class="card"').allMatches(html).length, 5);
    expect(html, contains('class="rows"'));
    expect(html, contains('<span class="product-name">Handle 1400</span>'));
    expect(html, isNot(contains('Model No. Handle 1400')));
    expect(html, isNot(contains('class="grid"')));
    expect(html, contains('CRIMSON'));
    expect(html, contains('Finish'));
    expect(html, contains('3,1fr'));
    expect(html, contains('grid-template-columns:42% 1fr'));
    expect(html, contains('background:#F8E4EA'));
    expect(html, contains('www.mycrimson.in'));
    expect(html, contains('@crimson.decor'));
    expect(html, contains('+91 89278 78935'));
  });

  test('classic mode remains unchanged for products with multiple images', () {
    final product = products.first.copyWith(
      imagePath: 'https://example.com/black.jpg',
      imagePaths: const [
        'https://example.com/black.jpg',
        'https://example.com/cola.jpg',
        'https://example.com/gold.jpg',
      ],
      imageFinishTags: const {
        'https://example.com/black.jpg': 'BL GREY',
        'https://example.com/cola.jpg': 'COLA CHOCO',
        'https://example.com/gold.jpg': 'GOLD YELLOW',
      },
    );

    final html = const MultiProductExportService().buildHtml([product]);

    expect(html, isNot(contains('class="photo photo-gallery"')));
    expect(html, contains('https://example.com/black.jpg'));
    expect(html, isNot(contains('https://example.com/cola.jpg')));
  });

  test('multi-image mode gives up to four images equal frames', () {
    final product = products.first.copyWith(
      imagePaths: const [
        'https://example.com/black.jpg',
        'https://example.com/cola.jpg',
        'https://example.com/gold.jpg',
        'https://example.com/detail.jpg',
        'https://example.com/installed.jpg',
      ],
      imageFinishTags: const {
        'https://example.com/black.jpg': 'BL GREY',
        'https://example.com/cola.jpg': 'COLA CHOCO',
        'https://example.com/gold.jpg': 'GOLD YELLOW',
      },
    );

    final html = const MultiProductExportService().buildHtml(
      [product],
      imageLayout: CatalogueImageLayout.multiImage,
    );

    expect(html, contains('class="photo photo-gallery count-4"'));
    expect(RegExp('class="photo-tile"').allMatches(html).length, 4);
    expect(html, isNot(contains('photo-main')));
    expect(html, isNot(contains('photo-thumb')));
    expect(html, contains('BL GREY'));
    expect(html, contains('COLA CHOCO'));
    expect(html, contains('GOLD YELLOW'));
    expect(html, contains('class="photo-more">+1</span>'));
    expect(html, contains('grid-template-columns:42% 1fr'));
    expect(html, contains('.photo-gallery.count-2'));
    expect(html, contains('.photo-gallery.count-3'));
    expect(html, contains('.photo-gallery.count-4'));
  });

  test('table CSS constrains cells and keeps dense data readable', () {
    final product = ProductDraft(
      id: 'long-table-product',
      name: 'Long Table Handle',
      category: 'Cabinet Handles',
      subcategory: 'Welset',
      brand: 'Crimson',
      variations: const [
        VariationDraft(
          size: '448MM',
          finish: 'EXTRA LONG METALLIC COLA ROSE GOLD',
          price: '1560',
        ),
      ],
    );

    final html = const MultiProductExportService().buildHtml([product]);

    expect(html, contains('table-layout:fixed'));
    expect(html, contains('.matrix-wide{font-size:12px}'));
    expect(html, contains('overflow-wrap:anywhere'));
    expect(html, contains('font-variant-numeric:tabular-nums'));
    expect(html, contains('EXTRA LONG METALLIC COLA ROSE GOLD'));
  });

  test('wide size matrix shows every size by splitting table blocks', () {
    final product = ProductDraft(
      id: 'wide-product',
      name: '1500 Handle',
      category: 'Cabinet Handles',
      subcategory: 'Monza',
      brand: 'Crimson',
      variations: const [
        VariationDraft(size: '96MM', finish: 'Antik', price: '250'),
        VariationDraft(size: '128MM', finish: 'Antik', price: '335'),
        VariationDraft(size: '160MM', finish: 'Antik', price: '440'),
        VariationDraft(size: '224MM', finish: 'Antik', price: '535'),
        VariationDraft(size: '288MM', finish: 'Antik', price: '735'),
        VariationDraft(size: '96MM', finish: 'Black', price: '250'),
        VariationDraft(size: '128MM', finish: 'Black', price: '335'),
        VariationDraft(size: '160MM', finish: 'Black', price: '440'),
        VariationDraft(size: '224MM', finish: 'Black', price: '535'),
        VariationDraft(size: '288MM', finish: 'Black', price: '735'),
      ],
    );

    final html = const MultiProductExportService().buildHtml([product]);

    expect(html, contains('96MM'));
    expect(html, contains('128MM'));
    expect(html, contains('160MM'));
    expect(html, contains('224MM'));
    expect(html, contains('288MM'));
    expect(html, isNot(contains('Complete matrix')));
  });

  test('seven size matrix stays in one wide table and avoids duplicate title',
      () {
    final product = ProductDraft(
      id: 'seven-size-product',
      name: '1500 Handle',
      category: 'Cabinet Handles',
      subcategory: 'Monza',
      brand: 'Crimson',
      variations: const [
        VariationDraft(size: '96MM', finish: 'Antik', price: '240'),
        VariationDraft(size: '128MM', finish: 'Antik', price: '335'),
        VariationDraft(size: '160MM', finish: 'Antik', price: '440'),
        VariationDraft(size: '224MM', finish: 'Antik', price: '535'),
        VariationDraft(size: '288MM', finish: 'Antik', price: '735'),
        VariationDraft(size: '448MM', finish: 'Antik', price: '900'),
        VariationDraft(size: '600MM', finish: 'Antik', price: '1100'),
      ],
    );

    final html = const MultiProductExportService().buildHtml([product]);

    expect(html, contains('<span class="product-name">1500 Handle</span>'));
    expect(html, isNot(contains('Model No.')));
    expect(RegExp(r'<table class="matrix[^"]*matrix-wide').allMatches(html),
        hasLength(1));
    expect(RegExp(r'<table class=').allMatches(html), hasLength(1));
    expect(html, contains('600MM'));
  });

  test('image export groups three products on the first page', () async {
    final imageProducts = [...products];
    imageProducts[0] = products.first.copyWith(
      imagePaths: const [
        'missing-black.png',
        'missing-cola.png',
        'missing-gold.png',
        'missing-detail.png',
        'missing-installed.png',
      ],
      imageFinishTags: const {
        'missing-black.png': 'BL GREY',
        'missing-cola.png': 'COLA CHOCO',
        'missing-gold.png': 'GOLD YELLOW',
      },
    );
    final directory =
        await Directory.systemTemp.createTemp('crimson_multi_export_test_');
    addTearDown(() => directory.delete(recursive: true));
    final paths = await const MultiProductExportService().exportImages(
      products: imageProducts,
      path: '${directory.path}/catalogue.png',
      imageLayout: CatalogueImageLayout.multiImage,
    );
    expect(paths, hasLength(2));
    for (final path in paths) {
      final file = File(path);
      expect(await file.exists(), isTrue);
      expect(await file.length(), greaterThan(1000));
    }
  });

  test('Windows PDF export creates a non-empty PDF', () async {
    if (!Platform.isWindows) return;
    final directory =
        await Directory.systemTemp.createTemp('crimson_pdf_export_test_');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}catalogue.pdf';

    await const MultiProductExportService().exportPdf(
      products: [products.first],
      path: path,
    );

    final file = File(path);
    expect(await file.exists(), isTrue);
    expect(await file.length(), greaterThan(1000));
  });
}
