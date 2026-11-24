import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('product image colour tags', () {
    test('legacy product JSON loads without changing existing data', () {
      final product = ProductDraft.fromJson({
        'id': 'legacy-1',
        'name': 'Legacy Chair',
        'sku': 'CHAIR-01',
        'category': 'Furniture',
        'subcategory': 'Chairs',
        'imagePath': 'black.jpg',
        'imagePaths': ['black.jpg', 'gold.jpg'],
        'sellingPrice': '1250.00',
        'isPublished': true,
      });

      expect(product.id, 'legacy-1');
      expect(product.name, 'Legacy Chair');
      expect(product.imagePaths, ['black.jpg', 'gold.jpg']);
      expect(product.imageFinishTags, isEmpty);
      expect(product.toJson()['sellingPrice'], '1250.00');
      expect(product.toJson()['isPublished'], isTrue);
    });

    test('image colour tags survive JSON and copyWith round trips', () {
      final product = ProductDraft(
        id: 'tagged-1',
        name: 'Tagged Chair',
        category: 'Furniture',
        subcategory: 'Chairs',
        imagePath: 'black.jpg',
        imagePaths: const ['black.jpg', 'gold.jpg', 'detail.jpg'],
        imageFinishTags: const {
          'black.jpg': 'Black',
          'gold.jpg': 'Gold',
        },
      );

      final restored = ProductDraft.fromJson(product.toJson());
      final copied = restored.copyWith(notes: 'Keep all image tags');

      expect(restored.imageFinishTags, {
        'black.jpg': 'Black',
        'gold.jpg': 'Gold',
      });
      expect(copied.imageFinishTags, restored.imageFinishTags);
      expect(copied.imagePaths, product.imagePaths);
      expect(copied.notes, 'Keep all image tags');
    });

    test('snake case cloud payload remains compatible', () {
      final product = ProductDraft.fromJson({
        'name': 'Cloud Product',
        'category': 'Decor',
        'subcategory': 'Vases',
        'image_finish_tags': {'blue.jpg': 'Blue'},
      });

      expect(product.imageFinishTags, {'blue.jpg': 'Blue'});
    });
  });
}
