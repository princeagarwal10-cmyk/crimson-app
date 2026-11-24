import 'dart:io';

import 'package:crimson_catalogue_studio/features/catalogue/data/multi_product_export_service.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('generate visual multi-product catalogue preview',
      (tester) async {
    const workspace = r'C:\Users\Lenovo\Documents\product catalogue';
    final imageDirectory = '$workspace${Platform.pathSeparator}images';
    final output = Directory(
      '$workspace${Platform.pathSeparator}crimson flutter version 1.0${Platform.pathSeparator}output${Platform.pathSeparator}catalogue-preview',
    );
    await output.create(recursive: true);
    const variations = [
      VariationDraft(size: '96MM', finish: 'Antique Brass', price: '210'),
      VariationDraft(size: '160MM', finish: 'Antique Brass', price: '260'),
      VariationDraft(size: '224MM', finish: 'Antique Brass', price: '310'),
      VariationDraft(size: '96MM', finish: 'Brushed Gold', price: '220'),
      VariationDraft(size: '160MM', finish: 'Brushed Gold', price: '270'),
      VariationDraft(size: '224MM', finish: 'Brushed Gold', price: '320'),
      VariationDraft(size: '96MM', finish: 'Matte Black', price: '190'),
      VariationDraft(size: '160MM', finish: 'Matte Black', price: '240'),
      VariationDraft(size: '224MM', finish: 'Matte Black', price: '290'),
    ];
    final products = [
      ProductDraft(
        name: '1400 Handle',
        category: 'Cabinet Handles',
        subcategory: 'Monza',
        brand: 'Crimson',
        imagePath: '$imageDirectory${Platform.pathSeparator}1400_59586b82.png',
        variations: variations,
      ),
      ProductDraft(
        name: '1425 Handle',
        category: 'Cabinet Handles',
        subcategory: 'Monza',
        brand: 'Crimson',
        imagePath:
            '$imageDirectory${Platform.pathSeparator}1425 rg + wengi _23cf8280.png',
        variations: variations,
      ),
      ProductDraft(
        name: '1500 Handle',
        category: 'Cabinet Handles',
        subcategory: 'Monza',
        brand: 'Crimson',
        imagePath: '$imageDirectory${Platform.pathSeparator}1500_35ce6c95.png',
        variations: variations,
      ),
      ProductDraft(
        name: '1508 Handle',
        category: 'Cabinet Handles',
        subcategory: 'Monza',
        brand: 'Crimson',
        imagePath:
            '$imageDirectory${Platform.pathSeparator}1508 gold_6d6e93ee.png',
        variations: variations,
      ),
      ProductDraft(
        name: '1545 Handle',
        category: 'Cabinet Handles',
        subcategory: 'Monza',
        brand: 'Crimson',
        imagePath:
            '$imageDirectory${Platform.pathSeparator}1545 Rembo + bk_c638f2e1.png',
        variations: variations,
      ),
    ];
    const service = MultiProductExportService();
    await tester.runAsync(() => service.exportImages(
          products: products,
          path:
              '${output.path}${Platform.pathSeparator}Crimson-Multi-Product.png',
        ));
    await tester.runAsync(() => service.exportPdf(
          products: products,
          path:
              '${output.path}${Platform.pathSeparator}Crimson-Multi-Product.pdf',
        ));
  });
}
