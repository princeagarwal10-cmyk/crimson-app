import '../../features/catalogue/domain/catalogue_models.dart';

final _catalogueSearchIndexCache = <_SearchIndexCacheEntry>[];

const productFields = [
  'name',
  'sku',
  'category',
  'subcategory',
  'brand',
  'size_spec',
  'finish_color',
  'breadth',
  'length',
  'height',
  'thickness',
  'selling_price',
  'image_path',
  'notes',
  'keywords',
];

const headerAliases = {
  'name': 'name',
  'item name': 'name',
  'product name': 'name',
  'sku': 'sku',
  'code': 'sku',
  'product code': 'sku',
  'category': 'category',
  'subcategory': 'subcategory',
  'sub category': 'subcategory',
  'brand': 'brand',
  'size/specification': 'size_spec',
  'size': 'size_spec',
  'variation size': 'size_spec',
  'specification': 'size_spec',
  'breadth': 'breadth',
  'width': 'breadth',
  'b': 'breadth',
  'length': 'length',
  'l': 'length',
  'height': 'height',
  'h': 'height',
  'thickness': 'thickness',
  'thick': 'thickness',
  'rod thickness': 'thickness',
  'finish/color': 'finish_color',
  'finish': 'finish_color',
  'color': 'finish_color',
  'colour': 'finish_color',
  'selling price': 'selling_price',
  'price': 'selling_price',
  'image path': 'image_path',
  'notes': 'notes',
  'keyword': 'keywords',
  'keywords': 'keywords',
  'tag': 'keywords',
  'tags': 'keywords',
  'search keywords': 'keywords',
  'search tags': 'keywords',
};

const internalProductCodeHeaders = {
  'internal product id',
  'internal product code',
  'crimson product code',
  'crimson code',
  'product id',
};

const groupNameHeaders = {
  'group name',
  'group',
  'parent name',
  'parent product',
};

const itemNameHeaders = {
  'item name',
  'product name',
  'name',
};

const rowSizeColumnHeaders = {
  'size',
  'variation size',
};

const simplePriceColumnHeaders = {
  'price',
  'selling price',
  'rate',
};

final productPriceTableAliases = {
  ...headerAliases,
  'finish': 'variation_finish',
  'variation finish': 'variation_finish',
};

