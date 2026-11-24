import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../domain/catalogue_models.dart';
import 'sample_catalogue_data.dart';

class LocalCatalogueRepository {
  LocalCatalogueRepository({File? storeFile})
      : _storeFile = storeFile ?? _defaultStoreFile();

  final File _storeFile;

  String get storePath => _storeFile.path;

  Future<CatalogueState> load() async {
    if (!await _storeFile.exists()) {
      await save(sampleCatalogueState);
      return sampleCatalogueState;
    }

    final raw = await _storeFile.readAsString();
    if (raw.trim().isEmpty) {
      await save(sampleCatalogueState);
      return sampleCatalogueState;
    }

    final decoded = raw.length >= 262144
        ? await Isolate.run<Object?>(() => jsonDecode(raw))
        : jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Catalogue data file is not valid.');
    }

    final hadDuplicateIds = _hasDuplicateProductIds(decoded);
    final state = CatalogueState.fromJson(Map<String, Object?>.from(decoded));
    if (hadDuplicateIds) {
      await _writeState(state);
    }
    return state;
  }

  Future<void> save(CatalogueState state) async {
    await _storeFile.parent.create(recursive: true);
    final next = state.copyWith(
      products: ensureProductIdentity(state.products),
      updatedAt: DateTime.now().toIso8601String(),
    );
    await _writeState(next);
  }

  Future<void> _writeState(CatalogueState state) async {
    await _storeFile.parent.create(recursive: true);
    await _storeFile.writeAsString(jsonEncode(state.toJson()));
  }

  Future<CatalogueState> upsertProduct(
    ProductDraft product, {
    bool updateExistingName = true,
  }) async {
    final state = await load();
    final products = [...state.products];
    final incomingName = _normal(product.name);
    final incomingSku = _normal(product.sku);
    final incomingInternalCode =
        normalizeInternalProductCode(product.internalProductCode);

    final sameIdIndex =
        products.indexWhere((existing) => existing.id == product.id);
    final sameInternalCodeIndex = incomingInternalCode.isEmpty
        ? -1
        : products.indexWhere((existing) =>
            normalizeInternalProductCode(existing.internalProductCode) ==
            incomingInternalCode);
    final sameSkuIndex = incomingSku.isEmpty
        ? -1
        : products
            .indexWhere((existing) => _normal(existing.sku) == incomingSku);
    final sameNameIndex = products
        .indexWhere((existing) => _normal(existing.name) == incomingName);
    final replaceIndex = sameIdIndex >= 0
        ? sameIdIndex
        : sameInternalCodeIndex >= 0
            ? sameInternalCodeIndex
            : sameSkuIndex >= 0
                ? sameSkuIndex
                : updateExistingName
                    ? sameNameIndex
                    : -1;

    if (replaceIndex >= 0) {
      final existing = products[replaceIndex];
      products[replaceIndex] = sameIdIndex >= 0
          ? _replaceEditedProduct(
              existing: existing,
              incoming: product,
            )
          : _mergeImportedProduct(
              existing: existing,
              incoming: product,
            );
    } else {
      products.add(product);
    }

    final nextState = state.copyWith(
      products: products,
      brands: _mergeTextValue(state.brands, product.brand),
    );
    await save(nextState);
    return nextState;
  }

  Future<CatalogueState> importProducts({
    required List<ProductDraft> incomingProducts,
    required List<CategoryDraft> incomingCategories,
  }) async {
    final state = await load();
    final products = [...state.products];
    var categories = [...state.categories];
    var brands = [...state.brands];

    for (final category in incomingCategories) {
      categories = _mergeCategory(categories, category);
    }

    for (final product in incomingProducts) {
      final incomingInternalCode =
          normalizeInternalProductCode(product.internalProductCode);
      final sameInternalCodeIndex = incomingInternalCode.isEmpty
          ? -1
          : products.indexWhere((existing) =>
              normalizeInternalProductCode(existing.internalProductCode) ==
              incomingInternalCode);
      if (sameInternalCodeIndex >= 0) {
        products[sameInternalCodeIndex] = _mergeImportedProduct(
          existing: products[sameInternalCodeIndex],
          incoming: product,
        );
      } else {
        final sameNameIndexes = incomingInternalCode.isEmpty
            ? _matchingProductNameIndexes(products, product.name)
            : const <int>[];
        if (sameNameIndexes.isEmpty) {
          products.add(product);
        } else {
          final primaryIndex = sameNameIndexes.first;
          final existingMatches =
              sameNameIndexes.map((index) => products[index]).toList();
          products[primaryIndex] = _mergeImportedProductGroup(
            existingProducts: existingMatches,
            incoming: product,
          );
          for (final duplicateIndex
              in sameNameIndexes.skip(1).toList().reversed) {
            products.removeAt(duplicateIndex);
          }
        }
      }
      categories = _mergeCategory(
        categories,
        CategoryDraft(
            name: product.category, subcategories: [product.subcategory]),
      );
      brands = _mergeTextValue(brands, product.brand);
    }

    final nextState = state.copyWith(
        products: products, categories: categories, brands: brands);
    await save(nextState);
    return nextState;
  }

  Future<List<String>> previewDuplicateNameWarnings(
    List<ProductDraft> incomingProducts,
  ) async {
    final state = await load();
    final warnings = <String>[];
    for (final product in incomingProducts) {
      if (normalizeInternalProductCode(product.internalProductCode)
          .isNotEmpty) {
        continue;
      }
      final incomingName = _normal(product.name);
      if (incomingName.isEmpty) continue;
      final matches = state.products
          .where((existing) => _normal(existing.name) == incomingName)
          .toList();
      if (matches.isEmpty) continue;
      final codes = matches
          .map((existing) =>
              normalizeInternalProductCode(existing.internalProductCode))
          .where((code) => code.isNotEmpty)
          .join(', ');
      warnings.add(matches.length > 1
          ? 'Will merge ${matches.length} existing products named ${product.name} into one product and update it from this paste.'
          : codes.isEmpty
              ? 'Will update existing product by name: ${product.name}.'
              : 'Will update existing product by name: ${product.name} ($codes).');
    }
    return warnings;
  }

  List<int> _matchingProductNameIndexes(
    List<ProductDraft> products,
    String name,
  ) {
    final incomingName = _normal(name);
    if (incomingName.isEmpty) return const [];
    final indexes = <int>[];
    for (var index = 0; index < products.length; index += 1) {
      if (_normal(products[index].name) == incomingName) {
        indexes.add(index);
      }
    }
    return indexes;
  }

  ProductDraft _mergeImportedProductGroup({
    required List<ProductDraft> existingProducts,
    required ProductDraft incoming,
  }) {
    final primary = existingProducts.first;
    var merged = _mergeImportedProduct(existing: primary, incoming: incoming);
    final incomingHasImages =
        incoming.imagePath.trim().isNotEmpty || incoming.imagePaths.isNotEmpty;
    if (incomingHasImages) return merged;

    final imagePaths = <String>[];
    final imageFinishTags = <String, String>{};
    var imageRevision = merged.imageRevision;
    for (final product in existingProducts) {
      final mainImage = product.imagePath.trim();
      if (mainImage.isNotEmpty &&
          !imagePaths.any((path) => _normal(path) == _normal(mainImage))) {
        imagePaths.add(mainImage);
      }
      for (final imagePath in product.imagePaths) {
        final clean = imagePath.trim();
        if (clean.isEmpty) continue;
        if (!imagePaths.any((path) => _normal(path) == _normal(clean))) {
          imagePaths.add(clean);
        }
      }
      for (final entry in product.imageFinishTags.entries) {
        final path = entry.key.trim();
        final finish = entry.value.trim();
        if (path.isNotEmpty && finish.isNotEmpty) {
          imageFinishTags.putIfAbsent(path, () => finish);
        }
      }
      if (product.imageRevision > imageRevision) {
        imageRevision = product.imageRevision;
      }
    }

    if (imagePaths.isEmpty) return merged;
    merged = merged.copyWith(
      imagePath: imagePaths.first,
      imagePaths: imagePaths,
      imageFinishTags: imageFinishTags,
      imageRevision: imageRevision,
    );
    return merged;
  }

  ProductDraft _mergeImportedProduct({
    required ProductDraft existing,
    required ProductDraft incoming,
  }) {
    final nextCode =
        normalizeInternalProductCode(incoming.internalProductCode).isNotEmpty
            ? incoming.internalProductCode
            : existing.internalProductCode;
    final preserveImagePath = incoming.imagePath.trim().isEmpty;
    final preserveImagePaths = incoming.imagePaths.isEmpty;
    final preserveImages = preserveImagePath && preserveImagePaths;
    final incomingNotes = incoming.notes.trim();
    return incoming.copyWith(
      id: existing.id,
      sku: incoming.sku.trim().isEmpty ? existing.sku : incoming.sku,
      internalProductCode: nextCode,
      imagePath: preserveImagePath ? existing.imagePath : incoming.imagePath,
      imagePaths:
          preserveImagePaths ? existing.imagePaths : incoming.imagePaths,
      imageFinishTags:
          preserveImages ? existing.imageFinishTags : incoming.imageFinishTags,
      imageRevision:
          preserveImages ? existing.imageRevision : incoming.imageRevision,
      notes: incomingNotes == 'Imported from bulk paste.' &&
              existing.notes.trim().isNotEmpty
          ? existing.notes
          : incoming.notes,
      keywords: _unique([
        ...existing.keywords,
        ...incoming.keywords,
      ]),
      isPublished: existing.isPublished,
      isComingSoon: existing.isComingSoon,
      isArchived: existing.isArchived,
      archivedAt: existing.archivedAt,
    );
  }

  ProductDraft _replaceEditedProduct({
    required ProductDraft existing,
    required ProductDraft incoming,
  }) {
    final nextCode =
        normalizeInternalProductCode(incoming.internalProductCode).isNotEmpty
            ? incoming.internalProductCode
            : existing.internalProductCode;
    return incoming.copyWith(
      id: existing.id,
      internalProductCode: nextCode,
      isArchived: existing.isArchived,
      archivedAt: existing.archivedAt,
    );
  }

  Future<CatalogueState> archiveProduct(String productId) async {
    return _setProductArchived(
      productId: productId,
      isArchived: true,
      archivedAt: DateTime.now().toIso8601String(),
    );
  }

  Future<CatalogueState> restoreProduct(String productId) async {
    return _setProductArchived(
      productId: productId,
      isArchived: false,
      archivedAt: '',
    );
  }

  Future<CatalogueState> _setProductArchived({
    required String productId,
    required bool isArchived,
    required String archivedAt,
  }) async {
    final state = await load();
    final products = [...state.products];
    final index = products.indexWhere((product) => product.id == productId);
    if (index < 0) return state;

    products[index] = products[index].copyWith(
      isArchived: isArchived,
      archivedAt: archivedAt,
    );
    final nextState = state.copyWith(products: products);
    await save(nextState);
    return nextState;
  }

  static File _defaultStoreFile() {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.trim().isNotEmpty) {
      return File('$appData\\Crimson Catalogue Studio\\catalogue_store.json');
    }
    return File('data/catalogue_store.json');
  }

  static String _normal(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool _hasDuplicateProductIds(Map<dynamic, dynamic> json) {
    final seen = <String>{};
    final products = json['products'];
    if (products is! List) return false;
    for (final value in products) {
      if (value is! Map) continue;
      final id = (value['id'] ?? '').toString().trim();
      if (id.isEmpty || !seen.add(id)) return true;
    }
    return false;
  }

  static List<CategoryDraft> _mergeCategory(
    List<CategoryDraft> categories,
    CategoryDraft incoming,
  ) {
    final name = incoming.name.trim();
    if (name.isEmpty) return categories;
    final index =
        categories.indexWhere((item) => _normal(item.name) == _normal(name));
    if (index < 0) {
      final subcategories = _unique(incoming.subcategories);
      return [
        ...categories,
        incoming.copyWith(
          name: name,
          subcategories: subcategories,
          subcategoryPublished: {
            for (final subcategory in subcategories)
              subcategory: incoming.isSubcategoryPublished(subcategory),
          },
        ),
      ];
    }

    final existing = categories[index];
    final subcategories = [...existing.subcategories];
    final subcategoryPublished = Map<String, bool>.from(
      existing.subcategoryPublished,
    );
    for (final subcategory in incoming.subcategories) {
      final clean = subcategory.trim();
      if (clean.isEmpty) continue;
      if (!subcategories.any((item) => _normal(item) == _normal(clean))) {
        subcategories.add(clean);
        subcategoryPublished[clean] = incoming.isSubcategoryPublished(clean);
      }
    }
    final next = [...categories];
    next[index] = existing.copyWith(
      subcategories: subcategories,
      subcategoryPublished: subcategoryPublished,
      keywords: _unique([
        ...existing.keywords,
        ...incoming.keywords,
      ]),
    );
    return next;
  }

  static List<String> _unique(List<String> values) {
    final result = <String>[];
    for (final value in values) {
      final clean = value.trim();
      if (clean.isEmpty) continue;
      if (!result.any((item) => _normal(item) == _normal(clean))) {
        result.add(clean);
      }
    }
    return result;
  }

  static List<String> _mergeTextValue(List<String> values, String incoming) {
    final clean = incoming.trim();
    if (clean.isEmpty) return values;
    if (values.any((value) => _normal(value) == _normal(clean))) {
      return values;
    }
    return [...values, clean];
  }
}
