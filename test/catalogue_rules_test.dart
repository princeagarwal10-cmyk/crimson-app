import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crimson_catalogue_studio/core/rules/catalogue_rules.dart';
import 'package:crimson_catalogue_studio/features/catalogue/data/catalogue_backup_service.dart';
import 'package:crimson_catalogue_studio/features/catalogue/data/legacy_catalogue_importer.dart';
import 'package:crimson_catalogue_studio/features/catalogue/data/local_catalogue_repository.dart';
import 'package:crimson_catalogue_studio/features/catalogue/data/premium_export_service.dart';
import 'package:crimson_catalogue_studio/features/catalogue/data/product_image_storage.dart';
import 'package:crimson_catalogue_studio/features/catalogue/data/xlsx_catalogue_io.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_health.dart';

void main() {
  test('simple singular category alias is merged into populated plural name',
      () {
    final state = CatalogueState(
      products: [
        ProductDraft(
          id: 'profile-1',
          name: 'G Profile',
          category: 'ALUMINIUM PROFILES',
          subcategory: 'G PROFILE',
          variations: const [
            VariationDraft(finish: 'Black', size: '10FT', price: '100'),
          ],
        ),
      ],
      categories: const [
        CategoryDraft(
          name: 'ALUMINIUM PROFILES',
          subcategories: ['G PROFILE'],
        ),
        CategoryDraft(
          name: 'ALUMINIUM PROFILE',
          subcategories: ['CALENDER'],
          imagePath: 'category.jpg',
        ),
      ],
    );

    final reconciled = reconcileSimplePluralCategoryAliases(state);

    expect(reconciled.categories, hasLength(1));
    expect(reconciled.categories.single.name, 'ALUMINIUM PROFILES');
    expect(
      reconciled.categories.single.subcategories,
      ['G PROFILE', 'CALENDER'],
    );
    expect(reconciled.categories.single.imagePath, 'category.jpg');
    expect(reconciled.products.single.category, 'ALUMINIUM PROFILES');
    expect(reconciled.products.single.variations.single.price, '100');
  });

  test('product image revision survives cloud JSON round trip', () {
    final source = ProductDraft(
      id: 'product-image-sync',
      name: 'Cloud Handle',
      category: 'Handles',
      subcategory: 'Main',
      imagePath: 'https://example.supabase.co/product.jpg',
      imagePaths: const ['https://example.supabase.co/product.jpg'],
      imageRevision: 4,
    );

    final restored = ProductDraft.fromJson(
      Map<String, Object?>.from(
        jsonDecode(jsonEncode(source.toJson())) as Map,
      ),
    );

    expect(restored.imageRevision, 4);
    expect(restored.imagePaths, source.imagePaths);
  });

  test('older catalogue JSON defaults image revision safely', () {
    final restored = ProductDraft.fromJson({
      'name': 'Legacy Product',
      'category': 'Handles',
      'subcategory': 'Main',
    });

    expect(restored.imageRevision, 0);
  });

  test('catalogue taxonomy images survive cloud JSON round trip', () {
    const source = CatalogueState(
      categories: [
        CategoryDraft(
          name: 'Cabinet Handles',
          subcategories: ['Monza'],
          imagePath: 'https://example.supabase.co/category.jpg',
          subcategoryImages: {
            'Monza': 'https://example.supabase.co/monza.jpg',
          },
        ),
      ],
      brands: ['Crimson'],
      brandImages: {
        'Crimson': 'https://example.supabase.co/crimson.jpg',
      },
    );

    final restored = CatalogueState.fromJson(
      Map<String, Object?>.from(
        jsonDecode(jsonEncode(source.toJson())) as Map,
      ),
    );

    expect(restored.categories.single.imagePath,
        source.categories.single.imagePath);
    expect(
      restored.categories.single.subcategoryImages['Monza'],
      source.categories.single.subcategoryImages['Monza'],
    );
    expect(restored.brandImages['Crimson'], source.brandImages['Crimson']);
  });

  test('older catalogue JSON stays published for customer compatibility', () {
    final product = ProductDraft.fromJson({
      'name': 'Legacy Handle',
      'category': 'Cabinet Handles',
      'subcategory': 'Monza',
    });
    final category = CategoryDraft.fromJson({
      'name': 'Cabinet Handles',
      'subcategories': ['Monza'],
    });

    expect(product.isPublished, isTrue);
    expect(category.isPublished, isTrue);
    expect(category.isSubcategoryPublished('Monza'), isTrue);
  });

  test('new catalogue items start hidden until admin publishes them', () {
    final product = ProductDraft(
      name: 'Draft Handle',
      category: 'Cabinet Handles',
      subcategory: 'Monza',
    );
    const category = CategoryDraft(
      name: 'Draft Category',
      subcategories: ['Draft Subcategory'],
    );

    expect(product.isPublished, isFalse);
    expect(category.isPublished, isFalse);
    expect(category.isSubcategoryPublished('Draft Subcategory'), isFalse);
  });

  test('photo inbox keeps grouped images and finish tags through local JSON',
      () {
    final draft = PhotoInboxDraft(
      id: 'photo-group-1',
      images: const [
        PhotoInboxImage(path: 'image-1.jpg', finish: 'Matt Black'),
        PhotoInboxImage(path: 'image-2.jpg', finish: 'Rose Gold'),
      ],
      category: 'Cabinet Handles',
      notes: 'Supplier sample',
    );
    final state = CatalogueState(photoInbox: [draft]);
    final restored = CatalogueState.fromJson(
      Map<String, Object?>.from(jsonDecode(jsonEncode(state.toJson())) as Map),
    );
    expect(restored.photoInbox, hasLength(1));
    expect(restored.photoInbox.single.images, hasLength(2));
    expect(restored.photoInbox.single.images.last.finish, 'Rose Gold');
    expect(restored.photoInbox.single.notes, 'Supplier sample');
    expect(restored.photoInbox.single.isActive, isTrue);
  });

  test('coming soon product is visible only in a published category', () {
    final comingSoon = ProductDraft(
      id: 'soon-1',
      name: 'W Emmy',
      category: 'Cabinet Handles',
      subcategory: 'Welset',
      imagePaths: const ['emmy.jpg'],
      isComingSoon: true,
    );
    final visible = CatalogueState(
      products: [comingSoon],
      categories: const [
        CategoryDraft(
          name: 'Cabinet Handles',
          subcategories: ['Welset'],
          isPublished: true,
          subcategoryPublished: {'Welset': true},
        ),
      ],
    );
    expect(customerVisibleProducts(visible), [comingSoon]);
    expect(
        customerVisibleProducts(visible.copyWith(
          products: [comingSoon.copyWith(isComingSoon: false)],
        )),
        isEmpty);
    expect(
        customerVisibleProducts(visible.copyWith(
          categories: const [CategoryDraft(name: 'Cabinet Handles')],
        )),
        isEmpty);
    final restored = ProductDraft.fromJson(comingSoon.toJson());
    expect(restored.isComingSoon, isTrue);
  });

  test('customer catalogue hides draft products categories and subcategories',
      () {
    final visible = ProductDraft(
      id: 'visible',
      name: 'Visible Handle',
      category: 'Cabinet Handles',
      subcategory: 'Ready',
      isPublished: true,
    );
    final hiddenProduct = ProductDraft(
      id: 'hidden-product',
      name: 'Draft Handle',
      category: 'Cabinet Handles',
      subcategory: 'Ready',
    );
    final hiddenSubcategory = ProductDraft(
      id: 'hidden-subcategory',
      name: 'Internal Handle',
      category: 'Cabinet Handles',
      subcategory: 'Internal',
      isPublished: true,
    );
    final hiddenCategory = ProductDraft(
      id: 'hidden-category',
      name: 'Hidden Category Product',
      category: 'Draft Handles',
      subcategory: 'Ready',
      isPublished: true,
    );
    final archived = ProductDraft(
      id: 'archived',
      name: 'Archived Handle',
      category: 'Cabinet Handles',
      subcategory: 'Ready',
      isPublished: true,
      isArchived: true,
    );

    final state = CatalogueState(
      products: [
        visible,
        hiddenProduct,
        hiddenSubcategory,
        hiddenCategory,
        archived,
      ],
      categories: const [
        CategoryDraft(
          name: 'Cabinet Handles',
          subcategories: ['Ready', 'Internal'],
          isPublished: true,
          subcategoryPublished: {'Ready': true, 'Internal': false},
        ),
        CategoryDraft(
          name: 'Draft Handles',
          subcategories: ['Ready'],
          subcategoryPublished: {'Ready': true},
        ),
      ],
    );

    expect(customerVisibleProducts(state), [visible]);
    expect(isProductVisibleToCustomers(state, visible), isTrue);
    expect(isProductVisibleToCustomers(state, hiddenProduct), isFalse);
    expect(isProductVisibleToCustomers(state, hiddenSubcategory), isFalse);
    expect(isProductVisibleToCustomers(state, hiddenCategory), isFalse);
    expect(isProductVisibleToCustomers(state, archived), isFalse);
  });
  test('rapidly created products receive unique IDs', () {
    final ids = List.generate(
      200,
      (index) => ProductDraft(
        name: 'Product $index',
        category: 'Handles',
        subcategory: 'Main',
      ).id,
    );

    expect(ids.toSet(), hasLength(ids.length));
  });

  test('catalogue JSON repairs duplicate product IDs deterministically', () {
    final source = {
      'products': [
        {
          'id': 'shared-id',
          'name': 'First Handle',
          'category': 'Handles',
          'subcategory': 'Main',
        },
        {
          'id': 'shared-id',
          'name': 'Second Handle',
          'category': 'Handles',
          'subcategory': 'Main',
        },
      ],
    };

    final first = CatalogueState.fromJson(source);
    final second = CatalogueState.fromJson(source);

    expect(first.products.first.id, 'shared-id');
    expect(first.products.last.id, isNot('shared-id'));
    expect(first.products.map((product) => product.id).toSet(), hasLength(2));
    expect(
      first.products.map((product) => product.id).toList(),
      second.products.map((product) => product.id).toList(),
    );
  });

  test('local load persists repaired duplicate product IDs', () async {
    final directory =
        await Directory.systemTemp.createTemp('crimson_duplicate_ids_');
    final store = File('${directory.path}\\catalogue.json');
    await store.writeAsString(jsonEncode({
      'products': [
        {
          'id': 'duplicate',
          'name': 'Handle A',
          'category': 'Handles',
          'subcategory': 'Main',
        },
        {
          'id': 'duplicate',
          'name': 'Handle B',
          'category': 'Handles',
          'subcategory': 'Main',
        },
      ],
    }));

    final repository = LocalCatalogueRepository(storeFile: store);
    final loaded = await repository.load();
    final persisted = jsonDecode(await store.readAsString()) as Map;
    final persistedIds = (persisted['products'] as List)
        .whereType<Map>()
        .map((product) => product['id'].toString())
        .toSet();

    expect(loaded.products.map((product) => product.id).toSet(), hasLength(2));
    expect(persistedIds, hasLength(2));
  });

  test('variation matrix sorts size columns from small to big', () {
    const source = [
      VariationDraft(size: 'KNOB', finish: 'COLA CHOCO', price: '195'),
      VariationDraft(size: '288MM', finish: 'COLA CHOCO', price: '885'),
      VariationDraft(size: '96MM', finish: 'COLA CHOCO', price: '300'),
      VariationDraft(size: 'KNOB', finish: 'MATT BLACK', price: '195'),
      VariationDraft(size: '288MM', finish: 'MATT BLACK', price: '885'),
      VariationDraft(size: '96MM', finish: 'MATT BLACK', price: '300'),
    ];

    final matrix = variationPriceMatrix(source);

    expect(matrix.sizes, ['KNOB', '96MM', '288MM']);
    expect(matrix.finishes, ['COLA CHOCO', 'MATT BLACK']);
    expect(matrix.prices[matrix.key('COLA CHOCO', 'KNOB')], '195');
    expect(matrix.prices[matrix.key('MATT BLACK', '96MM')], '300');
  });

  test('size sorting handles inches feet and plain numeric sizes', () {
    expect(sortSizeLabels(['12"', '4"', '8"', 'KNOB', '10"']),
        ['KNOB', '4"', '8"', '10"', '12"']);
    expect(
        sortSizeLabels(['12FT', '8 FIT', '10FT']), ['8 FIT', '10FT', '12FT']);
    expect(sortSizeLabels(['224', '96', '160']), ['96', '160', '224']);
  });
  test('blank labels are represented as dash in matrix display', () {
    const source = [
      VariationDraft(size: '', finish: 'BLACK', price: '100'),
    ];

    final matrix = variationPriceMatrix(source);

    expect(matrix.sizes, ['-']);
    expect(matrix.finishes, ['BLACK']);
    expect(matrix.prices[matrix.key('BLACK', '-')], '100');
  });

  test('local catalogue store seeds first launch', () async {
    final directory =
        await Directory.systemTemp.createTemp('crimson_catalogue_seed_');
    final repository = LocalCatalogueRepository(
      storeFile: File('${directory.path}\\catalogue_store.json'),
    );

    final state = await repository.load();

    expect(state.products, isNotEmpty);
    expect(state.categories, isNotEmpty);
    expect(await File(repository.storePath).exists(), isTrue);
  });

  test('upsert product updates matching product name instead of duplicating',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('crimson_catalogue_upsert_');
    final repository = LocalCatalogueRepository(
      storeFile: File('${directory.path}\\catalogue_store.json'),
    );

    final original = ProductDraft(
      id: 'product-1',
      name: '1400 Handle',
      sku: 'H-1400',
      category: 'Cabinet Handles',
      subcategory: 'Monza',
      variations: const [
        VariationDraft(size: '160MM', finish: 'Gold', price: '405'),
      ],
    );
    await repository.upsertProduct(original);

    final updated = original.copyWith(
      sku: 'H-1400-NEW',
      variations: const [
        VariationDraft(size: '160MM', finish: 'Gold', price: '455'),
      ],
    );
    final state = await repository.upsertProduct(updated);
    final matches = state.products
        .where((product) => product.name == '1400 Handle')
        .toList();

    expect(matches, hasLength(1));
    expect(matches.single.id, 'product-1');
    expect(matches.single.sku, 'H-1400-NEW');
    expect(matches.single.variations.single.price, '455');
  });

  test('upsert product updates matching product id even when name changes',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('crimson_catalogue_edit_id_');
    final repository = LocalCatalogueRepository(
      storeFile: File('${directory.path}\\catalogue_store.json'),
    );

    final original = ProductDraft(
      id: 'product-42',
      name: 'Old Handle Name',
      sku: 'OLD-42',
      category: 'Cabinet Handles',
      subcategory: 'Monza',
      variations: const [
        VariationDraft(size: '160MM', finish: 'Gold', price: '405'),
      ],
    );
    await repository.upsertProduct(original);

    final edited = original.copyWith(
      name: 'New Handle Name',
      sku: 'NEW-42',
      variations: const [
        VariationDraft(size: '160MM', finish: 'Gold', price: '455'),
      ],
    );
    final state = await repository.upsertProduct(edited);

    expect(state.products.where((product) => product.id == 'product-42'),
        hasLength(1));
    expect(
        state.products.where((product) => product.name.contains('Handle Name')),
        hasLength(1));
    final changed =
        state.products.singleWhere((product) => product.id == 'product-42');
    expect(changed.name, 'New Handle Name');
    expect(changed.variations.single.price, '455');
  });

  test('repository archives and restores products without deleting them',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('crimson_catalogue_archive_');
    final repository = LocalCatalogueRepository(
      storeFile: File('${directory.path}\\catalogue_store.json'),
    );

    final product = ProductDraft(
      id: 'archive-product-1',
      name: 'Archive Test Handle',
      category: 'Cabinet Handles',
      subcategory: 'Monza',
      variations: const [
        VariationDraft(size: '160MM', finish: 'Gold', price: '405'),
      ],
    );
    await repository.upsertProduct(product);

    final archived = await repository.archiveProduct(product.id);
    final archivedProduct =
        archived.products.singleWhere((item) => item.id == product.id);

    expect(archivedProduct.isArchived, isTrue);
    expect(archivedProduct.archivedAt, isNotEmpty);
    expect(
        archived.products.where((item) => item.id == product.id), hasLength(1));

    final restored = await repository.restoreProduct(product.id);
    final restoredProduct =
        restored.products.singleWhere((item) => item.id == product.id);

    expect(restoredProduct.isArchived, isFalse);
    expect(restoredProduct.archivedAt, isEmpty);
  });

  test('catalogue state stores managed brands', () {
    const state = CatalogueState(
      brands: ['Crimson', 'Aditya'],
      categories: [
        CategoryDraft(name: 'Cabinet Handles', subcategories: ['Monza']),
      ],
    );

    final decoded = CatalogueState.fromJson(state.toJson());

    expect(decoded.brands, ['Crimson', 'Aditya']);
    expect(decoded.categories.single.name, 'Cabinet Handles');
  });

  test('repository merges product brands into managed brands', () async {
    final directory =
        await Directory.systemTemp.createTemp('crimson_catalogue_brands_');
    final repository = LocalCatalogueRepository(
      storeFile: File('${directory.path}\\catalogue_store.json'),
    );

    await repository.upsertProduct(
      ProductDraft(
        name: 'Brand Test Handle',
        category: 'Cabinet Handles',
        subcategory: 'Monza',
        brand: 'Crimson',
      ),
    );
    final state = await repository.upsertProduct(
      ProductDraft(
        name: 'Brand Test Lock',
        category: 'Locks',
        subcategory: 'Mortise',
        brand: 'Aditya',
      ),
    );

    expect(state.brands, containsAll(['Crimson', 'Aditya']));
  });

  test('bulk paste groups aluminium profile rows by group name', () {
    const paste = '''
GROUP NAME\tITEM NAME\tCATEGORY\tSUBCATEGORY\tBRAND\tFINISH\tSIZE\tPRICE
BIS-101 G PROFILE\t(BIS-101) G PROFILE BLACK\tALUMINIUM PROFILES \tG PROFILE \tCRIMSON\tBLACK\t10FT\t0
BIS HN 201 J PROFILE\t(BIS HN 201) J PROFILE CP FINISH\tALUMINIUM PROFILES \tJ PROFILE  \tCRIMSON\tCP\t10FT\t0
BIS HN 201 J PROFILE\t(BIS HN 201) J PROFILE REALGOLD CP\tALUMINIUM PROFILES \tJ PROFILE  \tCRIMSON\tREALGOLD\t10FT\t0
BIS HN 201 J PROFILE\t(BIS HN 201) J PROFILE SENT BLACK\tALUMINIUM PROFILES \tJ PROFILE  \tCRIMSON\tSENT BLACK\t10FT\t0
BIS HN 202 J PROFILE\t(BIS HN 202) J PROFILE BLACK MATT\tALUMINIUM PROFILES \tJ PROFILE  \tCRIMSON\tBLACK MATT\t10FT\t0
BIS HN 202 J PROFILE\t(BIS HN 202) J PROFILE ROSE GOLD\tALUMINIUM PROFILES \tJ PROFILE  \tCRIMSON\tROSE GOLD\t10FT\t0
BIS HN225\tBIS HN225 SENT BLACK (10 FIT)\tALUMINIUM PROFILES \tWARDROBE PROFILE\tCRIMSON\tBLACK\t10FT\t0
BIS HN230\tBIS HN230 SENT BLACK (10 FIT)\tALUMINIUM PROFILES \tWARDROBE PROFILE\tCRIMSON\tBLACK\t10FT\t0
BIS HN230\tBIS HN230 SENT RROSE GOLD (10 FIT)\tALUMINIUM PROFILES \tWARDROBE PROFILE\tCRIMSON\tRROSE GOLD\t10FT\t0
BIS SL-019 TRIPLE TRACK\t(BIS SL-019) TRIPAL TRACK (12 FIT)\tALUMINIUM PROFILES \tWARDROBE TRACK\tCRIMSON\tMATT\t12FT\t0
BIS SL-019 TRIPLE TRACK\t(BIS SL-019) TRIPAL TRACK (8 FIT)\tALUMINIUM PROFILES \tWARDROBE TRACK\tCRIMSON\tMATT\t8 FT\t0
''';

    final result = parseBulkPasteProducts(paste);
    final productNames =
        result.products.map((product) => product.name).toList();

    expect(result.errors, isEmpty);
    expect(productNames, [
      'BIS-101 G PROFILE',
      'BIS HN 201 J PROFILE',
      'BIS HN 202 J PROFILE',
      'BIS HN225',
      'BIS HN230',
      'BIS SL-019 TRIPLE TRACK',
    ]);
    expect(
      result.products
          .firstWhere((product) => product.name == 'BIS HN 201 J PROFILE')
          .variations,
      hasLength(3),
    );
    expect(
      result.products
          .firstWhere((product) => product.name == 'BIS SL-019 TRIPLE TRACK')
          .variations
          .map((item) => item.size),
      ['12FT', '8 FT'],
    );
    expect(result.categories.single.name, 'ALUMINIUM PROFILES');
    expect(result.categories.single.subcategories, [
      'G PROFILE',
      'J PROFILE',
      'WARDROBE PROFILE',
      'WARDROBE TRACK',
    ]);
  });

  test(
      'bulk paste falls back to subcategory as product name and skips duplicate variations',
      () {
    const paste = '''
CATEGORY\tSUBCATEGORY\tBRAND\tFINISH\tSIZE\tPRICE
ALUMINIUM PROFILES\tWARDROBE PROFILE\tCRIMSON\tBLACK\t10FT\t0
ALUMINIUM PROFILES\tWARDROBE PROFILE\tCRIMSON\tBLACK\t10FT\t0
ALUMINIUM PROFILES\tWARDROBE PROFILE\tCRIMSON\tROSE GOLD\t10FT\t0
''';

    final result = parseBulkPasteProducts(paste);

    expect(result.products, hasLength(1));
    expect(result.products.single.name, 'WARDROBE PROFILE');
    expect(result.products.single.variations, hasLength(2));
  });

  test('bulk paste detects wide size columns and skips unavailable prices', () {
    const paste = '''
INTERNAL PRODUCT ID\tGROUP NAME\tITEM NAME\tCATEGORY\tSUBCATEGORY\tBRAND\tFINISH\tKNOB\t96MM\t 160MM\t224MM\t288MM\t448MM
CR-PROD-000264\tW ASTHA\t\tCABINET HANDLES\tWELSET\tCRIMSON\tMATT BLACK\t195\t300\t495\t710\t885\t0
CR-PROD-000264\tW ASTHA\t\tCABINET HANDLES\tWELSET\tCRIMSON\tCOLA CHOCO\t195\t300\t495\t710\t885\t0
CR-PROD-000265\tW CARENS\t\tCABINET HANDLES\tWELSET\tCRIMSON\tBL GREY\t200\t315\t520\t690\t875\t1560
''';

    final result = parseBulkPasteProducts(paste);

    expect(result.errors, isEmpty);
    expect(result.format, BulkPasteImportFormat.widePriceMatrix);
    expect(result.products, hasLength(2));

    final astha = result.products.singleWhere(
      (product) => product.internalProductCode == 'CR-PROD-000264',
    );
    expect(astha.name, 'W ASTHA');
    expect(astha.variations, hasLength(10));
    expect(astha.sizeSpec, 'KNOB, 96MM, 160MM, 224MM, 288MM');
    expect(
      astha.variations.any(
        (variation) =>
            variation.finish == 'MATT BLACK' &&
            variation.size == '160MM' &&
            variation.price == '495.00',
      ),
      isTrue,
    );
    expect(astha.variations.any((variation) => variation.size == '448MM'),
        isFalse);

    final carens = result.products.singleWhere(
      (product) => product.internalProductCode == 'CR-PROD-000265',
    );
    expect(carens.variations, hasLength(6));
    expect(
      carens.variations
          .singleWhere(
            (variation) => variation.size == '448MM',
          )
          .price,
      '1560.00',
    );
  });

  test('full Welset wide matrix creates ten products and 91 variations', () {
    const paste = '''
INTERNAL PRODUCT ID\tGROUP NAME\tITEM NAME\tCATEGORY\tSUBCATEGORY\tBRAND\tFINISH\tKNOB\t96MM\t160MM\t224MM\t288MM\t448MM
CR-PROD-000264\tW ASTHA\t\tCABINET HANDLES\tWELSET\tCRIMSON\tMATT BLACK\t195\t300\t495\t710\t885\t0
CR-PROD-000264\tW ASTHA\t\tCABINET HANDLES\tWELSET\tCRIMSON\tCOLA CHOCO\t195\t300\t495\t710\t885\t0
CR-PROD-000265\tW CARENS\t\tCABINET HANDLES\tWELSET\tCRIMSON\tBL GREY\t200\t315\t520\t690\t875\t1560
CR-PROD-000265\tW CARENS\t\tCABINET HANDLES\tWELSET\tCRIMSON\tCOLA CHOCO\t200\t315\t520\t690\t875\t1560
CR-PROD-000265\tW CARENS\t\tCABINET HANDLES\tWELSET\tCRIMSON\tGOLD YELLOW\t200\t315\t520\t690\t875\t1560
CR-PROD-000266\tW CLAVIS\t\tCABINET HANDLES\tWELSET\tCRIMSON\tBL MATTE BLACK\t0\t300\t470\t615\t790\t0
CR-PROD-000266\tW CLAVIS\t\tCABINET HANDLES\tWELSET\tCRIMSON\tGOLD YELLOW\t0\t300\t470\t615\t790\t0
CR-PROD-000266\tW CLAVIS\t\tCABINET HANDLES\tWELSET\tCRIMSON\tREMBO ORANGE\t0\t300\t470\t615\t790\t0
CR-PROD-000267\tW TOKYO\t\tCABINET HANDLES\tWELSET\tCRIMSON\tMATT BLACK-BL\t0\t220\t315\t485\t655\t0
CR-PROD-000267\tW TOKYO\t\tCABINET HANDLES\tWELSET\tCRIMSON\tMET COLA-RG\t0\t220\t315\t485\t655\t0
CR-PROD-000268\tW JACKSON\t\tCABINET HANDLES\tWELSET\tCRIMSON\tBL BROWN\t0\t315\t510\t695\t890\t1600
CR-PROD-000268\tW JACKSON\t\tCABINET HANDLES\tWELSET\tCRIMSON\tREMBO BROWN\t0\t315\t510\t695\t890\t1600
CR-PROD-000269\tW LINE\t\tCABINET HANDLES\tWELSET\tCRIMSON\tBL GREY\t0\t310\t520\t690\t885\t0
CR-PROD-000269\tW LINE\t\tCABINET HANDLES\tWELSET\tCRIMSON\tREMBO\t0\t310\t520\t690\t885\t0
CR-PROD-000270\tW COMPSS\t\tCABINET HANDLES\tWELSET\tCRIMSON\tR/G\t0\t215\t360\t505\t645\t0
CR-PROD-000271\tW CONCIL\t\tCONCEALES HANDLES\tWELSET\tCRIMSON\tBL/GREY\t0\t370\t505\t705\t0\t0
CR-PROD-000271\tW CONCIL\t\tCONCEALES HANDLES\tWELSET\tCRIMSON\tGOLD YELLOW\t0\t370\t505\t705\t0\t0
CR-PROD-000272\tW FUL CONCIL\t\tCONCEALES HANDLES\tWELSET\tCRIMSON\tMATT B/A\t0\t305\t460\t605\t0\t0
CR-PROD-000272\tW FUL CONCIL\t\tCONCEALES HANDLES\tWELSET\tCRIMSON\tMATT BLACK\t0\t345\t510\t675\t0\t0
CR-PROD-000272\tW FUL CONCIL\t\tCONCEALES HANDLES\tWELSET\tCRIMSON\tSL\t0\t305\t460\t605\t0\t0
CR-PROD-000273\tSC47\t\tCABINET HANDLES\tWELSET\tCRIMSON\tBLACK\t0\t235\t465\t0\t700\t0
CR-PROD-000273\tSC47\t\tCABINET HANDLES\tWELSET\tCRIMSON\tSATIN\t0\t235\t465\t0\t700\t0
''';

    final result = parseBulkPasteProducts(paste);
    final variationCount = result.products.fold<int>(
      0,
      (sum, product) => sum + product.variations.length,
    );

    expect(result.errors, isEmpty);
    expect(result.format, BulkPasteImportFormat.widePriceMatrix);
    expect(result.products, hasLength(10));
    expect(variationCount, 91);
    expect(
      {
        for (final product in result.products)
          product.internalProductCode: product.variations.length,
      },
      {
        'CR-PROD-000264': 10,
        'CR-PROD-000265': 18,
        'CR-PROD-000266': 12,
        'CR-PROD-000267': 8,
        'CR-PROD-000268': 10,
        'CR-PROD-000269': 8,
        'CR-PROD-000270': 4,
        'CR-PROD-000271': 6,
        'CR-PROD-000272': 9,
        'CR-PROD-000273': 6,
      },
    );
  });
  test('bulk paste rejects tables with no supported price layout', () {
    const paste = '''
GROUP NAME\tCATEGORY\tSUBCATEGORY\tBRAND\tFINISH
Unsafe Product\tHandles\tTest\tCrimson\tBlack
''';

    final result = parseBulkPasteProducts(paste);

    expect(result.products, isEmpty);
    expect(result.errors.single, contains('Unsupported table layout'));
    expect(result.format, BulkPasteImportFormat.unknown);
  });
  test('xlsx export and import uses the same bulk product rules', () async {
    final directory =
        await Directory.systemTemp.createTemp('crimson_xlsx_roundtrip_');
    final path = '${directory.path}\\catalogue.xlsx';
    final io = XlsxCatalogueIo();
    final products = [
      ProductDraft(
        name: 'BIS HN 201 J PROFILE',
        category: 'ALUMINIUM PROFILES',
        subcategory: 'J PROFILE',
        brand: 'CRIMSON',
        variations: const [
          VariationDraft(
              finish: 'CP',
              size: '10FT',
              price: '0.00',
              notes: 'Source: CP ITEM'),
          VariationDraft(finish: 'REALGOLD', size: '10FT', price: '0.00'),
        ],
      ),
    ];

    io.exportProducts(path: path, products: products);
    final result = io.importProducts(path);

    expect(File(path).existsSync(), isTrue);
    expect(result.errors, isEmpty);
    expect(result.products, hasLength(1));
    expect(result.products.single.name, 'BIS HN 201 J PROFILE');
    expect(result.products.single.variations.map((item) => item.finish),
        ['CP', 'REALGOLD']);
  });

  test('legacy importer reads Flutter JSON catalogue backups', () async {
    final directory =
        await Directory.systemTemp.createTemp('crimson_legacy_json_');
    final path = '${directory.path}\\catalogue_store.json';
    final state = CatalogueState(
      products: [
        ProductDraft(
          id: 'legacy-json-1',
          name: 'Legacy Handle',
          category: 'Cabinet Handles',
          subcategory: 'Monza',
          brand: 'Crimson',
          variations: const [
            VariationDraft(size: '160MM', finish: 'Rose Gold', price: '405'),
          ],
        ),
      ],
      categories: const [
        CategoryDraft(name: 'Cabinet Handles', subcategories: ['Monza']),
      ],
    );
    await File(path).writeAsString(jsonEncode(state.toJson()));

    final result = await const LegacyCatalogueImporter().importFromFile(path);

    expect(result.errors, isEmpty);
    expect(result.products.single.name, 'Legacy Handle');
    expect(result.products.single.variations.single.finish, 'Rose Gold');
    expect(result.categories.single.subcategories, ['Monza']);
  });

  test('catalogue search finds products by variation finish size and notes',
      () {
    final products = [
      ProductDraft(
        name: '1400 Handle',
        sku: 'H-1400',
        category: 'Cabinet Handles',
        subcategory: 'Monza',
        brand: 'Crimson',
        notes: 'Premium handle',
        variations: const [
          VariationDraft(size: '160MM', finish: 'Rose Gold', price: '405'),
          VariationDraft(size: '224MM', finish: 'Black', price: '575'),
        ],
      ),
      ProductDraft(
        name: 'Wardrobe Track',
        category: 'Aluminium Profiles',
        subcategory: 'Wardrobe Track',
        brand: 'Crimson',
        variations: const [
          VariationDraft(size: '12FT', finish: 'Matt', price: '0'),
        ],
      ),
    ];

    final byFinish = filterCatalogueProducts(
      products,
      const CatalogueProductFilter(query: 'rose gold'),
    );
    final bySize = filterCatalogueProducts(
      products,
      const CatalogueProductFilter(query: '12ft'),
    );

    expect(byFinish.single.name, '1400 Handle');
    expect(bySize.single.name, 'Wardrobe Track');
  });

  test('smart search understands finish size category and synonyms', () {
    final products = [
      ProductDraft(
        name: '1400 Handle',
        category: 'Cabinet Handles',
        subcategory: 'Monza',
        brand: 'Crimson',
        variations: const [
          VariationDraft(finish: 'Matt Black', size: '4"', price: '250'),
          VariationDraft(finish: 'Rose Gold', size: '160MM', price: '405'),
        ],
      ),
      ProductDraft(
        name: 'Glass Bracket',
        category: 'Glass Bracket',
        subcategory: 'Main',
        brand: 'Crimson',
        variations: const [
          VariationDraft(finish: 'SS', size: '96MM', price: '100'),
        ],
      ),
    ];

    final matches = filterCatalogueProducts(
      products,
      const CatalogueProductFilter(query: 'black 4 inch handle'),
    );

    expect(matches.map((product) => product.name), ['1400 Handle']);
  });

  test('smart search finds product and category keywords', () {
    final products = [
      ProductDraft(
        name: 'Premium Door Bolt',
        category: 'Towerbolt',
        subcategory: 'Main',
        keywords: const ['chitkani', 'sliding bolt'],
        variations: const [
          VariationDraft(finish: 'SS', size: '8"', price: '180')
        ],
      ),
    ];
    const categories = [
      CategoryDraft(
        name: 'Towerbolt',
        subcategories: ['Main'],
        keywords: ['door latch'],
      ),
    ];

    expect(
      filterCatalogueProducts(
        products,
        const CatalogueProductFilter(query: 'chitkani'),
        categories: categories,
      ),
      hasLength(1),
    );
    expect(
      filterCatalogueProducts(
        products,
        const CatalogueProductFilter(query: 'door latch'),
        categories: categories,
      ),
      hasLength(1),
    );
  });
  test('catalogue filters by category brand finish size and price range', () {
    final products = [
      ProductDraft(
        name: '1400 Handle',
        category: 'Cabinet Handles',
        subcategory: 'Monza',
        brand: 'Crimson',
        variations: const [
          VariationDraft(size: '160MM', finish: 'Rose Gold', price: '405'),
          VariationDraft(size: '224MM', finish: 'Black', price: '575'),
        ],
      ),
      ProductDraft(
        name: 'Budget Handle',
        category: 'Cabinet Handles',
        subcategory: 'Basic',
        brand: 'Other',
        variations: const [
          VariationDraft(size: '96MM', finish: 'Black', price: '120'),
        ],
      ),
    ];

    final result = filterCatalogueProducts(
      products,
      const CatalogueProductFilter(
        category: 'Cabinet Handles',
        brand: 'Crimson',
        finish: 'Black',
        size: '224MM',
        minPrice: 500,
        maxPrice: 600,
      ),
    );

    expect(result.single.name, '1400 Handle');
  });

  test('premium export html includes product and price matrix', () {
    final product = ProductDraft(
      name: '1425 Handle',
      category: 'Cabinet Handles',
      subcategory: 'Monza',
      brand: 'Crimson',
      finishColor: 'Rose Gold',
      variations: const [
        VariationDraft(size: '160MM', finish: 'Rose Gold', price: '405'),
        VariationDraft(size: '224MM', finish: 'Rose Gold', price: '575'),
      ],
    );

    final html =
        const PremiumExportService().buildProductSpotlightHtml(product);

    expect(html, contains('1425 HANDLE'));
    expect(html, contains('PRICE VARIATIONS'));
    expect(html, contains('160MM'));
    expect(html, contains('Rs. 405'));
    expect(html, contains('www.mycrimson.in'));
    expect(html, contains('@crimson.decor'));
    expect(html, contains('+91 89278 78935'));
    expect(html, isNot(contains('www.crimson.in')));
    expect(html, isNot(contains('+91 98765 43210')));
  });

  test('premium export creates a real PDF file', () async {
    final directory =
        await Directory.systemTemp.createTemp('crimson_pdf_export_');
    final path = '${directory.path}\\product-spotlight.pdf';
    final product = ProductDraft(
      name: 'W Astha',
      category: 'Cabinet Handles',
      subcategory: 'Welset',
      brand: 'Crimson',
      variations: const [
        VariationDraft(size: '96MM', finish: 'Matt Black', price: '300'),
      ],
    );

    await const PremiumExportService().exportProductSpotlightPdf(
      product: product,
      path: path,
    );

    final file = File(path);
    expect(await file.exists(), isTrue);
    expect(await file.length(), greaterThan(1000));
    final header = await file.openRead(0, 4).fold<List<int>>(
      <int>[],
      (bytes, chunk) => bytes..addAll(chunk),
    );
    expect(String.fromCharCodes(header), '%PDF');
  });

  test('product image storage copies images into managed folder', () async {
    final directory =
        await Directory.systemTemp.createTemp('crimson_image_storage_');
    final source = File('${directory.path}\\source photo.jpg');
    await source.writeAsBytes([1, 2, 3, 4, 5]);

    final storage = ProductImageStorage(
      imagesDirectory: Directory('${directory.path}\\managed_images'),
    );

    final copiedPath = await storage.copyIntoManagedFolder(
      sourcePath: source.path,
      productName: '1400 Handle',
    );

    expect(copiedPath, contains('managed_images'));
    expect(copiedPath, contains('1400_Handle'));
    expect(await File(copiedPath).exists(), isTrue);
    expect(await File(copiedPath).readAsBytes(), [1, 2, 3, 4, 5]);
  });

  test('catalogue backup round trip preserves products and variation order',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('crimson_catalogue_backup_');
    final path = '${directory.path}\\catalogue-backup.json';
    final source = CatalogueState(
      products: [
        ProductDraft(
          id: 'product-1',
          name: '1400 Handle',
          category: 'Cabinet Handles',
          subcategory: 'Monza',
          variations: const [
            VariationDraft(size: '224MM', finish: 'Gold', price: '575'),
            VariationDraft(size: '96MM', finish: 'Gold', price: '250'),
          ],
        ),
      ],
      categories: const [
        CategoryDraft(name: 'Cabinet Handles', subcategories: ['Monza']),
      ],
      brands: const ['Crimson'],
    );

    const service = CatalogueBackupService();
    await service.exportBackup(state: source, path: path);
    final restored = await service.readBackup(path);

    expect(restored.products.single.id, 'product-1');
    expect(
      restored.products.single.variations.map((item) => item.size).toList(),
      ['224MM', '96MM'],
    );
    expect(restored.categories.single.subcategories, ['Monza']);
  });

  test('catalogue health scan reports catalogue maintenance issues', () {
    final products = [
      ProductDraft(
        name: 'Duplicate Handle',
        category: '',
        subcategory: 'Monza',
        imagePath: 'missing.jpg',
        variations: const [
          VariationDraft(size: '96MM', finish: 'Black', price: '0'),
        ],
      ),
      ProductDraft(
        name: ' duplicate  handle ',
        category: 'Handles',
        subcategory: '',
      ),
    ];

    final report = inspectCatalogueHealth(
      products,
      imageExists: (_) => false,
    );

    expect(report.duplicateNames, ['Duplicate Handle']);
    expect(report.missingCategories, ['Duplicate Handle']);
    expect(report.missingSubcategories, [' duplicate  handle ']);
    expect(report.productsWithoutVariations, [' duplicate  handle ']);
    expect(report.productsWithoutImages, [' duplicate  handle ']);
    expect(report.productsWithMissingImageFiles, ['Duplicate Handle']);
    expect(report.productsWithZeroPriceVariations, ['Duplicate Handle']);
  });

  test('catalogue state auto-assigns hidden internal product codes', () {
    final state = CatalogueState.fromJson({
      'products': [
        {
          'id': 'p1',
          'name': 'First Handle',
          'category': 'Handles',
          'subcategory': 'Main',
        },
        {
          'id': 'p2',
          'name': 'Second Handle',
          'category': 'Handles',
          'subcategory': 'Main',
        },
      ],
    });

    expect(state.products.map((product) => product.internalProductCode), [
      'CR-PROD-000001',
      'CR-PROD-000002',
    ]);
  });

  test('bulk import without internal code updates same product name', () async {
    final directory = await Directory.systemTemp
        .createTemp('crimson_import_update_without_code_');
    final repository = LocalCatalogueRepository(
      storeFile: File('${directory.path}\\catalogue_store.json'),
    );
    await repository.save(CatalogueState(products: [
      ProductDraft(
        id: 'existing-handle',
        internalProductCode: 'CR-PROD-000010',
        name: '1400 Handle',
        category: 'Auto Towerbolt',
        subcategory: 'Old',
        imagePath: 'old-image.png',
        imagePaths: const ['old-image.png'],
        imageRevision: 2,
        variations: const [
          VariationDraft(size: '160MM', finish: 'Gold', price: '405'),
        ],
      ),
    ]));

    const paste = '''
GROUP NAME	ITEM NAME	CATEGORY	SUBCATEGORY	BRAND	FINISH	SIZE	PRICE
1400 Handle	1400 RG 160	Towerbolt	Main	Crimson	Rose Gold	160MM	455
''';
    final parsed = parseBulkPasteProducts(paste);
    final state = await repository.importProducts(
      incomingProducts: parsed.products,
      incomingCategories: parsed.categories,
    );
    final product = state.products.singleWhere(
      (item) => item.internalProductCode == 'CR-PROD-000010',
    );

    expect(state.products.where((product) => product.name == '1400 Handle'),
        hasLength(1));
    expect(product.id, 'existing-handle');
    expect(product.category, 'Towerbolt');
    expect(product.subcategory, 'Main');
    expect(product.imagePath, 'old-image.png');
    expect(product.imagePaths, ['old-image.png']);
    expect(product.imageRevision, 2);
    expect(product.variations.single.price, '455.00');
  });

  test('bulk import without internal code merges same-name duplicates',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('crimson_import_merge_without_code_');
    final repository = LocalCatalogueRepository(
      storeFile: File('${directory.path}\\catalogue_store.json'),
    );
    await repository.save(CatalogueState(products: [
      ProductDraft(
        id: 'auto-cambolt',
        internalProductCode: 'CR-PROD-000030',
        name: 'CAMBOLT',
        category: 'AUTO TOWERBOLT',
        subcategory: 'AUTO',
        imagePath: 'cambolt.png',
        imagePaths: const ['cambolt.png'],
        variations: const [
          VariationDraft(size: '6MM', finish: 'SS', price: '100'),
        ],
      ),
      ProductDraft(
        id: 'tower-cambolt',
        internalProductCode: 'CR-PROD-000031',
        name: 'CAMBOLT',
        category: 'TOWERBOLT',
        subcategory: 'MAIN',
        variations: const [
          VariationDraft(size: '8MM', finish: 'SS', price: '120'),
        ],
      ),
    ]));

    const paste = '''
GROUP NAME	ITEM NAME	CATEGORY	SUBCATEGORY	BRAND	FINISH	SIZE	PRICE
CAMBOLT	CAMBOLT SS 10MM	TOWERBOLT	MAIN	Crimson	SS	10MM	150
''';
    final parsed = parseBulkPasteProducts(paste);
    final state = await repository.importProducts(
      incomingProducts: parsed.products,
      incomingCategories: parsed.categories,
    );
    final products = state.products.where((item) => item.name == 'CAMBOLT');
    final product = products.single;

    expect(products, hasLength(1));
    expect(product.id, 'auto-cambolt');
    expect(product.internalProductCode, 'CR-PROD-000030');
    expect(product.category, 'TOWERBOLT');
    expect(product.imagePath, 'cambolt.png');
    expect(product.variations.single.size, '10MM');
    expect(product.variations.single.price, '150.00');
  });

  test(
      'bulk import with internal code updates exact product and preserves images',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('crimson_import_update_by_code_');
    final repository = LocalCatalogueRepository(
      storeFile: File('${directory.path}\\catalogue_store.json'),
    );
    await repository.save(CatalogueState(products: [
      ProductDraft(
        id: 'existing-handle',
        internalProductCode: 'CR-PROD-000020',
        name: '1400 Handle',
        category: 'Cabinet Handles',
        subcategory: 'Monza',
        sku: 'KEEP-SKU',
        imagePath: 'old-image.png',
        imagePaths: const ['old-image.png'],
        imageFinishTags: const {'old-image.png': 'Gold'},
        imageRevision: 3,
        notes: 'Keep this product note.',
        isPublished: true,
        variations: const [
          VariationDraft(size: '160MM', finish: 'Gold', price: '405'),
        ],
      ),
    ]));

    const paste = '''
INTERNAL PRODUCT ID	GROUP NAME	ITEM NAME	CATEGORY	SUBCATEGORY	BRAND	FINISH	SIZE	PRICE
CR-PROD-000020	1400 Handle Updated	1400 RG 160	Cabinet Handles	Monza	Crimson	Rose Gold	160MM	455
''';
    final parsed = parseBulkPasteProducts(paste);
    final state = await repository.importProducts(
      incomingProducts: parsed.products,
      incomingCategories: parsed.categories,
    );
    final product = state.products.singleWhere(
      (item) => item.internalProductCode == 'CR-PROD-000020',
    );

    expect(state.products, hasLength(1));
    expect(product.id, 'existing-handle');
    expect(product.name, '1400 Handle Updated');
    expect(product.variations.single.price, '455.00');
    expect(product.sku, 'KEEP-SKU');
    expect(product.imagePath, 'old-image.png');
    expect(product.imagePaths, ['old-image.png']);
    expect(product.imageFinishTags, {'old-image.png': 'Gold'});
    expect(product.imageRevision, 3);
    expect(product.notes, 'Keep this product note.');
    expect(product.isPublished, isTrue);
  });

  test('xlsx export includes internal product id for admin update sheets',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('crimson_internal_code_xlsx_');
    final path = '${directory.path}\\catalogue.xlsx';
    final io = XlsxCatalogueIo();
    final products = [
      ProductDraft(
        internalProductCode: 'CR-PROD-000030',
        name: '1500 Handle',
        category: 'Cabinet Handles',
        subcategory: 'Monza',
        brand: 'Crimson',
        variations: const [
          VariationDraft(size: '128MM', finish: 'Black', price: '335'),
        ],
      ),
    ];

    io.exportProducts(path: path, products: products);
    final result = io.importProducts(path);

    expect(result.errors, isEmpty);
    expect(result.products.single.internalProductCode, 'CR-PROD-000030');
    expect(result.products.single.name, '1500 Handle');
    expect(result.products.single.variations.single.price, '335.00');
  });
  test('catalogue reset generation survives json round trip', () {
    final state = CatalogueState(
      resetGeneration: 'reset-12345',
      bannerImagePaths: const ['banner.png'],
      products: [
        ProductDraft(
          name: 'Fresh Product',
          category: 'Handles',
          subcategory: 'Monza',
        ),
      ],
    );

    final restored = CatalogueState.fromJson(state.toJson());

    expect(restored.resetGeneration, 'reset-12345');
    expect(restored.bannerImagePaths, ['banner.png']);
    expect(restored.products.single.name, 'Fresh Product');
  });
}
