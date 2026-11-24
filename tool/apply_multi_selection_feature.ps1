$ErrorActionPreference = 'Stop'

function Replace-One([string]$Text, [string]$Old, [string]$New, [string]$Label) {
  $Text = $Text.Replace("`r`n", "`n")
  $Old = $Old.Replace("`r`n", "`n")
  $New = $New.Replace("`r`n", "`n")
  $count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
  if ($count -ne 1) { throw "$Label expected once, found $count" }
  return $Text.Replace($Old, $New)
}

$root = Split-Path -Parent $PSScriptRoot
$mainPath = Join-Path $root 'lib\main.dart'
$text = Get-Content -LiteralPath $mainPath -Raw

$text = Replace-One $text @'
import 'features/catalogue/data/premium_export_service.dart';
'@ @'
import 'features/catalogue/data/premium_export_service.dart';
import 'features/catalogue/data/multi_product_export_service.dart';
'@ 'multi export import'

$text = Replace-One $text @'
import 'features/catalogue/domain/catalogue_models.dart';
'@ @'
import 'features/catalogue/domain/catalogue_models.dart';
import 'features/catalogue/domain/catalogue_selection.dart';
import 'features/catalogue/presentation/catalogue_selection_bar.dart';
'@ 'selection imports'

$text = $text.Replace("const kCrimsonAppVersionName = '1.0.24';", "const kCrimsonAppVersionName = '1.0.25';")
$text = $text.Replace('const kCrimsonAppVersionCode = 25;', 'const kCrimsonAppVersionCode = 26;')

$text = Replace-One $text @'
  String _category = '';
  String _subcategory = '';
'@ @'
  String _category = '';
  String _subcategory = '';
  final Set<String> _selectedProductIds = {};
  final _multiExportService = const MultiProductExportService();
  bool _exportingSelection = false;
'@ 'mobile selection fields'

