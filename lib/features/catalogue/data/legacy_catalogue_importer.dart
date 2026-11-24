import 'dart:convert';
import 'dart:io';

import '../domain/catalogue_models.dart';
import 'xlsx_catalogue_io.dart';

class LegacyCatalogueImporter {
  const LegacyCatalogueImporter();

  Future<BulkPasteImportResult> importFromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return BulkPasteImportResult(
        products: const [],
        categories: const [],
        errors: ['Legacy file not found: $path'],
      );
    }

    final extension = _extension(path);
    if (extension == '.xlsx') {
      return XlsxCatalogueIo().importProducts(path);
    }
    if (extension == '.json') {
      return _importJson(file);
    }
    if (extension == '.db' ||
        extension == '.sqlite' ||
        extension == '.sqlite3') {
      return _importSqliteWithPython(path);
    }

    return const BulkPasteImportResult(
      products: [],
      categories: [],
      errors: [
        'Unsupported legacy file. Select .db, .sqlite, .sqlite3, .json or .xlsx.'
      ],
    );
  }

  BulkPasteImportResult _importJson(File file) {
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map && decoded['products'] is List) {
        final state =
            CatalogueState.fromJson(Map<String, Object?>.from(decoded));
        return BulkPasteImportResult(
          products: state.products,
          categories: state.categories,
          errors: const [],
        );
      }
      if (decoded is List) {
        return BulkPasteImportResult(
          products: decoded
              .whereType<Map>()
              .map((item) =>
                  ProductDraft.fromJson(Map<String, Object?>.from(item)))
              .toList(),
          categories: const [],
          errors: const [],
        );
      }
      return const BulkPasteImportResult(
        products: [],
        categories: [],
        errors: ['JSON file does not contain a products list.'],
      );
    } on Object catch (error) {
      return BulkPasteImportResult(
        products: const [],
        categories: const [],
        errors: ['Could not read JSON import: $error'],
      );
    }
  }

  Future<BulkPasteImportResult> _importSqliteWithPython(String path) async {
    final result = await Process.run(
      'python',
      ['-c', _sqliteExportScript, path],
      runInShell: false,
    );

    if (result.exitCode != 0) {
      return BulkPasteImportResult(
        products: const [],
        categories: const [],
        errors: [
          'Could not read old desktop database. Python reported: ${result.stderr}'
        ],
      );
    }

    try {
      final decoded = jsonDecode(result.stdout.toString());
      if (decoded is! Map) {
        return const BulkPasteImportResult(
          products: [],
          categories: [],
          errors: ['Old desktop database export was not valid.'],
        );
      }
      final products = ((decoded['products'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => ProductDraft.fromJson(Map<String, Object?>.from(item)))
          .toList();
      final categories = ((decoded['categories'] as List?) ?? const [])
          .whereType<Map>()
          .map(
              (item) => CategoryDraft.fromJson(Map<String, Object?>.from(item)))
          .toList();
      final errors = ((decoded['errors'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList();

      return BulkPasteImportResult(
        products: products,
        categories: categories,
        errors: errors,
      );
    } on Object catch (error) {
      return BulkPasteImportResult(
        products: const [],
        categories: const [],
        errors: ['Could not parse old desktop database export: $error'],
      );
    }
  }

  String _extension(String path) {
    final index = path.lastIndexOf('.');
    if (index < 0) return '';
    return path.substring(index).toLowerCase();
  }
}

const _sqliteExportScript = r'''
import json
import sqlite3
import sys
from pathlib import Path

db_path = Path(sys.argv[1])
legacy_root = db_path.parent.parent if db_path.parent.name.lower() == "data" else db_path.parent
errors = []

def has_table(con, name):
    row = con.execute(
        "select 1 from sqlite_master where type='table' and name=?",
        (name,),
    ).fetchone()
    return row is not None

def text(value):
    return "" if value is None else str(value).strip()

def price(value):
    try:
        return f"{float(value or 0):.2f}"
    except Exception:
        return "0.00"

def resolve_image(value):
    raw = text(value)
    if not raw:
        return ""
    image_path = Path(raw)
    if image_path.is_absolute():
        return str(image_path)
    candidates = [
        legacy_root / image_path,
        db_path.parent / image_path,
        Path.cwd() / image_path,
    ]
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    return str((legacy_root / image_path).resolve())

con = sqlite3.connect(str(db_path))
con.row_factory = sqlite3.Row

categories = []
if has_table(con, "categories"):
    subcategories_by_category = {}
    if has_table(con, "subcategories"):
        for row in con.execute(
            "select category_id, name from subcategories order by category_id, name"
        ):
            subcategories_by_category.setdefault(row["category_id"], []).append(text(row["name"]))
    for row in con.execute("select id, name from categories order by name"):
        categories.append({
            "name": text(row["name"]),
            "subcategories": subcategories_by_category.get(row["id"], []),
        })

variations_by_product = {}
if has_table(con, "product_variations"):
    for row in con.execute(
        "select product_id, size, finish, price, sku, notes "
        "from product_variations order by product_id, sort_order, id"
    ):
        variations_by_product.setdefault(row["product_id"], []).append({
            "size": text(row["size"]),
            "finish": text(row["finish"]),
            "price": price(row["price"]),
            "sku": text(row["sku"]),
            "notes": text(row["notes"]),
        })

images_by_product = {}
if has_table(con, "product_images"):
    for row in con.execute(
        "select product_id, image_path from product_images order by product_id, sort_order, id"
    ):
        image = resolve_image(row["image_path"])
        if image and image not in images_by_product.setdefault(row["product_id"], []):
            images_by_product[row["product_id"]].append(image)

products = []
if not has_table(con, "products"):
    errors.append("Old database does not contain a products table.")
else:
    for row in con.execute(
        "select id, name, sku, category, subcategory, brand, size_spec, "
        "finish_color, selling_price, image_path, notes, archived "
        "from products order by name, id"
    ):
        product_id = row["id"]
        image_paths = list(images_by_product.get(product_id, []))
        main_image = resolve_image(row["image_path"])
        if main_image and main_image not in image_paths:
            image_paths.insert(0, main_image)
        products.append({
            "id": f"legacy-{product_id}",
            "name": text(row["name"]),
            "sku": text(row["sku"]),
            "category": text(row["category"]),
            "subcategory": text(row["subcategory"]),
            "brand": text(row["brand"]),
            "sizeSpec": text(row["size_spec"]),
            "finishColor": text(row["finish_color"]),
            "sellingPrice": price(row["selling_price"]),
            "imagePath": image_paths[0] if image_paths else "",
            "notes": text(row["notes"]),
            "imagePaths": image_paths,
            "variations": variations_by_product.get(product_id, []),
            "isArchived": bool(row["archived"] or 0),
            "archivedAt": "",
        })

con.close()
print(json.dumps({
    "products": products,
    "categories": categories,
    "errors": errors,
}, ensure_ascii=False))
''';