String cleanText(Object? value) {
  return (value ?? '').toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

extension _CleanTextFallback on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

({String breadth, String length, String height}) parseBreadthLengthHeight(
    Object? value) {
  final text = cleanText(value)
      .toUpperCase()
      .replaceAll('×', 'X')
      .replaceAll('*', 'X')
      .replaceAll(RegExp(r'\s+'), '');
  final match = RegExp(r'^(\d+(?:\.\d+)?)X(\d+(?:\.\d+)?)X(\d+(?:\.\d+)?)$')
      .firstMatch(text);
  if (match == null) return (breadth: '', length: '', height: '');
  return (
    breadth: match.group(1) ?? '',
    length: match.group(2) ?? '',
    height: match.group(3) ?? '',
  );
}

CatalogueState reconcileSimplePluralCategoryAliases(CatalogueState state) {
  final categories = <CategoryDraft>[];
  var products = [...state.products];

  for (final incoming in state.categories) {
    final incomingName = cleanText(incoming.name);
    if (incomingName.isEmpty) continue;
    final family = _simplePluralFamily(incomingName);
    final existingIndex = categories.indexWhere(
      (category) => _simplePluralFamily(category.name) == family,
    );
    if (existingIndex < 0) {
      categories.add(incoming.copyWith(name: incomingName));
      continue;
    }

    final existing = categories[existingIndex];
    final existingCount = products
        .where((product) => _normal(product.category) == _normal(existing.name))
        .length;
    final incomingCount = products
        .where((product) => _normal(product.category) == _normal(incomingName))
        .length;
    final preferIncoming = incomingCount > existingCount;
    final target = preferIncoming ? incoming : existing;
    final alias = preferIncoming ? existing : incoming;
    final targetName = cleanText(target.name);
    final aliasName = cleanText(alias.name);
    final subcategories = _uniqueCleanText([
      ...target.subcategories,
      ...alias.subcategories,
    ]);
    final subcategoryImages = <String, String>{
      ...alias.subcategoryImages,
      ...target.subcategoryImages,
    };

    categories[existingIndex] = target.copyWith(
      name: targetName,
      imagePath: cleanText(target.imagePath).isNotEmpty
          ? target.imagePath
          : alias.imagePath,
      subcategories: subcategories,
      subcategoryImages: subcategoryImages,
    );
    products = products
        .map((product) => _normal(product.category) == _normal(aliasName)
            ? product.copyWith(category: targetName)
            : product)
        .toList();
  }

  return state.copyWith(products: products, categories: categories);
}

String _simplePluralFamily(String value) {
  final normalized = _normal(value);
  if (normalized.length > 3 &&
      normalized.endsWith('s') &&
      !normalized.endsWith('ss')) {
    return normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

List<String> _uniqueCleanText(Iterable<String> values) {
  final result = <String>[];
  for (final value in values) {
    final clean = cleanText(value);
    if (clean.isEmpty ||
        result.any((item) => _normal(item) == _normal(clean))) {
      continue;
    }
    result.add(clean);
  }
  return result;
}

String normalizeHeader(Object? value) => cleanText(value).toLowerCase();

String formatCompactPrice(Object? value) {
  final amount = double.tryParse(cleanText(value)) ?? 0;
  if (amount == amount.truncateToDouble()) {
    return amount.toInt().toString();
  }
  return amount.toStringAsFixed(2);
}

String parsePrice(Object? value) {
  final text = cleanText(value).replaceAll(',', '');
  if (text.isEmpty) {
    return '0.00';
  }
  final amount = double.tryParse(text);
  if (amount == null) {
    throw FormatException('Invalid price: $value');
  }
  return amount.toStringAsFixed(2);
}

BulkPasteImportResult parseBulkPasteProducts(String rawText) {
  final lines = rawText
      .split(RegExp(r'\r?\n'))
      .where((line) => line.trim().isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    return const BulkPasteImportResult(
      products: [],
      categories: [],
      errors: ['No rows found.'],
    );
  }

  final delimiter = _detectDelimiter(lines.first);
  final rawHeaders = _splitRow(lines.first, delimiter).map(cleanText).toList();
  final headers = rawHeaders.map(normalizeHeader).toList();
  final index = <String, int>{};
  for (var i = 0; i < headers.length; i++) {
    index[headers[i]] = i;
  }

  int? column(Set<String> names) {
    for (final name in names) {
      final value = index[name];
      if (value != null) return value;
    }
    return null;
  }

  String cell(List<String> row, Set<String> names) {
    final columnIndex = column(names);
    if (columnIndex == null || columnIndex >= row.length) return '';
    return cleanText(row[columnIndex]);
  }

  final finishColumn = column({
    'finish',
    'finish/color',
    'finish colour',
    'color',
    'colour',
  });
  final sizeColumn = column(rowSizeColumnHeaders);
  final priceColumn = column(simplePriceColumnHeaders);
  final isLongRows = sizeColumn != null && priceColumn != null;
  final wideSizeColumns = <({int index, String size})>[];
  if (!isLongRows && finishColumn != null) {
    for (var headerIndex = finishColumn + 1;
        headerIndex < rawHeaders.length;
        headerIndex++) {
      final size = cleanText(rawHeaders[headerIndex]);
      final normalized = normalizeHeader(size);
      if (size.isEmpty || _isReservedBulkHeader(normalized)) continue;
      wideSizeColumns.add((index: headerIndex, size: size));
    }
  }
  final isWideMatrix = !isLongRows && wideSizeColumns.isNotEmpty;
  if (!isLongRows && !isWideMatrix) {
    return const BulkPasteImportResult(
      products: [],
      categories: [],
      errors: [
        'Unsupported table layout. Use FINISH + SIZE + PRICE rows, or place size columns such as KNOB, 96MM and 4 INCH after FINISH.',
      ],
    );
  }

  final errors = <String>[];
  final grouped = <String, _BulkProductBuilder>{};
  final categories = <String, List<String>>{};

  for (var lineNumber = 2; lineNumber <= lines.length; lineNumber++) {
    final row = _splitRow(lines[lineNumber - 1], delimiter);
    final internalProductCode = cell(row, internalProductCodeHeaders);
    final groupName = cell(row, groupNameHeaders);
    final itemName = cell(row, itemNameHeaders);
    final category = cell(row, {'category'});
    final subcategory = cell(row, {'subcategory', 'sub category'});
    final brand = cell(row, {'brand'});
    final finish = cell(row, {
      'finish',
      'finish/color',
      'finish colour',
      'color',
      'colour',
    });
    final keywords = cell(row, {
      'keyword',
      'keywords',
      'tag',
      'tags',
      'search keywords',
      'search tags',
    });
    final productName = cleanText(
      groupName.isNotEmpty
          ? groupName
          : itemName.isNotEmpty
              ? itemName
              : subcategory,
    );

    if (productName.isEmpty) {
      errors.add(
          'Row $lineNumber skipped: group name, item name and subcategory are blank.');
      continue;
    }
    if (category.isEmpty) {
      errors.add('Row $lineNumber skipped: category is blank.');
      continue;
    }
    if (subcategory.isEmpty) {
      errors.add('Row $lineNumber skipped: subcategory is blank.');
      continue;
    }
    if (finish.isEmpty) {
      errors.add('Row $lineNumber skipped: finish is blank.');
      continue;
    }

    final variations = <_BulkVariationValue>[];
    if (isLongRows) {
      final size = sizeColumn < row.length ? cleanText(row[sizeColumn]) : '';
      final priceText =
          priceColumn < row.length ? cleanText(row[priceColumn]) : '';
      late final String price;
      try {
        price = parsePrice(priceText);
      } on FormatException catch (error) {
        errors.add('Row $lineNumber skipped: ${error.message}');
        continue;
      }
      variations.add(_BulkVariationValue(size: size, price: price));
    } else {
      for (final sizeColumn in wideSizeColumns) {
        final priceText = sizeColumn.index < row.length
            ? cleanText(row[sizeColumn.index])
            : '';
        if (_isUnavailableWidePrice(priceText)) continue;
        late final String price;
        try {
          price = parsePrice(priceText);
        } on FormatException catch (error) {
          errors.add(
              'Row $lineNumber, ${sizeColumn.size} skipped: ${error.message}');
          continue;
        }
        variations.add(
          _BulkVariationValue(size: sizeColumn.size, price: price),
        );
      }
      if (variations.isEmpty) {
        errors.add(
            'Row $lineNumber skipped: no available non-zero prices were found.');
        continue;
      }
    }

    final builder = grouped.putIfAbsent(
      _bulkProductKey(internalProductCode, productName),
      () => _BulkProductBuilder(
        internalProductCode: internalProductCode,
        name: productName,
        category: category,
        subcategory: subcategory,
        brand: brand,
      ),
    );
    builder.addKeywords(keywords);
    for (final variation in variations) {
      final parsedDimensions = parseBreadthLengthHeight(variation.size);
      builder.addVariation(
        finish: finish,
        size: variation.size,
        breadth: isLongRows
            ? cell(row, {'breadth', 'width', 'b'})
                .ifEmpty(parsedDimensions.breadth)
            : parsedDimensions.breadth,
        length: isLongRows
            ? cell(row, {'length', 'l'}).ifEmpty(parsedDimensions.length)
            : parsedDimensions.length,
        height: isLongRows
            ? cell(row, {'height', 'h'}).ifEmpty(parsedDimensions.height)
            : parsedDimensions.height,
        thickness: isLongRows
            ? cell(row, {'thickness', 'thick', 'rod thickness'})
            : '',
        price: variation.price,
        sourceItemName: itemName,
      );
    }

    categories.putIfAbsent(category, () => <String>[]);
    if (!categories[category]!
        .any((item) => _normal(item) == _normal(subcategory))) {
      categories[category]!.add(subcategory);
    }
  }

  return BulkPasteImportResult(
    products: grouped.values.map((builder) => builder.build()).toList(),
    categories: [
      for (final entry in categories.entries)
        CategoryDraft(name: entry.key, subcategories: entry.value),
    ],
    errors: errors,
    format: isWideMatrix
        ? BulkPasteImportFormat.widePriceMatrix
        : BulkPasteImportFormat.longRows,
  );
}

bool _isReservedBulkHeader(String header) {
  return headerAliases.containsKey(header) ||
      internalProductCodeHeaders.contains(header) ||
      groupNameHeaders.contains(header) ||
      itemNameHeaders.contains(header) ||
      const {
        'keyword',
        'keywords',
        'tag',
        'tags',
        'search keywords',
        'search tags',
      }.contains(header);
}

bool _isUnavailableWidePrice(String value) {
  final clean = cleanText(value);
  if (clean.isEmpty || clean == '-') return true;
  final amount = double.tryParse(clean.replaceAll(',', ''));
  return amount != null && amount <= 0;
}

class _BulkVariationValue {
  const _BulkVariationValue({required this.size, required this.price});

  final String size;
  final String price;
}

VariationMatrix variationPriceMatrix(
  List<VariationDraft> variations, {
  bool skipBlankLabels = false,
}) {
  final sizes = <String>[];
  final finishes = <String>[];
  final priceLists = <String, List<String>>{};
  final extraLines = <String>[];

  for (final variation in variations) {
    final sizeText = cleanText(variation.size);
    final finishText = cleanText(variation.finish);
    if (skipBlankLabels && (sizeText.isEmpty || finishText.isEmpty)) {
      continue;
    }
    final size = sizeText.isEmpty ? '-' : sizeText;
    final finish = finishText.isEmpty ? '-' : finishText;
    if (!sizes.contains(size)) sizes.add(size);
    if (!finishes.contains(finish)) finishes.add(finish);
    final key = '$finish\u001f$size';
    priceLists
        .putIfAbsent(key, () => [])
        .add(formatCompactPrice(variation.price));

    final extras = <String>[];
    if (variation.sku.isNotEmpty) extras.add('SKU ${variation.sku}');
    if (variation.notes.isNotEmpty) extras.add(variation.notes);
    if (extras.isNotEmpty) {
      extraLines.add('$finish / $size: ${extras.join(' - ')}');
    }
  }

  return VariationMatrix(
    sizes: sortSizeLabels(sizes),
    finishes: finishes,
    prices: priceLists.map((key, value) => MapEntry(key, value.join(' / '))),
    extraLines: extraLines,
  );
}

List<String> sortSizeLabels(Iterable<String> values) {
  final result = values.toList(growable: false);
  result.sort(compareSizeLabels);
  return result;
}

int compareSizeLabels(String left, String right) {
  final leftKey = _SizeSortKey.from(left);
  final rightKey = _SizeSortKey.from(right);
  return leftKey.compareTo(rightKey);
}

class _SizeSortKey {
  const _SizeSortKey({
    required this.rank,
    required this.measure,
    required this.naturalParts,
  });

  factory _SizeSortKey.from(String value) {
    final text = cleanText(value);
    final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (normalized == 'knob' || normalized == 'knobs') {
      return const _SizeSortKey(rank: 0, measure: 0, naturalParts: ['knob']);
    }
    if (normalized == '-' || normalized.isEmpty) {
      return const _SizeSortKey(rank: 2, measure: 0, naturalParts: ['']);
    }

    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(normalized);
    if (match != null) {
      final value = double.tryParse(match.group(1) ?? '');
      if (value != null) {
        return _SizeSortKey(
          rank: 1,
          measure: value * _sizeUnitFactor(normalized),
          naturalParts: _naturalSizeParts(normalized),
        );
      }
    }

    return _SizeSortKey(
      rank: 3,
      measure: 0,
      naturalParts: _naturalSizeParts(normalized),
    );
  }

  final int rank;
  final double measure;
  final List<String> naturalParts;

  int compareTo(_SizeSortKey other) {
    final rankCompare = rank.compareTo(other.rank);
    if (rankCompare != 0) return rankCompare;
    final measureCompare = measure.compareTo(other.measure);
    if (measureCompare != 0) return measureCompare;
    final limit = naturalParts.length < other.naturalParts.length
        ? naturalParts.length
        : other.naturalParts.length;
    for (var index = 0; index < limit; index++) {
      final leftPart = naturalParts[index];
      final rightPart = other.naturalParts[index];
      final leftNumber = double.tryParse(leftPart);
      final rightNumber = double.tryParse(rightPart);
      final comparison = leftNumber != null && rightNumber != null
          ? leftNumber.compareTo(rightNumber)
          : leftPart.compareTo(rightPart);
      if (comparison != 0) return comparison;
    }
    return naturalParts.length.compareTo(other.naturalParts.length);
  }
}

double _sizeUnitFactor(String normalized) {
  if (normalized.contains('mm')) return 1;
  if (normalized.contains('cm')) return 10;
  if (normalized.contains('inch') ||
      normalized.contains('in') ||
      normalized.contains('"')) {
    return 25.4;
  }
  if (normalized.contains('feet') ||
      normalized.contains('foot') ||
      normalized.contains('ft') ||
      normalized.contains('fit') ||
      normalized.contains("'")) {
    return 304.8;
  }
  if (normalized.contains('mtr') ||
      normalized.contains('meter') ||
      normalized.contains('metre')) {
    return 1000;
  }
  return 1;
}

List<String> _naturalSizeParts(String value) {
  return RegExp(r'\d+(?:\.\d+)?|\D+')
      .allMatches(value)
      .map((match) => match.group(0) ?? '')
      .toList(growable: false);
}

class CatalogueProductFilter {
  const CatalogueProductFilter({
    this.query = '',
    this.category = '',
    this.subcategory = '',
    this.brand = '',
    this.finish = '',
    this.size = '',
    this.minPrice,
    this.maxPrice,
  });

  final String query;
  final String category;
  final String subcategory;
  final String brand;
  final String finish;
  final String size;
  final double? minPrice;
  final double? maxPrice;

  bool get hasFilters =>
      cleanText(query).isNotEmpty ||
      cleanText(category).isNotEmpty ||
      cleanText(subcategory).isNotEmpty ||
      cleanText(brand).isNotEmpty ||
      cleanText(finish).isNotEmpty ||
      cleanText(size).isNotEmpty ||
      minPrice != null ||
      maxPrice != null;
}

List<ProductDraft> filterCatalogueProducts(
  List<ProductDraft> products,
  CatalogueProductFilter filter, {
  List<CategoryDraft> categories = const [],
  List<SearchTerminologyDraft> terminology = const [],
}) {
  final searchIndex = _catalogueSearchIndex(products, categories, terminology);
  final query = _SmartSearchQuery.parse(
    filter.query,
    vocabulary: searchIndex.vocabulary,
  );
  final category = _normal(filter.category);
  final subcategory = _normal(filter.subcategory);
  final brand = _normal(filter.brand);
  final finish = _smartTokens(filter.finish);
  final size = _smartTokens(filter.size);
  final scored = <_ScoredProduct>[];

  final candidateIndexes = query.hasTerms
      ? searchIndex.candidateIndexes(query)
      : Iterable<int>.generate(products.length);
  for (final productIndex in candidateIndexes) {
    final product = products[productIndex];
    if (category.isNotEmpty && _normal(product.category) != category) {
      continue;
    }
    if (subcategory.isNotEmpty && _normal(product.subcategory) != subcategory) {
      continue;
    }
    if (brand.isNotEmpty && _normal(product.brand) != brand) {
      continue;
    }
    if (finish.isNotEmpty &&
        !_tokenSetMatches(_productFinishTokens(product), finish)) {
      continue;
    }
    if (size.isNotEmpty &&
        !_tokenSetMatches(_productSizeTokens(product), size)) {
      continue;
    }
    if (!_priceInRange(product, filter.minPrice, filter.maxPrice)) {
      continue;
    }
    scored.add(_ScoredProduct(
      product: product,
      score: query.hasTerms
          ? _smartSearchScore(
              product,
              searchIndex.documents[productIndex],
              query,
            )
          : 0,
    ));
  }

  if (query.hasTerms) {
    scored.sort((left, right) {
      final score = right.score.compareTo(left.score);
      if (score != 0) return score;
      return cleanText(left.product.name)
          .compareTo(cleanText(right.product.name));
    });
  }

  return scored.map((item) => item.product).toList(growable: false);
}

List<String> smartSearchChips(String query) =>
    _SmartSearchQuery.parse(query).labels;

/// Matches a category name while the user is still typing its words.
bool categoryNameMatchesSearch(String categoryName, String query) {
  final name = cleanText(categoryName).toLowerCase();
  final search = cleanText(query).toLowerCase();
  if (name.isEmpty || search.isEmpty) return false;
  final nameWords = RegExp(r'[a-z0-9]+')
      .allMatches(name)
      .map((match) => match.group(0)!)
      .toList(growable: false);
  final searchWords = RegExp(r'[a-z0-9]+')
      .allMatches(search)
      .map((match) => match.group(0)!)
      .toList(growable: false);
  if (searchWords.isEmpty) return false;
  if (name.contains(search)) return true;
  return searchWords.every((word) =>
      nameWords.any((nameWord) => nameWord.startsWith(word)));
}

int _smartSearchScore(
  ProductDraft product,
  _SmartSearchDocument document,
  _SmartSearchQuery query,
) {
  var score = 0;
  final normalName = _smartNormalize(product.name);
  final normalQuery = _smartNormalize(query.raw);
  if (normalName == normalQuery) score += 200;
  if (normalName.startsWith(normalQuery) && normalQuery.isNotEmpty) {
    score += 120;
  }
  if (document.keywordTokens.any(query.tokens.contains)) score += 70;
  if (document.variationTokens.any(query.tokens.contains)) score += 45;
  score += query.tokens.where(document.tokens.contains).length * 12;
  return score;
}

_SmartSearchDocument _buildSmartSearchDocument(
  ProductDraft product,
  CategoryDraft? category,
) {
  final textParts = <String>[
    product.name,
    product.sku,
    product.internalProductCode,
    product.category,
    product.subcategory,
    product.brand,
    product.sizeSpec,
    product.finishColor,
    product.sellingPrice,
    product.notes,
    for (final variation in product.variations) ...[
      variation.size,
      variation.finish,
      variation.breadth,
      variation.length,
      variation.height,
      variation.thickness,
      variation.price,
      variation.sku,
      variation.notes,
    ],
  ];
  final keywordParts = <String>[
    ...product.keywords,
    if (category != null) ...category.keywords,
  ];
  final variationTokens = _smartTokens([
    for (final variation in product.variations) ...[
      variation.size,
      variation.finish,
      variation.breadth,
      variation.length,
      variation.height,
      variation.thickness,
      variation.price,
      variation.sku,
      variation.notes,
    ],
  ].join(' '));
  final document = _SmartSearchDocument(
    tokens: {
      ..._smartTokens(textParts.join(' ')),
      ..._smartTokens(keywordParts.join(' ')),
    },
    keywordTokens: _smartTokens(keywordParts.join(' ')),
    variationTokens: variationTokens,
  );
  return document;
}

Set<String> _productFinishTokens(ProductDraft product) => _smartTokens([
      product.finishColor,
      for (final variation in product.variations) variation.finish,
    ].join(' '));

Set<String> _productSizeTokens(ProductDraft product) => _smartTokens([
      product.sizeSpec,
      for (final variation in product.variations) ...[
        variation.size,
        variation.breadth,
        variation.length,
        variation.height,
        variation.thickness
      ],
    ].join(' '));

bool _tokenSetMatches(Set<String> haystack, Set<String> needle) {
  return needle.every(haystack.contains);
}

class _SmartSearchQuery {
  _SmartSearchQuery._(
      {required this.raw,
      required this.tokens,
      required this.labels,
      required this.terms});

  factory _SmartSearchQuery.parse(
    String value, {
    _SearchVocabulary? vocabulary,
  }) {
    final raw = cleanText(value);
    final tokens = _smartTokens(raw);
    final resolvedVocabulary =
        vocabulary ?? _SearchVocabulary(const <SearchTerminologyDraft>[]);
    return _SmartSearchQuery._(
      raw: raw,
      tokens: tokens,
      labels: _smartLabels(raw, tokens),
      terms: resolvedVocabulary.queryTerms(raw),
    );
  }

  final String raw;
  final Set<String> tokens;
  final List<String> labels;
  final List<_SearchQueryTerm> terms;

  bool get hasTerms => terms.isNotEmpty;
}

class _SearchIndexCacheEntry {
  const _SearchIndexCacheEntry({
    required this.products,
    required this.categories,
    required this.terminologySignature,
    required this.index,
  });

  final List<ProductDraft> products;
  final List<CategoryDraft> categories;
  final String terminologySignature;
  final _CatalogueSearchIndex index;
}

_CatalogueSearchIndex _catalogueSearchIndex(
  List<ProductDraft> products,
  List<CategoryDraft> categories,
  List<SearchTerminologyDraft> terminology,
) {
  final signature = terminology
      .map((entry) =>
          '${_smartNormalize(entry.canonical)}:${entry.aliases.map(_smartNormalize).join(',')}')
      .join('|');
  final cachedIndex = _catalogueSearchIndexCache.indexWhere(
    (entry) =>
        identical(entry.products, products) &&
        identical(entry.categories, categories) &&
        entry.terminologySignature == signature,
  );
  if (cachedIndex >= 0) {
    final cached = _catalogueSearchIndexCache.removeAt(cachedIndex);
    _catalogueSearchIndexCache.insert(0, cached);
    return cached.index;
  }

  final index = _CatalogueSearchIndex.build(
    products,
    categories,
    terminology,
  );
  _catalogueSearchIndexCache.insert(
    0,
    _SearchIndexCacheEntry(
      products: products,
      categories: categories,
      terminologySignature: signature,
      index: index,
    ),
  );
  if (_catalogueSearchIndexCache.length > 4) {
    _catalogueSearchIndexCache.removeLast();
  }
  return index;
}

class _CatalogueSearchIndex {
  const _CatalogueSearchIndex({
    required this.documents,
    required this.vocabulary,
    required this.exactTokenProducts,
    required this.prefixProducts,
  });

  factory _CatalogueSearchIndex.build(
    List<ProductDraft> products,
    List<CategoryDraft> categories,
    List<SearchTerminologyDraft> terminology,
  ) {
    final vocabulary = _SearchVocabulary(terminology);
    final categoryMap = {
      for (final category in categories) _normal(category.name): category,
    };
    final documents = <_SmartSearchDocument>[];
    final exact = <String, Set<int>>{};
    final prefixes = <String, Set<int>>{};
    for (var index = 0; index < products.length; index++) {
      final product = products[index];
      final document = _buildSmartSearchDocument(
        product,
        categoryMap[_normal(product.category)],
      );
      documents.add(document);
      for (final token in document.tokens) {
        exact.putIfAbsent(token, () => <int>{}).add(index);
        if (token.startsWith('size:')) {
          prefixes.putIfAbsent(token, () => <int>{}).add(index);
          continue;
        }
        for (var length = 1; length <= token.length; length++) {
          final prefix = token.substring(0, length);
          prefixes.putIfAbsent(prefix, () => <int>{}).add(index);
        }
      }
    }
    return _CatalogueSearchIndex(
      documents: documents,
      vocabulary: vocabulary,
      exactTokenProducts: exact,
      prefixProducts: prefixes,
    );
  }

  final List<_SmartSearchDocument> documents;
  final _SearchVocabulary vocabulary;
  final Map<String, Set<int>> exactTokenProducts;
  final Map<String, Set<int>> prefixProducts;

  Iterable<int> candidateIndexes(_SmartSearchQuery query) {
    Set<int>? candidates;
    for (final term in query.terms) {
      final matching = term.group == null
          ? Set<int>.from(prefixProducts[term.prefix] ?? const <int>{})
          : _productsForGroup(term.group!);
      if (matching.isEmpty) return const <int>[];
      if (candidates == null) {
        candidates = matching;
      } else {
        candidates = candidates.intersection(matching);
      }
      if (candidates.isEmpty) return const <int>[];
    }
    final result = (candidates ?? const <int>{}).toList(growable: false)
      ..sort();
    return result;
  }

  Set<int> _productsForGroup(_SearchTerminologyGroup group) {
    final matching = <int>{};
    for (final variant in group.variants) {
      Set<int>? variantMatches;
      for (final token in variant) {
        final tokenProducts = exactTokenProducts[token];
        if (tokenProducts == null) {
          variantMatches = <int>{};
          break;
        }
        variantMatches = variantMatches == null
            ? Set<int>.from(tokenProducts)
            : variantMatches.intersection(tokenProducts);
      }
      if (variantMatches != null) matching.addAll(variantMatches);
    }
    return matching;
  }
}

class _SearchVocabulary {
  _SearchVocabulary(List<SearchTerminologyDraft> customTerminology)
      : groups = _buildGroups(customTerminology);

  final List<_SearchTerminologyGroup> groups;

  static List<_SearchTerminologyGroup> _buildGroups(
    List<SearchTerminologyDraft> customTerminology,
  ) {
    final entries = <SearchTerminologyDraft>[
      ...customTerminology,
      ...builtInSearchTerminology,
    ];
    final groups = <_SearchTerminologyGroup>[];
    for (final entry in entries) {
      final canonical = _smartNormalize(entry.canonical);
      if (canonical.isEmpty) continue;
      final variants = <List<String>>[];
      final seen = <String>{};
      for (final value in [entry.canonical, ...entry.aliases]) {
        final normalized = _smartNormalize(value);
        if (normalized.isEmpty || !seen.add(normalized)) continue;
        variants.add(normalized.split(' '));
      }
      variants.sort((left, right) => right.length.compareTo(left.length));
      groups.add(_SearchTerminologyGroup(
        canonical: canonical,
        variants: variants,
      ));
    }
    return groups;
  }

  List<_SearchQueryTerm> queryTerms(String raw) {
    final words = _smartNormalize(raw)
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    final terms = <_SearchQueryTerm>[];
    var index = 0;
    while (index < words.length) {
      final compactMeasurement = RegExp(
        r'''^(\d+(?:\.\d+)?)(mm|cm|inch|inches|in|ft|feet|foot|fit|mtr|meter|metre)$''',
      ).firstMatch(words[index]);
      if (compactMeasurement != null) {
        final number = double.parse(compactMeasurement.group(1)!);
        final unit = compactMeasurement.group(2)!;
        terms.add(_SearchQueryTerm.prefix(
          'size:${(number * _smartUnitFactor(unit)).round()}',
        ));
        index++;
        continue;
      }
      if (index + 1 < words.length) {
        final number = double.tryParse(words[index]);
        final unit = words[index + 1];
        if (number != null && _isSmartUnit(unit)) {
          terms.add(_SearchQueryTerm.prefix(
            'size:${(number * _smartUnitFactor(unit)).round()}',
          ));
          index += 2;
          continue;
        }
      }

      _SearchTerminologyGroup? matchedGroup;
      var matchedLength = 0;
      for (final group in groups) {
        for (final variant in group.variants) {
          if (variant.length <= matchedLength ||
              index + variant.length > words.length) {
            continue;
          }
          var matches = true;
          for (var offset = 0; offset < variant.length; offset++) {
            if (words[index + offset] != variant[offset]) {
              matches = false;
              break;
            }
          }
          if (matches) {
            matchedGroup = group;
            matchedLength = variant.length;
          }
        }
      }
      if (matchedGroup != null) {
        terms.add(_SearchQueryTerm.group(matchedGroup));
        index += matchedLength;
      } else {
        terms.add(_SearchQueryTerm.prefix(words[index]));
        index++;
      }
    }
    return terms;
  }
}

bool _isSmartUnit(String value) {
  return const {
    'mm',
    'cm',
    'inch',
    'inches',
    'in',
    'ft',
    'feet',
    'foot',
    'fit',
    'mtr',
    'meter',
    'metre',
  }.contains(value);
}

class _SearchTerminologyGroup {
  const _SearchTerminologyGroup({
    required this.canonical,
    required this.variants,
  });

  final String canonical;
  final List<List<String>> variants;
}

class _SearchQueryTerm {
  const _SearchQueryTerm.prefix(this.prefix) : group = null;
  const _SearchQueryTerm.group(this.group) : prefix = '';

  final String prefix;
  final _SearchTerminologyGroup? group;
}

class _ScoredProduct {
  const _ScoredProduct({required this.product, required this.score});

  final ProductDraft product;
  final int score;
}

class _SmartSearchDocument {
  const _SmartSearchDocument({
    required this.tokens,
    required this.keywordTokens,
    required this.variationTokens,
  });

  final Set<String> tokens;
  final Set<String> keywordTokens;
  final Set<String> variationTokens;
}

Set<String> _smartTokens(String value) {
  final original = cleanText(value).toLowerCase();
  if (original.isEmpty) return <String>{};
  final tokens = <String>{};
  final prepared = original
      .replaceAll(RegExp(r'\br\s*[/.-]\s*g\b'), ' rg ')
      .replaceAll(RegExp(r'\bc\s*[/.-]\s*p\b'), ' cp ')
      .replaceAll(RegExp(r'\bs\s*[/.-]\s*s\b'), ' ss ')
      .replaceAll('&', ' and ');

  for (final match in RegExp(
          r'''(\d+(?:\.\d+)?)\s*(mm|millimeter|millimetre|cm|inch|inches|in|"|ft|feet|foot|fit|mtr|meter|metre|')''')
      .allMatches(prepared)) {
    final number = double.tryParse(match.group(1) ?? '');
    final unit = match.group(2) ?? '';
    if (number == null) continue;
    tokens.add('size:${(number * _smartUnitFactor(unit)).round()}');
    tokens.add(_compactNumber(number));
    tokens.add(_smartUnitLabel(unit));
  }

  final words =
      _smartNormalize(prepared).split(' ').where((word) => word.isNotEmpty);
  final wordList = words.toList(growable: false);
  tokens.addAll(wordList);
  for (final word in List<String>.from(tokens)) {
    tokens.addAll(_synonymTokens(word));
  }
  return tokens.where((token) => token.trim().isNotEmpty).toSet();
}

String _smartNormalize(String value) {
  return cleanText(value)
      .toLowerCase()
      .replaceAll(RegExp(r'\br\s*[/.-]\s*g\b'), ' rg ')
      .replaceAll(RegExp(r'\bc\s*[/.-]\s*p\b'), ' cp ')
      .replaceAll(RegExp(r'\bs\s*[/.-]\s*s\b'), ' ss ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Set<String> _synonymTokens(String token) {
  switch (token) {
    case 'rg':
    case 'rosegold':
      return {'rose', 'gold', 'rosegold', 'rg'};
    case 'ss':
    case 'steel':
    case 'stainless':
    case 'stainlesssteel':
      return {'ss', 'steel', 'stainless', 'stainlesssteel'};
    case 'cp':
    case 'chrome':
      return {'cp', 'chrome'};
    case 'mat':
    case 'matt':
    case 'matte':
      return {'mat', 'matt', 'matte'};
    case 'towerbolt':
    case 'tower':
    case 'bolt':
      return {'towerbolt', 'tower', 'bolt'};
    case 'handle':
    case 'handles':
      return {'handle', 'handles'};
    case 'knob':
    case 'knobs':
      return {'knob', 'knobs'};
  }
  return const <String>{};
}

String _compactNumber(double value) {
  if (value == value.truncateToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

String _smartUnitLabel(String unit) {
  final text = unit.toLowerCase();
  if (text.contains('mm') || text.contains('mill')) return 'mm';
  if (text == 'cm') return 'cm';
  if (text.contains('inch') || text == 'in' || text == '"') return 'inch';
  if (text.contains('ft') ||
      text.contains('feet') ||
      text.contains('foot') ||
      text.contains('fit') ||
      text == "'") {
    return 'ft';
  }
  if (text.contains('mtr') ||
      text.contains('meter') ||
      text.contains('metre')) {
    return 'mtr';
  }
  return text;
}

double _smartUnitFactor(String unit) {
  switch (_smartUnitLabel(unit)) {
    case 'mm':
      return 1;
    case 'cm':
      return 10;
    case 'inch':
      return 25.4;
    case 'ft':
      return 304.8;
    case 'mtr':
      return 1000;
  }
  return 1;
}

List<String> _smartLabels(String raw, Set<String> tokens) {
  final words =
      _smartNormalize(raw).split(' ').where((word) => word.isNotEmpty);
  final labels = <String>[];
  for (final word in words) {
    final label = word.length <= 2
        ? word.toUpperCase()
        : '${word[0].toUpperCase()}${word.substring(1)}';
    if (!labels.contains(label)) labels.add(label);
  }
  return labels.take(6).toList(growable: false);
}

List<ProductDraft> customerVisibleProducts(CatalogueState state) {
  return state.products
      .where((product) => isProductVisibleToCustomers(state, product))
      .toList(growable: false);
}

bool isProductVisibleToCustomers(CatalogueState state, ProductDraft product) {
  if (product.isArchived || (!product.isPublished && !product.isComingSoon)) {
    return false;
  }
  final category = categoryForProduct(state.categories, product);
  if (category == null || !category.isPublished) return false;
  return category.isSubcategoryPublished(product.subcategory);
}

CategoryDraft? categoryForProduct(
  List<CategoryDraft> categories,
  ProductDraft product,
) {
  final productCategory = _normal(product.category);
  if (productCategory.isEmpty) return null;
  for (final category in categories) {
    if (_normal(category.name) == productCategory) return category;
  }
  return null;
}

bool _priceInRange(ProductDraft product, double? minPrice, double? maxPrice) {
  if (minPrice == null && maxPrice == null) return true;
  final prices = [
    double.tryParse(cleanText(product.sellingPrice)) ?? 0,
    for (final variation in product.variations)
      double.tryParse(cleanText(variation.price)) ?? 0,
  ].where((price) => price > 0);

  if (prices.isEmpty) return minPrice == null || minPrice <= 0;
  return prices.any((price) {
    if (minPrice != null && price < minPrice) return false;
    if (maxPrice != null && price > maxPrice) return false;
    return true;
  });
}

String _detectDelimiter(String headerLine) {
  if (headerLine.contains('\t')) return '\t';
  if (headerLine.contains(',')) return ',';
  return '\t';
}

List<String> _splitRow(String row, String delimiter) {
  if (delimiter == ',') {
    return _splitCsvRow(row);
  }
  return row.split(delimiter);
}

List<String> _splitCsvRow(String row) {
  final values = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  for (var index = 0; index < row.length; index++) {
    final char = row[index];
    if (char == '"') {
      quoted = !quoted;
    } else if (char == ',' && !quoted) {
      values.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  values.add(buffer.toString());
  return values;
}

String _normal(String value) {
  return cleanText(value).toLowerCase();
}

String _bulkProductKey(String internalProductCode, String productName) {
  final code = normalizeInternalProductCode(internalProductCode);
  return code.isNotEmpty ? 'code:$code' : 'name:${_normal(productName)}';
}

class _BulkProductBuilder {
  _BulkProductBuilder({
    required this.internalProductCode,
    required this.name,
    required this.category,
    required this.subcategory,
    required this.brand,
  });

  final String internalProductCode;
  final String name;
  final String category;
  final String subcategory;
  final String brand;
  final List<VariationDraft> variations = [];
  final Set<String> _variationKeys = {};
  final List<String> keywords = [];

  void addKeywords(String value) {
    for (final keyword in value.split(RegExp(r'[,;\\n]'))) {
      final clean = cleanText(keyword);
      if (clean.isEmpty) continue;
      if (!keywords.any((item) => _normal(item) == _normal(clean))) {
        keywords.add(clean);
      }
    }
  }

  void addVariation({
    required String finish,
    required String size,
    required String breadth,
    required String length,
    required String height,
    required String thickness,
    required String price,
    required String sourceItemName,
  }) {
    final key = [
      _normal(finish),
      _normal(size),
      _normal(breadth),
      _normal(length),
      _normal(height),
      _normal(thickness),
      price,
    ].join(r'\u001f');
    if (_variationKeys.contains(key)) return;
    _variationKeys.add(key);
    final note = cleanText(sourceItemName);
    variations.add(
      VariationDraft(
        finish: finish,
        size: size,
        breadth: breadth,
        length: length,
        height: height,
        thickness: thickness,
        price: price,
        notes: note.isEmpty || _normal(note) == _normal(name)
            ? ''
            : 'Source: $note',
      ),
    );
  }

  ProductDraft build() {
    final finishes = <String>[];
    final sizes = <String>[];
    for (final variation in variations) {
      if (variation.finish.isNotEmpty && !finishes.contains(variation.finish)) {
        finishes.add(variation.finish);
      }
      if (variation.size.isNotEmpty && !sizes.contains(variation.size)) {
        sizes.add(variation.size);
      }
    }
    return ProductDraft(
      internalProductCode: internalProductCode,
      name: name,
      category: category,
      subcategory: subcategory,
      brand: brand,
      finishColor: finishes.join(', '),
      sizeSpec: sortSizeLabels(sizes).join(', '),
      sellingPrice: variations.isEmpty ? '0.00' : variations.first.price,
      variations: variations,
      keywords: keywords,
      notes: 'Imported from bulk paste.',
    );
  }
}
