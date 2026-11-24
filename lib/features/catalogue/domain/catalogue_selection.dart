import 'catalogue_models.dart';

Set<String> productIdsForCategory(
  Iterable<ProductDraft> products,
  String category,
) {
  final target = _normal(category);
  return {
    for (final product in products)
      if (!product.isArchived && _normal(product.category) == target)
        product.id,
  };
}

Set<String> productIdsForSubcategory(
  Iterable<ProductDraft> products, {
  required String category,
  required String subcategory,
}) {
  final categoryKey = _normal(category);
  final subcategoryKey = _normal(subcategory);
  return {
    for (final product in products)
      if (!product.isArchived &&
          _normal(product.category) == categoryKey &&
          _normal(product.subcategory) == subcategoryKey)
        product.id,
  };
}

Set<String> toggleProductSelection(Set<String> selected, String productId) {
  final next = {...selected};
  if (!next.remove(productId)) {
    next.add(productId);
  }
  return next;
}

Set<String> toggleSelectionGroup(
  Set<String> selected,
  Iterable<String> productIds,
) {
  final group = productIds.where((id) => id.trim().isNotEmpty).toSet();
  if (group.isEmpty) return {...selected};

  final next = {...selected};
  if (group.every(next.contains)) {
    next.removeAll(group);
  } else {
    next.addAll(group);
  }
  return next;
}

bool isSelectionGroupComplete(
  Set<String> selected,
  Iterable<String> productIds,
) {
  final group = productIds.where((id) => id.trim().isNotEmpty).toSet();
  return group.isNotEmpty && group.every(selected.contains);
}

String _normal(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