$text = Replace-One $text @'
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        if (showCategoryBrowser)
'@ @'
        if (_selectedProductIds.isNotEmpty ||
            (!showCategoryBrowser && !showSubcategoryBrowser))
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: CatalogueSelectionBar(
                selectedCount: _selectedProductIds.length,
                visibleCount: filtered.length,
                busy: _exportingSelection,
                compact: true,
                onSelectAll: () => _toggleMobileSelectionGroup(
                  filtered.map((product) => product.id),
                ),
                onClear: () => setState(_selectedProductIds.clear),
                onExportImage: _exportMobileCatalogueImages,
                onExportPdf: _exportMobileCataloguePdf,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        if (showCategoryBrowser)
'@ 'mobile selection bar'

$text = Replace-One $text @'
              return _MobileBrowseCard(
                icon: Icons.category_outlined,
                imagePath: summary.imagePath,
                title: summary.name,
                subtitle: '${summary.productCount} products',
                onTap: () => setState(() {
'@ @'
              final ids = productIdsForCategory(products, summary.name);
              return _MobileBrowseCard(
                icon: Icons.category_outlined,
                imagePath: summary.imagePath,
                title: summary.name,
                subtitle: '${summary.productCount} products',
                selected: isSelectionGroupComplete(_selectedProductIds, ids),
                onSelectionToggle: () => _toggleMobileSelectionGroup(ids),
                onTap: () => setState(() {
'@ 'mobile category selection'

$text = Replace-One $text @'
                return _MobileBrowseCard(
                  icon: Icons.inventory_2_outlined,
                  imagePath: selectedCategoryDraft?.imagePath ?? '',
                  title: 'All $_category',
                  subtitle: '${categoryProducts.length} products',
                  onTap: () => setState(() => _subcategory = '__all__'),
'@ @'
                final ids = categoryProducts.map((product) => product.id);
                return _MobileBrowseCard(
                  icon: Icons.inventory_2_outlined,
                  imagePath: selectedCategoryDraft?.imagePath ?? '',
                  title: 'All $_category',
                  subtitle: '${categoryProducts.length} products',
                  selected: isSelectionGroupComplete(_selectedProductIds, ids),
                  onSelectionToggle: () => _toggleMobileSelectionGroup(ids),
                  onTap: () => setState(() => _subcategory = '__all__'),
'@ 'mobile all category selection'

$text = Replace-One $text @'
              final summary = subcategories[index - 1];
              return _MobileBrowseCard(
                icon: Icons.folder_outlined,
                imagePath: summary.imagePath,
                title: summary.name,
                subtitle: '${summary.productCount} products',
                onTap: () => setState(() => _subcategory = summary.name),
'@ @'
              final summary = subcategories[index - 1];
              final ids = productIdsForSubcategory(
                products,
                category: _category,
                subcategory: summary.name,
              );
              return _MobileBrowseCard(
                icon: Icons.folder_outlined,
                imagePath: summary.imagePath,
                title: summary.name,
                subtitle: '${summary.productCount} products',
                selected: isSelectionGroupComplete(_selectedProductIds, ids),
                onSelectionToggle: () => _toggleMobileSelectionGroup(ids),
                onTap: () => setState(() => _subcategory = summary.name),
'@ 'mobile subcategory selection'

$text = Replace-One $text @'
              return _MobileProductCard(
                product: product,
                onTap: () => _openMobileProductDetail(
'@ @'
              return _MobileProductCard(
                product: product,
                selected: _selectedProductIds.contains(product.id),
                onSelectionToggle: () => _toggleMobileProduct(product.id),
                onTap: () => _openMobileProductDetail(
'@ 'mobile product selection'

$text = Replace-One $text @'
  Future<void> _showCategoryFilter(List<_CategorySummary> categories) async {
'@ @'
  void _toggleMobileProduct(String productId) {
    setState(() {
      final next = toggleProductSelection(_selectedProductIds, productId);
      _selectedProductIds
        ..clear()
        ..addAll(next);
    });
  }

  void _toggleMobileSelectionGroup(Iterable<String> productIds) {
    setState(() {
      final next = toggleSelectionGroup(_selectedProductIds, productIds);
      _selectedProductIds
        ..clear()
        ..addAll(next);
    });
  }

  List<ProductDraft> get _mobileSelectedProducts => widget.state.products
      .where((product) => _selectedProductIds.contains(product.id))
      .toList(growable: false);

  Future<void> _exportMobileCatalogueImages() async {
    await _runMobileSelectionExport(() async {
      final base = '${Directory.systemTemp.path}/crimson_selected_catalogue.png';
      final paths = await _multiExportService.exportImages(
        products: _mobileSelectedProducts,
        path: base,
      );
      await const MethodChannel('com.mycrimson.cataloguestudio/storage')
          .invokeMethod<void>('shareFiles', {
        'paths': paths,
        'mimeType': 'image/png',
        'title': 'Share Crimson catalogue images',
      });
    });
  }

  Future<void> _exportMobileCataloguePdf() async {
    await _runMobileSelectionExport(() async {
      final base = '${Directory.systemTemp.path}/crimson_selected_page.png';
      final pages = await _multiExportService.exportImages(
        products: _mobileSelectedProducts,
        path: base,
      );
      final pdfPath = '${Directory.systemTemp.path}/Crimson_Selected_Catalogue.pdf';
      await const MethodChannel('com.mycrimson.cataloguestudio/storage')
          .invokeMethod<void>('createPdfFromImages', {
        'imagePaths': pages,
        'outputPath': pdfPath,
      });
      await const MethodChannel('com.mycrimson.cataloguestudio/storage')
          .invokeMethod<void>('shareFiles', {
        'paths': [pdfPath],
        'mimeType': 'application/pdf',
        'title': 'Share Crimson catalogue PDF',
      });
    });
  }

  Future<void> _runMobileSelectionExport(
      Future<void> Function() action) async {
    if (_exportingSelection || _mobileSelectedProducts.isEmpty) return;
    setState(() => _exportingSelection = true);
    try {
      await action();
    } on Object catch (error) {
      if (mounted) _showMessage(context, 'Catalogue export failed: $error');
    } finally {
      if (mounted) setState(() => _exportingSelection = false);
    }
  }

  Future<void> _showCategoryFilter(List<_CategorySummary> categories) async {
'@ 'mobile export methods'

$text = Replace-One $text @'
  const _MobileBrowseCard({
    required this.icon,
    this.imagePath = '',
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
'@ @'
  const _MobileBrowseCard({
    required this.icon,
    this.imagePath = '',
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.selected = false,
    this.onSelectionToggle,
  });
'@ 'mobile browse constructor'

$text = Replace-One $text @'
  final IconData icon;
  final String imagePath;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
'@ @'
  final IconData icon;
  final String imagePath;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool selected;
  final VoidCallback? onSelectionToggle;
'@ 'mobile browse fields'

$mobileBrowseStart = $text.IndexOf('class _MobileBrowseCard extends StatelessWidget')
$mobileBrowseEnd = $text.IndexOf('class _MobileAddProductScreen', $mobileBrowseStart)
$mobileBrowse = $text.Substring($mobileBrowseStart, $mobileBrowseEnd - $mobileBrowseStart)
$mobileBrowse = $mobileBrowse.Replace('        onTap: onTap,', "        onTap: onTap,`r`n        onLongPress: onSelectionToggle,")
$mobileBrowse = $mobileBrowse.Replace('border: Border.all(color: _CrimsonColors.border),', "border: Border.all(`r`n              color: selected ? _CrimsonColors.crimson : _CrimsonColors.border,`r`n              width: selected ? 2 : 1,`r`n            ),")
$mobileBrowse = $mobileBrowse.Replace(@'
                    const SizedBox(height: 3),
                    Text(
'@, @'
                    const SizedBox(height: 3),
                    Text(
'@)
$mobileBrowse = $mobileBrowse.Replace(@'
                    ),
                  ],
                ),
              ),
'@, @'
                    ),
                    if (onSelectionToggle != null) ...[
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: onSelectionToggle,
                        borderRadius: BorderRadius.circular(10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.add_circle_outline_rounded,
                              size: 18,
                              color: _CrimsonColors.crimson,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              selected ? 'Selected' : 'Select all',
                              style: const TextStyle(
                                color: _CrimsonColors.crimson,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
'@)
$text = $text.Substring(0, $mobileBrowseStart) + $mobileBrowse + $text.Substring($mobileBrowseEnd)

$text = Replace-One $text @'
  const _MobileProductCard({
    required this.product,
    required this.onTap,
  });

  final ProductDraft product;
  final VoidCallback onTap;
'@ @'
  const _MobileProductCard({
    required this.product,
    required this.onTap,
    required this.selected,
    required this.onSelectionToggle,
  });

  final ProductDraft product;
  final VoidCallback onTap;
  final bool selected;
  final VoidCallback onSelectionToggle;
'@ 'mobile product card props'

$mobileProductStart = $text.IndexOf('class _MobileProductCard extends StatelessWidget')
$mobileProductEnd = $text.IndexOf('class _MobileProductListTile', $mobileProductStart)
$mobileProduct = $text.Substring($mobileProductStart, $mobileProductEnd - $mobileProductStart)
$mobileProduct = $mobileProduct.Replace('        onTap: onTap,', "        onTap: onTap,`r`n        onLongPress: onSelectionToggle,")
$mobileProduct = $mobileProduct.Replace('border: Border.all(color: _CrimsonColors.border),', "border: Border.all(`r`n              color: selected ? _CrimsonColors.crimson : _CrimsonColors.border,`r`n              width: selected ? 2 : 1,`r`n            ),")
$mobileProduct = $mobileProduct.Replace(@'
                      Positioned.fill(
                        child: Container(
'@, @'
                      Positioned.fill(
                        child: Container(
'@)
$mobileProduct = $mobileProduct.Replace(@'
                      ),
                    ],
'@, @'
                      ),
                      Positioned(
                        top: 7,
                        right: 7,
                        child: IconButton.filledTonal(
                          tooltip: selected ? 'Remove selection' : 'Select product',
                          onPressed: onSelectionToggle,
                          icon: Icon(selected
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined),
                        ),
                      ),
                    ],
'@)
$text = $text.Substring(0, $mobileProductStart) + $mobileProduct + $text.Substring($mobileProductEnd)

$text = Replace-One $text @'
  String _sizeFilter = '';
  int _page = 0;
'@ @'
  String _sizeFilter = '';
  int _page = 0;
  final Set<String> _selectedProductIds = {};
  final _multiExportService = const MultiProductExportService();
  final _fileDialogs = const WindowsFileDialogs();
  bool _exportingSelection = false;
'@ 'desktop selection fields'

$text = Replace-One $text @'
              const SizedBox(height: 10),
              Expanded(
                child: showCategoryBrowser
'@ @'
              if (_selectedProductIds.isNotEmpty || showProductGrid) ...[
                const SizedBox(height: 8),
                CatalogueSelectionBar(
                  selectedCount: _selectedProductIds.length,
                  visibleCount: filteredProducts.length,
                  busy: _exportingSelection,
                  onSelectAll: () => _toggleDesktopSelectionGroup(
                    filteredProducts.map((product) => product.id),
                  ),
                  onClear: () => setState(_selectedProductIds.clear),
                  onExportImage: _exportDesktopCatalogueImages,
                  onExportPdf: _exportDesktopCataloguePdf,
                ),
              ],
              const SizedBox(height: 10),
              Expanded(
                child: showCategoryBrowser
'@ 'desktop selection bar'

$text = Replace-One $text @'
                        summaries: categoryStats
                            .where((summary) => summary.name.isNotEmpty)
                            .toList(),
                        onSelected: (category) {
'@ @'
                        summaries: categoryStats
                            .where((summary) => summary.name.isNotEmpty)
                            .toList(),
                        products: baseProducts,
                        selectedProductIds: _selectedProductIds,
                        onSelectionChanged: _toggleDesktopSelectionGroup,
                        onSelected: (category) {
'@ 'desktop category grid props'

$text = Replace-One $text @'
                            categoryProductCount:
                                selectedCategoryProducts.length,
                            onShowAllProducts: () {
'@ @'
                            categoryProductCount:
                                selectedCategoryProducts.length,
                            products: selectedCategoryProducts,
                            selectedProductIds: _selectedProductIds,
                            onSelectionChanged: _toggleDesktopSelectionGroup,
                            onShowAllProducts: () {
'@ 'desktop subcategory grid props'

$text = Replace-One $text @'
                                  return _ProductGridCard(
                                    product: product,
                                    selected: false,
                                    onTap: () => _openProduct(product),
                                  );
'@ @'
                                  return _ProductGridCard(
                                    product: product,
                                    selected: _selectedProductIds.contains(product.id),
                                    onSelectionToggle: () =>
                                        _toggleDesktopProduct(product.id),
                                    onTap: () => _openProduct(product),
                                  );
'@ 'desktop product card call'

$text = Replace-One $text @'
  void _handleSearchChanged() {
'@ @'
  void _toggleDesktopProduct(String productId) {
    setState(() {
      final next = toggleProductSelection(_selectedProductIds, productId);
      _selectedProductIds
        ..clear()
        ..addAll(next);
    });
  }

  void _toggleDesktopSelectionGroup(Iterable<String> productIds) {
    setState(() {
      final next = toggleSelectionGroup(_selectedProductIds, productIds);
      _selectedProductIds
        ..clear()
        ..addAll(next);
    });
  }

  List<ProductDraft> get _desktopSelectedProducts => widget.state.products
      .where((product) => _selectedProductIds.contains(product.id))
      .toList(growable: false);

  Future<void> _exportDesktopCatalogueImages() async {
    final products = _desktopSelectedProducts;
    if (products.isEmpty) return;
    final path = await _fileDialogs.pickPngSavePath(
      suggestedName: 'Crimson_Selected_Catalogue.png',
    );
    if (path == null) return;
    await _runDesktopSelectionExport(() async {
      final pages = await _multiExportService.exportImages(
        products: products,
        path: path,
      );
      if (mounted) {
        _showMessage(context,
            '${pages.length} catalogue image${pages.length == 1 ? '' : 's'} saved.');
      }
    });
  }

  Future<void> _exportDesktopCataloguePdf() async {
    final products = _desktopSelectedProducts;
    if (products.isEmpty) return;
    final path = await _fileDialogs.pickPdfSavePath(
      suggestedName: 'Crimson_Selected_Catalogue.pdf',
    );
    if (path == null) return;
    await _runDesktopSelectionExport(() async {
      await _multiExportService.exportPdf(products: products, path: path);
      if (mounted) _showMessage(context, 'Catalogue PDF saved: $path');
    });
  }

  Future<void> _runDesktopSelectionExport(
      Future<void> Function() action) async {
    if (_exportingSelection) return;
    setState(() => _exportingSelection = true);
    try {
      await action();
    } on Object catch (error) {
      if (mounted) _showMessage(context, 'Catalogue export failed: $error');
    } finally {
      if (mounted) setState(() => _exportingSelection = false);
    }
  }

  void _handleSearchChanged() {
'@ 'desktop export methods'

$text = Replace-One $text @'
  const _CategoryBrowseGrid({
    required this.summaries,
    required this.onSelected,
  });

  final List<_CategorySummary> summaries;
  final ValueChanged<String> onSelected;
'@ @'
  const _CategoryBrowseGrid({
    required this.summaries,
    required this.products,
    required this.selectedProductIds,
    required this.onSelectionChanged,
    required this.onSelected,
  });

  final List<_CategorySummary> summaries;
  final List<ProductDraft> products;
  final Set<String> selectedProductIds;
  final ValueChanged<Iterable<String>> onSelectionChanged;
  final ValueChanged<String> onSelected;
'@ 'category grid fields'

$text = Replace-One $text @'
        final summary = summaries[index];
        return _BrowseTile(
          icon: Icons.category_outlined,
'@ @'
        final summary = summaries[index];
        final ids = productIdsForCategory(products, summary.name);
        return _BrowseTile(
          icon: Icons.category_outlined,
'@ 'category grid ids'

$text = $text.Replace(@'
          badge: summary.productCount.toString(),
          onTap: () => onSelected(summary.name),
'@, @'
          badge: summary.productCount.toString(),
          selected: isSelectionGroupComplete(selectedProductIds, ids),
          onSelectionToggle: () => onSelectionChanged(ids),
          onTap: () => onSelected(summary.name),
'@)

$text = Replace-One $text @'
    required this.categoryProductCount,
    required this.onShowAllProducts,
    required this.onSelected,
'@ @'
    required this.categoryProductCount,
    required this.products,
    required this.selectedProductIds,
    required this.onSelectionChanged,
    required this.onShowAllProducts,
    required this.onSelected,
'@ 'subcategory constructor'

$text = Replace-One $text @'
  final int categoryProductCount;
  final VoidCallback onShowAllProducts;
  final ValueChanged<String> onSelected;
'@ @'
  final int categoryProductCount;
  final List<ProductDraft> products;
  final Set<String> selectedProductIds;
  final ValueChanged<Iterable<String>> onSelectionChanged;
  final VoidCallback onShowAllProducts;
  final ValueChanged<String> onSelected;
'@ 'subcategory fields'

$text = Replace-One $text @'
        if (index == 0) {
          return _BrowseTile(
'@ @'
        if (index == 0) {
          final ids = products.map((product) => product.id);
          return _BrowseTile(
'@ 'subcategory all ids'

$text = Replace-One $text @'
            badge: categoryProductCount.toString(),
            selected: true,
            onTap: onShowAllProducts,
'@ @'
            badge: categoryProductCount.toString(),
            selected: isSelectionGroupComplete(selectedProductIds, ids),
            onSelectionToggle: () => onSelectionChanged(ids),
            onTap: onShowAllProducts,
'@ 'subcategory all selection'

$text = Replace-One $text @'
        final summary = summaries[index - 1];
        return _BrowseTile(
'@ @'
        final summary = summaries[index - 1];
        final ids = productIdsForSubcategory(
          products,
          category: category,
          subcategory: summary.name,
        );
        return _BrowseTile(
'@ 'subcategory ids'


$text = Replace-One $text @'
    required this.badge,
    required this.onTap,
    this.selected = false,
'@ @'
    required this.badge,
    required this.onTap,
    this.selected = false,
    this.onSelectionToggle,
'@ 'browse tile constructor'

$text = Replace-One $text @'
  final String badge;
  final VoidCallback onTap;
  final bool selected;
'@ @'
  final String badge;
  final VoidCallback onTap;
  final bool selected;
  final VoidCallback? onSelectionToggle;
'@ 'browse tile fields'

$browseStart = $text.IndexOf('class _BrowseTile extends StatelessWidget')
$browseEnd = $text.IndexOf('class _ProductsPaginationBar', $browseStart)
$browse = $text.Substring($browseStart, $browseEnd - $browseStart)
$browse = $browse.Replace('        onTap: onTap,', "        onTap: onTap,`r`n        onLongPress: onSelectionToggle,")
$browse = $browse.Replace(@'
                    const SizedBox(width: 8),
                    _MiniChip(label: badge, selected: selected),
'@, @'
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: selected ? 'Remove selection' : 'Select all products',
                      onPressed: onSelectionToggle,
                      icon: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.add_circle_outline_rounded,
                        color: _CrimsonColors.crimson,
                      ),
                    ),
                    _MiniChip(label: badge, selected: selected),
'@)
$text = $text.Substring(0, $browseStart) + $browse + $text.Substring($browseEnd)

$text = Replace-One $text @'
  const _ProductGridCard({
    required this.product,
    required this.selected,
    required this.onTap,
  });

  final ProductDraft product;
  final bool selected;
  final VoidCallback onTap;
'@ @'
  const _ProductGridCard({
    required this.product,
    required this.selected,
    required this.onTap,
    required this.onSelectionToggle,
  });

  final ProductDraft product;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onSelectionToggle;
'@ 'desktop product card props'

$productCardStart = $text.IndexOf('class _ProductGridCard extends StatelessWidget')
$productCardEnd = $text.IndexOf('class _ProductRow', $productCardStart)
$productCard = $text.Substring($productCardStart, $productCardEnd - $productCardStart)
$productCard = $productCard.Replace('        onTap: onTap,', "        onTap: onTap,`r`n        onLongPress: onSelectionToggle,")
$productCard = $productCard.Replace(@'
                          child: const Icon(
                            Icons.favorite_border_rounded,
                            size: 15,
                            color: _CrimsonColors.textSecondary,
                          ),
'@, @'
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: selected ? 'Remove selection' : 'Select product',
                            onPressed: onSelectionToggle,
                            icon: Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined,
                              size: 18,
                              color: selected
                                  ? _CrimsonColors.crimson
                                  : _CrimsonColors.textSecondary,
                            ),
                          ),
'@)
$text = $text.Substring(0, $productCardStart) + $productCard + $text.Substring($productCardEnd)

Set-Content -LiteralPath $mainPath -Value $text -Encoding UTF8

$pubspecPath = Join-Path $root 'pubspec.yaml'
$pubspec = Get-Content -LiteralPath $pubspecPath -Raw
$pubspec = $pubspec.Replace('version: 1.0.24+25', 'version: 1.0.25+26')
Set-Content -LiteralPath $pubspecPath -Value $pubspec -Encoding UTF8

Write-Output 'Applied multi-product selection and catalogue export integration.'
