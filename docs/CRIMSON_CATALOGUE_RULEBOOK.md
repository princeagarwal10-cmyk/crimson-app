# Crimson Catalogue Rulebook

This document is the source of truth for rebuilding Crimson Catalogue Studio in Flutter.
The Flutter app must preserve these behaviours from the working Python desktop app.

## Product Master Rules

- A product has: name, SKU/code, category, subcategory, brand, size/specification, finish/color, selling price, image path, notes, images, and variations.
- Product name is required.
- Category is required and must already exist in the category master.
- Subcategory is required and must already exist under the selected category.
- SKU/code is optional, but when provided it must be unique case-insensitively.
- Manual product creation must reject duplicate product names case-insensitively.
- Import/bulk-add may update an existing product by matching product name case-insensitively.
- When import updates an existing product, the previous product is updated instead of creating a duplicate.
- Product selling price should be the minimum valid variation price when imported from a variation table.

## Category And Subcategory Rules

- Users cannot freely type categories in the product form.
- Categories must be added in the category manager first.
- Subcategories must belong to a category.
- Product form should only allow selecting existing categories and subcategories.
- Import/bulk-add can ensure missing categories/subcategories exist before saving imported products.

## Variation Rules

- A variation has: size, finish, price, variation SKU, notes, and sort order.
- Blank variation rows are ignored.
- A variation is valid when it has at least size or finish.
- Blank size is allowed when the product has finish-only variations.
- Blank finish is allowed when the product has size-only variations.
- Price must parse as a valid numeric amount.
- Saved variation order must match the imported/manual order.
- Price matrix display must preserve first-seen size order and first-seen finish order.
- Size and finish values are not alphabetically resorted for the matrix.
- Matrix blank labels display as `-` unless the export/render path intentionally skips blank labels.

## Price Matrix Rules

- A price matrix is displayed as finishes in rows and sizes in columns.
- The first column is always finish.
- Size columns are shown in the exact order first encountered.
- Finish rows are shown in the exact order first encountered.
- A matrix cell shows the compact price for that finish/size.
- If multiple variations share the same finish/size pair, prices are joined with ` / `.
- Empty matrix cells display `-`.
- If there are many size columns, the UI/export may split the matrix into column groups, but the order must remain unchanged.
- Compact price formatting removes decimals for whole numbers and keeps two decimals for fractional values.

## Supported Paste / Excel Import Formats

### 1. Product Price Table

Header example:

`ITEM NAME | CATEGORY | SUBCATEGORY | BRAND | FINISH | KNOB | 96MM | 160MM | 224MM | 288MM`

Rules:

- `ITEM NAME`, `CATEGORY`, `SUBCATEGORY`, and `FINISH` are required.
- Any non-empty header after `FINISH` becomes a size column.
- Each row represents one finish.
- Each non-blank price cell creates one variation.
- `-` is treated as blank and skipped.
- Repeated item rows are grouped into one product.
- Product name is the item name.
- Product category/subcategory/brand come from the row.
- Product size/specification, finish/color, and image path are cleared because variations carry size/finish.

### 2. Simple Finish Price Table

Header example:

`ITEM NAME | CATEGORY | SUBCATEGORY | BRAND | FINISH | PRICE`

Rules:

- `ITEM NAME`, `CATEGORY`, `SUBCATEGORY`, `FINISH`, and `PRICE` are required.
- `PRICE` is not treated as a size column.
- Each row creates one finish-only variation with blank size.
- Repeated item rows are grouped into one product.
- Product selling price is the minimum variation price.

### 3. Group Name Variation Rows

Header example:

`GROUP NAME | ITEM NAME | CATEGORY | SUBCATEGORY | BRAND | FINISH | SIZE | PRICE`

Rules:

- Either `GROUP NAME` or `ITEM NAME` is required.
- `CATEGORY`, `SUBCATEGORY`, `FINISH`, `SIZE`, and `PRICE` columns must exist.
- Size values may be blank.
- Product name is `GROUP NAME` when present, otherwise `ITEM NAME`.
- `ITEM NAME` can contain messy size text, but the app uses the explicit `SIZE` column for the variation size.
- Rows with the same group/name/category/subcategory/brand/notes are grouped into one product.
- Product selling price is the minimum variation price.

## Header Alias Rules

- `ITEM NAME`, `PRODUCT NAME`, and `NAME` map to product name.
- `SKU`, `CODE`, and `PRODUCT CODE` map to SKU/code.
- `SUB CATEGORY` maps to subcategory.
- `FINISH`, `COLOR`, and `COLOUR` map to finish/color when used as product fields.
- In price-table import, `FINISH` is the variation finish column.
- `PRICE`, `SELLING PRICE`, and common price aliases map to price only when the importer format expects price.

## Image Rules

- Product images are stored in the app-managed images folder.
- Product image records preserve sort order.
- The first image becomes the main product image.
- Duplicate image paths for a product are removed while preserving first occurrence.
- Missing image files should not break the catalogue; the UI shows a graceful placeholder.

## Search And Filter Rules

- Search should match product name, SKU/code, category, subcategory, brand, size/specification, finish/color, notes, variation size, variation finish, variation SKU, and variation notes.
- Category, subcategory, brand, size, finish, minimum price, and maximum price filters must work across product fields and variation rows.
- Search suggestions include product names and SKU/codes.

## Export Rules

- Product preview and share image/PDF should show product image first, then product identity, then variation matrix.
- SKU and subcategory can be hidden in customer-facing catalogue exports when requested.
- Blank variation size/finish labels should be hidden or represented cleanly in customer-facing exports.
- Multi-product catalogue PDFs should use compact matrix tables to avoid very long list-style pages.

## Cloud Rules For Later

- Flutter V1 starts local-first.
- Supabase is added only after local catalogue behaviour matches the Python app.
- Existing Python desktop app remains the daily master until Flutter reaches feature parity.
- When cloud sync is added, it must preserve product IDs/mappings, variation order, image order, category/subcategory relationships, and duplicate-name update behaviour.

## Acceptance Tests To Port To Flutter

- Duplicate SKU is rejected.
- Manual duplicate product name is rejected.
- Import with existing product name updates the existing product.
- Product update rejects duplicate name.
- Multiple images are stored in order.
- Multiple size/finish variations save in order.
- Variation matrix preserves imported row/column order.
- Product price table groups repeated item rows.
- Simple finish price table does not treat `PRICE` as size.
- Group-name rows group messy item names into one product.
- Blank size is allowed for group-name rows.
- Excel/product paste import accepts all three supported formats.
