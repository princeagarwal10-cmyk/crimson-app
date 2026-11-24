import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final products = [
    ProductDraft(
      id: 'monza-1',
      name: '1400 Handle',
      category: 'Cabinet Handles',
      subcategory: 'Monza',
    ),
    ProductDraft(
      id: 'monza-2',
      name: '1425 Handle',
      category: ' cabinet  handles ',
      subcategory: 'MONZA',
    ),
    ProductDraft(
      id: 'welset-1',
      name: 'W Astha',
      category: 'Cabinet Handles',
      subcategory: 'Welset',
    ),
    ProductDraft(
      id: 'archived',
      name: 'Old Handle',
      category: 'Cabinet Handles',
      subcategory: 'Monza',
      isArchived: true,
    ),
  ];

  test('category selection includes every active product', () {
    expect(
      productIdsForCategory(products, 'CABINET HANDLES'),
      {'monza-1', 'monza-2', 'welset-1'},
    );
  });

  test('subcategory selection is category scoped and normalized', () {
    expect(
      productIdsForSubcategory(
        products,
        category: 'Cabinet Handles',
        subcategory: 'monza',
      ),
      {'monza-1', 'monza-2'},
    );
  });

  test('group toggle selects and then clears only that group', () {
    final selected = toggleSelectionGroup({'outside'}, {'a', 'b'});
    expect(selected, {'outside', 'a', 'b'});
    expect(isSelectionGroupComplete(selected, {'a', 'b'}), isTrue);
    expect(toggleSelectionGroup(selected, {'a', 'b'}), {'outside'});
  });
}
