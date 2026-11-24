import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/product_image_storage.dart';
import '../data/windows_file_dialogs.dart';
import '../domain/catalogue_models.dart';
import 'cached_catalogue_image.dart';

const _crimson = Color(0xFFC8102E);
const _crimsonLight = Color(0xFFFCE7EB);
const _background = Color(0xFFF7F8FA);
const _border = Color(0xFFE5E7EB);
const _textPrimary = Color(0xFF1C1C1E);
const _textSecondary = Color(0xFF6B7280);

enum _ManagerMode { categories, subcategories, brands }

class CatalogueManagerScreen extends StatefulWidget {
  const CatalogueManagerScreen({
    super.key,
    required this.state,
    required this.onSaveState,
    required this.onOpenProducts,
  });

  final CatalogueState state;
  final ValueChanged<CatalogueState> onSaveState;
  final VoidCallback onOpenProducts;

  @override
  State<CatalogueManagerScreen> createState() => _CatalogueManagerScreenState();
}

class _CatalogueManagerScreenState extends State<CatalogueManagerScreen> {
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _fileDialogs = const WindowsFileDialogs();
  final _imageStorage = ProductImageStorage();
  late CatalogueState _working;
  _ManagerMode _mode = _ManagerMode.categories;
  String _selectedKey = '';
  bool _savingImage = false;

  @override
  void initState() {
    super.initState();
    _working = _withDiscoveredTaxonomy(widget.state);
    _selectFirst();
  }

