import 'catalogue_models.dart';

class CatalogueHealthReport {
  const CatalogueHealthReport({
    required this.duplicateNames,
    required this.missingCategories,
    required this.missingSubcategories,
    required this.productsWithoutVariations,
    required this.productsWithoutImages,
    required this.productsWithMissingImageFiles,
    required this.productsWithZeroPriceVariations,
  });

  final List<String> duplicateNames;
  final List<String> missingCategories;
  final List<String> missingSubcategories;
  final List<String> productsWithoutVariations;
  final List<String> productsWithoutImages;
  final List<String> productsWithMissingImageFiles;
  final List<String> productsWithZeroPriceVariations;

  int get attentionCount =>
      duplicateNames.length +
      missingCategories.length +
      missingSubcategories.length +
      productsWithoutVariations.length +
      productsWithoutImages.length +
      productsWithMissingImageFiles.length +
      productsWithZeroPriceVariations.length;
}

CatalogueHealthReport inspectCatalogueHealth(
  List<ProductDraft> products, {
  bool Function(String path)? imageExists,
}) {
  final active = products.where((product) => !product.isArchived).toList();
  final names = <String, List<String>>{};
  for (final product in active) {
    final key = _normal(product.name);
    if (key.isNotEmpty) names.putIfAbsent(key, () => []).add(product.name);
  }

  List<String> matching(bool Function(ProductDraft product) test) =>
      active.where(test).map((product) => product.name).toSet().toList();

  final duplicates = <String>[
    for (final entry in names.entries)
      if (entry.value.length > 1) entry.value.first,
  ];

  return CatalogueHealthReport(
    duplicateNames: duplicates,
    missingCategories: matching((product) => product.category.trim().isEmpty),
    missingSubcategories:
        matching((product) => product.subcategory.trim().isEmpty),
    productsWithoutVariations:
        matching((product) => product.variations.isEmpty),
    productsWithoutImages: matching((product) => _paths(product).isEmpty),
    productsWithMissingImageFiles: imageExists == null
        ? const []
        : matching(
            (product) => _paths(product).any((path) => !imageExists(path)),
          ),
    productsWithZeroPriceVariations: matching(
      (product) => product.variations.any(
        (variation) => (double.tryParse(variation.price.trim()) ?? 0) <= 0,
      ),
    ),
  );
}

List<String> _paths(ProductDraft product) {
  return <String>{
    if (product.imagePath.trim().isNotEmpty) product.imagePath.trim(),
    for (final path in product.imagePaths)
      if (path.trim().isNotEmpty) path.trim(),
  }.toList();
}

String _normal(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