  @override
  void didUpdateWidget(covariant CatalogueManagerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.updatedAt != widget.state.updatedAt) {
      _working = _withDiscoveredTaxonomy(widget.state);
      if (!_items.any((item) => item.key == _selectedKey)) _selectFirst();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        final body = compact
            ? ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _header(compact: true),
                  const SizedBox(height: 14),
                  _modeSelector(),
                  const SizedBox(height: 14),
                  SizedBox(height: 330, child: _listPane()),
                  const SizedBox(height: 14),
                  _editorPane(),
                ],
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
                    child: _header(compact: false),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: _modeSelector(),
                  ),
                  const Divider(height: 22, color: _border),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 350,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(22, 0, 10, 18),
                            child: _listPane(),
                          ),
                        ),
                        const VerticalDivider(width: 1, color: _border),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 22, 18),
                            child: _editorPane(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
        return Container(
          decoration: BoxDecoration(
            color: _background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border),
          ),
          clipBehavior: Clip.antiAlias,
          child: body,
        );
      },
    );
  }

  Widget _header({required bool compact}) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _crimsonLight,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.account_tree_outlined, color: _crimson),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Manage catalogue',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: _textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const Text(
                'Edit names, images and structure without losing products.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _textSecondary),
              ),
            ],
          ),
        ),
        if (!compact)
          OutlinedButton.icon(
            onPressed: widget.onOpenProducts,
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('View products'),
          ),
      ],
    );
  }

  Widget _modeSelector() {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_ManagerMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _ManagerMode.categories,
                  icon: Icon(Icons.grid_view_rounded),
                  label: Text('Categories'),
                ),
                ButtonSegment(
                  value: _ManagerMode.subcategories,
                  icon: Icon(Icons.folder_outlined),
                  label: Text('Subcategories'),
                ),
                ButtonSegment(
                  value: _ManagerMode.brands,
                  icon: Icon(Icons.sell_outlined),
                  label: Text('Brands'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) {
                setState(() {
                  _mode = selection.first;
                  _search.clear();
                  _selectFirst();
                });
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: _addItem,
          icon: const Icon(Icons.add_rounded),
          label: Text(switch (_mode) {
            _ManagerMode.categories => 'Add category',
            _ManagerMode.subcategories => 'Add subcategory',
            _ManagerMode.brands => 'Add brand',
          }),
        ),
      ],
    );
  }

  Widget _listPane() {
    final duplicateCount = _duplicateGroups.length;
    final query = _normal(_search.text);
    final items = _items
        .where((item) => query.isEmpty || _normal(item.name).contains(query))
        .toList();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (duplicateCount > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: const Color(0xFFFFF7ED),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$duplicateCount possible duplicate ${duplicateCount == 1 ? 'group' : 'groups'}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search ${_mode.name}',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: _background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _border),
                ),
              ),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text('Nothing found.',
                        style: TextStyle(color: _textSecondary)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 7),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final selected = item.key == _selectedKey;
                      return Material(
                        color: selected ? _crimsonLight : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          onTap: () => _select(item),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected ? _crimson : _border,
                              ),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: 62,
                                    height: 48,
                                    child: _CatalogueCover(
                                      path: item.imagePath,
                                      fallbackIcon: item.icon,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _textPrimary,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item.subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (selected)
                                  const Icon(Icons.check_circle,
                                      color: _crimson, size: 20),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _editorPane() {
    final item = _selectedItem;
    if (item == null) {
      return Container(
        decoration: _panelDecoration(),
        child: const Center(child: Text('Select an item to edit.')),
      );
    }
    final similar = _items
        .where((other) =>
            other.key != item.key &&
            _canonical(other.name) == _canonical(item.name) &&
            (_mode != _ManagerMode.subcategories ||
                _same(other.categoryName, item.categoryName)))
        .toList();

    return Container(
      decoration: _panelDecoration(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Edit ${switch (_mode) {
                      _ManagerMode.categories => 'category',
                      _ManagerMode.subcategories => 'subcategory',
                      _ManagerMode.brands => 'brand',
                    }}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.inventory_2_outlined, size: 16),
                  label: Text('${item.productCount} products'),
                  side: const BorderSide(color: _border),
                  backgroundColor: Colors.white,
                ),
              ],
            ),
            const SizedBox(height: 16),
            AspectRatio(
              aspectRatio: 16 / 7,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: _CatalogueCover(
                  path: item.imagePath,
                  fallbackIcon: item.icon,
                  large: true,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _savingImage ? null : () => _changeImage(item),
                  icon: _savingImage
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(item.imagePath.isEmpty
                      ? 'Add cover image'
                      : 'Change image'),
                ),
                if (item.imagePath.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _removeImage(item),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Remove'),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: switch (_mode) {
                  _ManagerMode.categories => 'Category name',
                  _ManagerMode.subcategories => 'Subcategory name',
                  _ManagerMode.brands => 'Brand name',
                },
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            if (_mode != _ManagerMode.brands) ...[
              const SizedBox(height: 12),
              _PublishSwitchCard(
                published: _isPublished(item),
                label: _mode == _ManagerMode.categories
                    ? 'Visible to customers'
                    : 'Subcategory products visible to customers',
                description: _mode == _ManagerMode.categories
                    ? 'When hidden, customers cannot see this category or its products.'
                    : 'Customers still do not see subcategories, but products inside this subcategory can be hidden.',
                onChanged: (value) => _setPublished(item, value),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _rename(item),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save name'),
              ),
            ),
            if (similar.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.merge_type_rounded,
                            color: Color(0xFFD97706)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Possible duplicate found',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${similar.first.name} has ${similar.first.productCount} products. Merge it into ${item.name}.',
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: () => _confirmMerge(similar.first, item),
                      icon: const Icon(Icons.call_merge_rounded),
                      label: Text('Merge into ${item.name}'),
                    ),
                  ],
                ),
              ),
            ],
            if (_mode == _ManagerMode.categories) ...[
              const SizedBox(height: 22),
              const Divider(color: _border),
              const SizedBox(height: 12),
              Text(
                'Subcategories',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              for (final subcategory
                  in _categoryFor(item.name)?.subcategories ?? const <String>[])
                Material(
                  color: Colors.transparent,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: SizedBox(
                        width: 48,
                        height: 40,
                        child: _CatalogueCover(
                          path: _subcategoryImage(item.name, subcategory),
                          fallbackIcon: Icons.folder_outlined,
                        ),
                      ),
                    ),
                    title: Text(subcategory,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                        '${_subcategoryProductCount(item.name, subcategory)} products'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      setState(() {
                        _mode = _ManagerMode.subcategories;
                        _selectedKey = _subcategoryKey(item.name, subcategory);
                        _syncName();
                      });
                    },
                  ),
                ),
            ],
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(Icons.shield_outlined, color: Color(0xFF16A34A), size: 18),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Products, variations, prices and photos are retained when names are merged.',
                    style: TextStyle(color: _textSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _panelDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      );

  List<_ManagerItem> get _items {
    return switch (_mode) {
      _ManagerMode.categories => _working.categories.map((category) {
          final count = _categoryProductCount(category.name);
          return _ManagerItem(
            key: _normal(category.name),
            name: category.name,
            subtitle:
                '$count products | ${category.subcategories.length} subcategories',
            imagePath: _categoryImage(category.name),
            productCount: count,
            icon: Icons.category_outlined,
          );
        }).toList(),
      _ManagerMode.subcategories => [
          for (final category in _working.categories)
            for (final subcategory in category.subcategories)
              _ManagerItem(
                key: _subcategoryKey(category.name, subcategory),
                name: subcategory,
                subtitle:
                    '${category.name} | ${_subcategoryProductCount(category.name, subcategory)} products',
                imagePath: _subcategoryImage(category.name, subcategory),
                productCount:
                    _subcategoryProductCount(category.name, subcategory),
                icon: Icons.folder_outlined,
                categoryName: category.name,
              ),
        ],
      _ManagerMode.brands => _working.brands.map((brand) {
          final count = _brandProductCount(brand);
          return _ManagerItem(
            key: _normal(brand),
            name: brand,
            subtitle: '$count products',
            imagePath: _brandImage(brand),
            productCount: count,
            icon: Icons.sell_outlined,
          );
        }).toList(),
    }
      ..sort((a, b) => b.productCount.compareTo(a.productCount));
  }

  _ManagerItem? get _selectedItem {
    for (final item in _items) {
      if (item.key == _selectedKey) return item;
    }
    return null;
  }

  List<List<_ManagerItem>> get _duplicateGroups {
    final grouped = <String, List<_ManagerItem>>{};
    for (final item in _items) {
      final scope = _mode == _ManagerMode.subcategories
          ? '${_normal(item.categoryName)}\u001f'
          : '';
      grouped.putIfAbsent('$scope${_canonical(item.name)}', () => []).add(item);
    }
    return grouped.values.where((group) => group.length > 1).toList();
  }

  void _selectFirst() {
    final items = _items;
    _selectedKey = items.isEmpty ? '' : items.first.key;
    _syncName();
  }

  void _select(_ManagerItem item) {
    setState(() {
      _selectedKey = item.key;
      _syncName();
    });
  }

  void _syncName() => _name.text = _selectedItem?.name ?? '';

  Future<void> _addItem() async {
    final controller = TextEditingController();
    String selectedCategory =
        _working.categories.isEmpty ? '' : _working.categories.first.name;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add ${_mode.name.substring(0, _mode.name.length - 1)}'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_mode == _ManagerMode.subcategories) ...[
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      for (final category in _working.categories)
                        DropdownMenuItem(
                          value: category.name,
                          child: Text(category.name),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => selectedCategory = value ?? ''),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: switch (_mode) {
                      _ManagerMode.categories => 'Category name',
                      _ManagerMode.subcategories => 'Subcategory name',
                      _ManagerMode.brands => 'Brand name',
                    },
                  ),
                  onSubmitted: (value) => Navigator.pop(dialogContext, value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    final name = _clean(result ?? '');
    if (name.isEmpty) return;

    switch (_mode) {
      case _ManagerMode.categories:
        if (_working.categories.any((item) => _same(item.name, name))) {
          _message('Category already exists.');
          return;
        }
        _commit(_working.copyWith(
          categories: [..._working.categories, CategoryDraft(name: name)],
        ));
        _selectedKey = _normal(name);
      case _ManagerMode.subcategories:
        if (selectedCategory.isEmpty) return;
        final categories = _working.categories.map((category) {
          if (!_same(category.name, selectedCategory)) return category;
          if (category.subcategories.any((item) => _same(item, name))) {
            return category;
          }
          return category.copyWith(
            subcategories: [...category.subcategories, name],
            subcategoryPublished: {
              ...category.subcategoryPublished,
              name: false,
            },
          );
        }).toList();
        _commit(_working.copyWith(categories: categories));
        _selectedKey = _subcategoryKey(selectedCategory, name);
      case _ManagerMode.brands:
        if (_working.brands.any((item) => _same(item, name))) {
          _message('Brand already exists.');
          return;
        }
        _commit(_working.copyWith(brands: [..._working.brands, name]));
        _selectedKey = _normal(name);
    }
    setState(_syncName);
  }

  void _rename(_ManagerItem item) {
    final nextName = _clean(_name.text);
    if (nextName.isEmpty || _same(nextName, item.name)) return;
    if (_items
        .any((other) => other.key != item.key && _same(other.name, nextName))) {
      _message('That name already exists. Use Merge instead.');
      return;
    }
    final next = switch (_mode) {
      _ManagerMode.categories => _renameCategory(item.name, nextName),
      _ManagerMode.subcategories =>
        _renameSubcategory(item.categoryName, item.name, nextName),
      _ManagerMode.brands => _renameBrand(item.name, nextName),
    };
    _commit(next);
    _selectedKey = switch (_mode) {
      _ManagerMode.subcategories =>
        _subcategoryKey(item.categoryName, nextName),
      _ => _normal(nextName),
    };
    setState(_syncName);
    _message('Name updated across the catalogue.');
  }

  Future<void> _confirmMerge(_ManagerItem alias, _ManagerItem target) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Merge duplicate names?'),
            content: Text(
              '${alias.name} will become ${target.name}. All ${alias.productCount} linked products keep their photos, variations and prices.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.call_merge_rounded),
                label: const Text('Merge safely'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    final next = switch (_mode) {
      _ManagerMode.categories => _mergeCategories(alias.name, target.name),
      _ManagerMode.subcategories => _mergeSubcategories(
          target.categoryName,
          alias.name,
          target.name,
        ),
      _ManagerMode.brands => _mergeBrands(alias.name, target.name),
    };
    _commit(next);
    _selectedKey = target.key;
    setState(_syncName);
    _message('Merged successfully. No products were lost.');
  }

  Future<void> _changeImage(_ManagerItem item) async {
    setState(() => _savingImage = true);
    try {
      final paths = Platform.isAndroid
          ? (await const MethodChannel('com.mycrimson.cataloguestudio/storage')
                  .invokeListMethod<String>('pickImageFiles') ??
              const <String>[])
          : await _fileDialogs.pickImageFiles();
      if (paths.isEmpty) return;
      final copied = await _imageStorage.copyIntoManagedFolder(
        sourcePath: paths.first,
        productName: '${_mode.name}_${item.name}',
      );
      _setImage(item, copied);
    } on Object catch (error) {
      _message('Image could not be added: $error');
    } finally {
      if (mounted) setState(() => _savingImage = false);
    }
  }

  void _removeImage(_ManagerItem item) => _setImage(item, '');

  bool _isPublished(_ManagerItem item) {
    return switch (_mode) {
      _ManagerMode.categories => _categoryFor(item.name)?.isPublished ?? false,
      _ManagerMode.subcategories =>
        _categoryFor(item.categoryName)?.isSubcategoryPublished(item.name) ??
            false,
      _ManagerMode.brands => true,
    };
  }

  void _setPublished(_ManagerItem item, bool isPublished) {
    final next = switch (_mode) {
      _ManagerMode.categories => _working.copyWith(
          categories: _working.categories
              .map((category) => _same(category.name, item.name)
                  ? category.copyWith(isPublished: isPublished)
                  : category)
              .toList(),
        ),
      _ManagerMode.subcategories => _working.copyWith(
          categories: _working.categories.map((category) {
            if (!_same(category.name, item.categoryName)) return category;
            final published = Map<String, bool>.from(
              category.subcategoryPublished,
            )..removeWhere((key, _) => _same(key, item.name));
            published[item.name] = isPublished;
            return category.copyWith(subcategoryPublished: published);
          }).toList(),
        ),
      _ManagerMode.brands => _working,
    };
    _commit(next);
    setState(() {});
    _message(
        isPublished ? 'Published for customers.' : 'Hidden from customers.');
  }

  void _setImage(_ManagerItem item, String path) {
    final next = switch (_mode) {
      _ManagerMode.categories => _working.copyWith(
          categories: _working.categories
              .map((category) => _same(category.name, item.name)
                  ? category.copyWith(imagePath: path)
                  : category)
              .toList(),
        ),
      _ManagerMode.subcategories => _working.copyWith(
          categories: _working.categories.map((category) {
            if (!_same(category.name, item.categoryName)) return category;
            final images = Map<String, String>.from(category.subcategoryImages)
              ..removeWhere((key, _) => _same(key, item.name));
            if (path.isNotEmpty) images[item.name] = path;
            return category.copyWith(subcategoryImages: images);
          }).toList(),
        ),
      _ManagerMode.brands => _working.copyWith(
          brandImages: Map<String, String>.from(_working.brandImages)
            ..removeWhere((key, _) => _same(key, item.name))
            ..addAll(path.isEmpty ? const {} : {item.name: path}),
        ),
    };
    _commit(next);
    setState(() {});
    _message(path.isEmpty ? 'Cover image removed.' : 'Cover image saved.');
  }

  CatalogueState _renameCategory(String oldName, String nextName) {
    return _working.copyWith(
      products: _working.products
          .map((product) => _same(product.category, oldName)
              ? product.copyWith(category: nextName)
              : product)
          .toList(),
      categories: _working.categories
          .map((category) => _same(category.name, oldName)
              ? category.copyWith(name: nextName)
              : category)
          .toList(),
    );
  }

  CatalogueState _renameSubcategory(
      String categoryName, String oldName, String nextName) {
    return _working.copyWith(
      products: _working.products.map((product) {
        if (_same(product.category, categoryName) &&
            _same(product.subcategory, oldName)) {
          return product.copyWith(subcategory: nextName);
        }
        return product;
      }).toList(),
      categories: _working.categories.map((category) {
        if (!_same(category.name, categoryName)) return category;
        final images = Map<String, String>.from(category.subcategoryImages);
        final image = _mapValue(images, oldName);
        images.removeWhere((key, _) => _same(key, oldName));
        if (image.isNotEmpty) images[nextName] = image;
        final published = Map<String, bool>.from(category.subcategoryPublished);
        final wasPublished = category.isSubcategoryPublished(oldName);
        published.removeWhere((key, _) => _same(key, oldName));
        published[nextName] = wasPublished;
        return category.copyWith(
          subcategories: category.subcategories
              .map((name) => _same(name, oldName) ? nextName : name)
              .toList(),
          subcategoryImages: images,
          subcategoryPublished: published,
        );
      }).toList(),
    );
  }

  CatalogueState _renameBrand(String oldName, String nextName) {
    final images = Map<String, String>.from(_working.brandImages);
    final image = _mapValue(images, oldName);
    images.removeWhere((key, _) => _same(key, oldName));
    if (image.isNotEmpty) images[nextName] = image;
    return _working.copyWith(
      products: _working.products
          .map((product) => _same(product.brand, oldName)
              ? product.copyWith(brand: nextName)
              : product)
          .toList(),
      brands: _working.brands
          .map((brand) => _same(brand, oldName) ? nextName : brand)
          .toList(),
      brandImages: images,
    );
  }

  CatalogueState _mergeCategories(String aliasName, String targetName) {
    final alias = _categoryFor(aliasName);
    final target = _categoryFor(targetName);
    if (alias == null || target == null) return _working;
    final subcategories = _unique([
      ...target.subcategories,
      ...alias.subcategories,
    ]);
    final merged = target.copyWith(
      isPublished: target.isPublished || alias.isPublished,
      subcategories: subcategories,
      imagePath: target.imagePath.trim().isNotEmpty
          ? target.imagePath
          : alias.imagePath,
      subcategoryImages: {
        ...alias.subcategoryImages,
        ...target.subcategoryImages,
      },
      subcategoryPublished: {
        for (final subcategory in subcategories)
          subcategory: target.isSubcategoryPublished(subcategory) ||
              alias.isSubcategoryPublished(subcategory),
      },
    );
    return _working.copyWith(
      products: _working.products
          .map((product) => _same(product.category, aliasName)
              ? product.copyWith(category: targetName)
              : product)
          .toList(),
      categories: [
        for (final category in _working.categories)
          if (_same(category.name, targetName))
            merged
          else if (!_same(category.name, aliasName))
            category,
      ],
    );
  }

  CatalogueState _mergeSubcategories(
      String categoryName, String aliasName, String targetName) {
    return _working.copyWith(
      products: _working.products.map((product) {
        if (_same(product.category, categoryName) &&
            _same(product.subcategory, aliasName)) {
          return product.copyWith(subcategory: targetName);
        }
        return product;
      }).toList(),
      categories: _working.categories.map((category) {
        if (!_same(category.name, categoryName)) return category;
        final images = Map<String, String>.from(category.subcategoryImages);
        final aliasPublished = category.isSubcategoryPublished(aliasName);
        final targetPublished = category.isSubcategoryPublished(targetName);
        final aliasImage = _mapValue(images, aliasName);
        final targetImage = _mapValue(images, targetName);
        images.removeWhere(
            (key, _) => _same(key, aliasName) || _same(key, targetName));
        final image = targetImage.isNotEmpty ? targetImage : aliasImage;
        if (image.isNotEmpty) images[targetName] = image;
        final published = Map<String, bool>.from(category.subcategoryPublished)
          ..removeWhere(
              (key, _) => _same(key, aliasName) || _same(key, targetName));
        published[targetName] = aliasPublished || targetPublished;
        return category.copyWith(
          subcategories: _unique([
            for (final name in category.subcategories)
              if (!_same(name, aliasName)) name,
            targetName,
          ]),
          subcategoryImages: images,
          subcategoryPublished: published,
        );
      }).toList(),
    );
  }

  CatalogueState _mergeBrands(String aliasName, String targetName) {
    final images = Map<String, String>.from(_working.brandImages);
    final aliasImage = _mapValue(images, aliasName);
    final targetImage = _mapValue(images, targetName);
    images.removeWhere(
        (key, _) => _same(key, aliasName) || _same(key, targetName));
    final image = targetImage.isNotEmpty ? targetImage : aliasImage;
    if (image.isNotEmpty) images[targetName] = image;
    return _working.copyWith(
      products: _working.products
          .map((product) => _same(product.brand, aliasName)
              ? product.copyWith(brand: targetName)
              : product)
          .toList(),
      brands: _unique([
        for (final brand in _working.brands)
          if (!_same(brand, aliasName)) brand,
        targetName,
      ]),
      brandImages: images,
    );
  }

  void _commit(CatalogueState state) {
    final next = state.copyWith(updatedAt: DateTime.now().toIso8601String());
    setState(() => _working = next);
    widget.onSaveState(next);
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  CategoryDraft? _categoryFor(String name) {
    for (final category in _working.categories) {
      if (_same(category.name, name)) return category;
    }
    return null;
  }

  String _categoryImage(String categoryName) {
    final saved = _categoryFor(categoryName)?.imagePath.trim() ?? '';
    if (saved.isNotEmpty) return saved;
    return _firstProductImage(
        (product) => _same(product.category, categoryName));
  }

  String _subcategoryImage(String categoryName, String subcategoryName) {
    final category = _categoryFor(categoryName);
    final saved = category == null
        ? ''
        : _mapValue(category.subcategoryImages, subcategoryName);
    if (saved.isNotEmpty) return saved;
    return _firstProductImage((product) =>
        _same(product.category, categoryName) &&
        _same(product.subcategory, subcategoryName));
  }

  String _brandImage(String brandName) {
    final saved = _mapValue(_working.brandImages, brandName);
    if (saved.isNotEmpty) return saved;
    return _firstProductImage((product) => _same(product.brand, brandName));
  }

  String _firstProductImage(bool Function(ProductDraft) matches) {
    for (final product in _working.products) {
      if (!matches(product)) continue;
      for (final path in [...product.imagePaths, product.imagePath]) {
        if (path.trim().isNotEmpty) return path.trim();
      }
    }
    return '';
  }

  int _categoryProductCount(String name) => _working.products
      .where((product) => !product.isArchived && _same(product.category, name))
      .length;

  int _subcategoryProductCount(String category, String subcategory) =>
      _working.products
          .where((product) =>
              !product.isArchived &&
              _same(product.category, category) &&
              _same(product.subcategory, subcategory))
          .length;

  int _brandProductCount(String name) => _working.products
      .where((product) => !product.isArchived && _same(product.brand, name))
      .length;

  CatalogueState _withDiscoveredTaxonomy(CatalogueState state) {
    final categories = [...state.categories];
    final brands = [...state.brands];
    for (final product in state.products) {
      final categoryName = _clean(product.category);
      final subcategoryName = _clean(product.subcategory);
      final brandName = _clean(product.brand);
      if (categoryName.isNotEmpty) {
        final index = categories
            .indexWhere((category) => _same(category.name, categoryName));
        if (index < 0) {
          categories.add(CategoryDraft(
            name: categoryName,
            subcategories:
                subcategoryName.isEmpty ? const [] : [subcategoryName],
          ));
        } else if (subcategoryName.isNotEmpty &&
            !categories[index]
                .subcategories
                .any((value) => _same(value, subcategoryName))) {
          categories[index] = categories[index].copyWith(
            subcategories: [
              ...categories[index].subcategories,
              subcategoryName,
            ],
          );
        }
      }
      if (brandName.isNotEmpty &&
          !brands.any((value) => _same(value, brandName))) {
        brands.add(brandName);
      }
    }
    return state.copyWith(categories: categories, brands: brands);
  }

  static String _subcategoryKey(String category, String subcategory) =>
      '${_normal(category)}\u001f${_normal(subcategory)}';

  static String _clean(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _normal(String value) => _clean(value).toLowerCase();

  static bool _same(String left, String right) =>
      _normal(left) == _normal(right);

  static String _canonical(String value) {
    var normalized = _normal(value).replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normalized.endsWith('ies') && normalized.length > 3) {
      normalized = '${normalized.substring(0, normalized.length - 3)}y';
    } else if (normalized.endsWith('s') &&
        !normalized.endsWith('ss') &&
        normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static List<String> _unique(Iterable<String> values) {
    final result = <String>[];
    for (final raw in values) {
      final value = _clean(raw);
      if (value.isNotEmpty && !result.any((item) => _same(item, value))) {
        result.add(value);
      }
    }
    return result;
  }

  static String _mapValue(Map<String, String> values, String key) {
    for (final entry in values.entries) {
      if (_same(entry.key, key)) return entry.value.trim();
    }
    return '';
  }
}

class _PublishSwitchCard extends StatelessWidget {
  const _PublishSwitchCard({
    required this.published,
    required this.label,
    required this.description,
    required this.onChanged,
  });

  final bool published;
  final String label;
  final String description;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: published ? const Color(0xFFECFDF5) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: published ? const Color(0xFFBBF7D0) : const Color(0xFFFED7AA),
        ),
      ),
      child: Row(
        children: [
          Icon(
            published
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color:
                published ? const Color(0xFF16A34A) : const Color(0xFFD97706),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(color: _textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(value: published, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ManagerItem {
  const _ManagerItem({
    required this.key,
    required this.name,
    required this.subtitle,
    required this.imagePath,
    required this.productCount,
    required this.icon,
    this.categoryName = '',
  });

  final String key;
  final String name;
  final String subtitle;
  final String imagePath;
  final int productCount;
  final IconData icon;
  final String categoryName;
}

class _CatalogueCover extends StatelessWidget {
  const _CatalogueCover({
    required this.path,
    required this.fallbackIcon,
    this.large = false,
  });

  final String path;
  final IconData fallbackIcon;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final cleanPath = path.trim();
    Widget fallback() => Container(
          color: Colors.white,
          alignment: Alignment.center,
          child: Icon(
            fallbackIcon,
            color: _crimson,
            size: large ? 54 : 26,
          ),
        );
    if (cleanPath.isEmpty) return fallback();
    if (cleanPath.startsWith('http://') || cleanPath.startsWith('https://')) {
      return Container(
        color: Colors.white,
        child: CachedCatalogueImage(
          url: cleanPath,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: large ? 720 : 360,
          fallbackBuilder: (_) => fallback(),
        ),
      );
    }
    final file = File(cleanPath);
    if (!file.existsSync()) return fallback();
    return Container(
      color: Colors.white,
      child: Image.file(
        file,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => fallback(),
      ),
    );
  }
}
