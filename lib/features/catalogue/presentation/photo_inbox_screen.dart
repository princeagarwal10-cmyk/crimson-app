import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/product_image_storage.dart';
import '../data/windows_file_dialogs.dart';
import '../domain/catalogue_models.dart';

/// A separate workspace for photos that do not yet have catalogue details.
class PhotoInboxScreen extends StatefulWidget {
  const PhotoInboxScreen({
    super.key,
    required this.state,
    required this.onSaveState,
    required this.onResolveImage,
    this.onCheckCloudReady,
  });

  final CatalogueState state;
  final Future<void> Function(CatalogueState) onSaveState;
  final Future<File> Function(String) onResolveImage;
  final Future<bool> Function()? onCheckCloudReady;

  @override
  State<PhotoInboxScreen> createState() => _PhotoInboxScreenState();
}

class _PhotoInboxScreenState extends State<PhotoInboxScreen> {
  final _selected = <String>{};
  final _imageStorage = ProductImageStorage();
  final _fileDialogs = const WindowsFileDialogs();
  bool _busy = false;
  bool? _cloudReady;

  @override
  void initState() {
    super.initState();
    _checkCloudReady();
  }

  Future<void> _checkCloudReady() async {
    if (widget.onCheckCloudReady == null) {
      _cloudReady = true;
      return;
    }
    setState(() => _cloudReady = null);
    final ready = await widget.onCheckCloudReady!();
    if (mounted) setState(() => _cloudReady = ready);
  }

  List<PhotoInboxDraft> get _active => widget.state.photoInbox
      .where((draft) => draft.isActive && draft.images.isNotEmpty)
      .toList();

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<List<PhotoInboxImage>> _pickPhotos() async {
    final paths = Platform.isAndroid
        ? (await const MethodChannel('com.mycrimson.cataloguestudio/storage')
                .invokeListMethod<String>('pickImageFiles') ??
            const <String>[])
        : await _fileDialogs.pickImageFiles();
    final images = <PhotoInboxImage>[];
    for (final path in paths) {
      final copied = await _imageStorage.copyIntoManagedFolder(
        sourcePath: path,
        productName: 'photo_inbox',
      );
      images.add(PhotoInboxImage(path: copied));
    }
    return images;
  }

  Future<void> _upload() async {
    if (_busy || _cloudReady != true) return;
    setState(() => _busy = true);
    try {
      final images = await _pickPhotos();
      if (images.isEmpty) return;
      final next = widget.state.copyWith(photoInbox: [
        ...widget.state.photoInbox,
        for (final image in images) PhotoInboxDraft(images: [image]),
      ]);
      await widget.onSaveState(next);
      _message('${images.length} photo${images.length == 1 ? '' : 's'} added.');
    } on Object catch (error) {
      _message('Photos saved locally; cloud sync needs attention: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _groupSelected() async {
    final selected =
        _active.where((draft) => _selected.contains(draft.id)).toList();
    if (selected.length < 2) return;
    final target = selected.first;
    final joinedImages = [
      for (final draft in selected) ...draft.images,
    ];
    final next = widget.state.copyWith(photoInbox: [
      for (final draft in widget.state.photoInbox)
        if (draft.id == target.id)
          draft.copyWith(images: joinedImages)
        else if (_selected.contains(draft.id))
          draft.copyWith(mergedIntoDraftId: target.id)
        else
          draft,
    ]);
    try {
      await widget.onSaveState(next);
      setState(() {
        _selected.clear();
        _selected.add(target.id);
      });
      _message('${joinedImages.length} images grouped as one product draft.');
    } on Object catch (error) {
      _message('Group saved locally; cloud sync needs attention: $error');
    }
  }

  Future<void> _editDraft(PhotoInboxDraft draft) async {
    final edited = await showDialog<PhotoInboxDraft>(
      context: context,
      builder: (context) => _PhotoInboxEditor(
        draft: draft,
        categories: widget.state.categories,
        onResolveImage: widget.onResolveImage,
        onPickPhotos: _pickPhotos,
      ),
    );
    if (edited == null) return;
    final next = widget.state.copyWith(photoInbox: [
      for (final item in widget.state.photoInbox)
        item.id == draft.id ? edited : item,
    ]);
    try {
      await widget.onSaveState(next);
      _message('Draft saved.');
    } on Object catch (error) {
      _message('Draft saved locally; cloud sync needs attention: $error');
    }
  }

  Future<void> _showComingSoon(PhotoInboxDraft draft) async {
    final categoryName = draft.category.trim();
    final category = widget.state.categories.where(
        (item) => item.name.trim().toLowerCase() == categoryName.toLowerCase());
    if (categoryName.isEmpty ||
        category.isEmpty ||
        !category.first.isPublished ||
        !category.first.isSubcategoryPublished(draft.subcategory)) {
      _message(
          'Choose a visible category and subcategory before showing this product.');
      return;
    }
    final duplicate = widget.state.products.any((product) =>
        !product.isArchived &&
        draft.name.trim().isNotEmpty &&
        product.name.trim().toLowerCase() == draft.name.trim().toLowerCase() &&
        product.category.trim().toLowerCase() == categoryName.toLowerCase());
    if (duplicate) {
      _message('This product already exists. Use Attach to add its photos.');
      return;
    }
    setState(() => _busy = true);
    try {
      final resolved = <String>[];
      for (final image in draft.images) {
        final file = await widget.onResolveImage(image.path);
        if (!file.existsSync()) throw StateError('A draft photo is missing.');
        resolved.add(file.path);
      }
      if (resolved.isEmpty) return;
      final shortId = draft.id.length > 6
          ? draft.id.substring(draft.id.length - 6).toUpperCase()
          : draft.id.toUpperCase();
      final product = ProductDraft(
        name: draft.name.trim().isEmpty
            ? 'Coming Soon $shortId'
            : draft.name.trim(),
        category: categoryName,
        subcategory: draft.subcategory.trim(),
        brand: draft.brand.trim(),
        // Inbox notes remain admin-only in the private photo record.
        notes: '',
        finishColor: draft.images
            .map((image) => image.finish.trim())
            .where((finish) => finish.isNotEmpty)
            .toSet()
            .join(', '),
        imagePath: resolved.first,
        imagePaths: resolved,
        imageFinishTags: {
          for (var i = 0; i < resolved.length; i++)
            if (draft.images[i].finish.trim().isNotEmpty)
              resolved[i]: draft.images[i].finish.trim(),
        },
        isComingSoon: true,
      );
      final next = widget.state.copyWith(
        products: [...widget.state.products, product],
        photoInbox: [
          for (final item in widget.state.photoInbox)
            item.id == draft.id
                ? item.copyWith(convertedProductId: product.id)
                : item,
        ],
      );
      await widget.onSaveState(next);
      setState(() => _selected.remove(draft.id));
      _message('Product now appears as Coming Soon in $categoryName.');
    } on Object catch (error) {
      _message('Check the product list and cloud sync status: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attachToProduct(PhotoInboxDraft draft) async {
    final products = widget.state.products
        .where((item) => !item.isArchived)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (products.isEmpty) {
      _message('Add a product first, or show this draft as Coming Soon.');
      return;
    }
    final product = await showDialog<ProductDraft>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Attach photos to product'),
        children: [
          SizedBox(
            width: 440,
            height: 400,
            child: ListView.builder(
              itemCount: products.length,
              itemBuilder: (context, index) => ListTile(
                title: Text(products[index].name),
                subtitle: Text(products[index].category),
                onTap: () => Navigator.pop(context, products[index]),
              ),
            ),
          ),
        ],
      ),
    );
    if (product == null) return;
    setState(() => _busy = true);
    try {
      final paths = [...product.imagePaths];
      final tags = {...product.imageFinishTags};
      for (final image in draft.images) {
        final file = await widget.onResolveImage(image.path);
        if (!file.existsSync()) throw StateError('A draft photo is missing.');
        if (!paths.contains(file.path)) paths.add(file.path);
        if (image.finish.trim().isNotEmpty) {
          tags[file.path] = image.finish.trim();
        }
      }
      final updated = product.copyWith(
        imagePath: paths.isEmpty ? product.imagePath : paths.first,
        imagePaths: paths,
        imageFinishTags: tags,
        imageRevision: DateTime.now().microsecondsSinceEpoch,
      );
      final next = widget.state.copyWith(
        products: [
          for (final item in widget.state.products)
            item.id == product.id ? updated : item,
        ],
        photoInbox: [
          for (final item in widget.state.photoInbox)
            item.id == draft.id
                ? item.copyWith(convertedProductId: product.id)
                : item,
        ],
      );
      await widget.onSaveState(next);
      _message('Photos attached to ${product.name}.');
    } on Object catch (error) {
      _message('Check the product list and cloud sync status: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drafts = _active;
    return Scaffold(
      appBar: AppBar(title: const Text('Photo Inbox')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Upload photos now. Group them and add product details later.',
                style: Theme.of(context).textTheme.bodyMedium),
            if (_cloudReady != true) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: Text(_cloudReady == null
                        ? 'Checking private photo storage...'
                        : 'Photo Inbox needs its private cloud setup before uploads can start. Existing catalogue tools remain available.')),
                if (_cloudReady == false)
                  TextButton(
                      onPressed: _checkCloudReady, child: const Text('Retry')),
              ]),
            ],
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: _busy || _cloudReady != true ? null : _upload,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Upload Photos'),
              ),
              OutlinedButton.icon(
                onPressed: _busy || _cloudReady != true || _selected.length < 2
                    ? null
                    : _groupSelected,
                icon: const Icon(Icons.collections_outlined),
                label: const Text('Group Selected'),
              ),
            ]),
            const SizedBox(height: 16),
            Expanded(
              child: drafts.isEmpty
                  ? const Center(
                      child: Text(
                          'No unassigned photos. Upload pictures to begin.'))
                  : LayoutBuilder(builder: (context, constraints) {
                      final columns = constraints.maxWidth < 600
                          ? 2
                          : constraints.maxWidth < 1000
                              ? 3
                              : 5;
                      return GridView.builder(
                        itemCount: drafts.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.72,
                        ),
                        itemBuilder: (context, index) {
                          final draft = drafts[index];
                          return Card(
                            child: Column(children: [
                              Expanded(
                                  child: Stack(children: [
                                Positioned.fill(
                                    child: _InboxPhoto(
                                  path: draft.images.first.path,
                                  onResolveImage: widget.onResolveImage,
                                )),
                                Positioned(
                                    top: 4,
                                    left: 4,
                                    child: Checkbox(
                                      value: _selected.contains(draft.id),
                                      onChanged: (value) => setState(() {
                                        if (value == true) {
                                          _selected.add(draft.id);
                                        } else {
                                          _selected.remove(draft.id);
                                        }
                                      }),
                                    )),
                              ])),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(children: [
                                  Text(
                                      draft.name.trim().isEmpty
                                          ? 'Photo draft'
                                          : draft.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  Text(
                                      '${draft.images.length} image${draft.images.length == 1 ? '' : 's'}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                  Wrap(
                                      alignment: WrapAlignment.center,
                                      children: [
                                        TextButton(
                                            onPressed:
                                                _busy || _cloudReady != true
                                                    ? null
                                                    : () => _editDraft(draft),
                                            child: const Text('Details')),
                                        TextButton(
                                            onPressed: _busy ||
                                                    _cloudReady != true
                                                ? null
                                                : () => _showComingSoon(draft),
                                            child: const Text('Coming Soon')),
                                        TextButton(
                                            onPressed: _busy ||
                                                    _cloudReady != true
                                                ? null
                                                : () => _attachToProduct(draft),
                                            child: const Text('Attach')),
                                      ]),
                                ]),
                              ),
                            ]),
                          );
                        },
                      );
                    }),
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxPhoto extends StatelessWidget {
  const _InboxPhoto({required this.path, required this.onResolveImage});

  final String path;
  final Future<File> Function(String) onResolveImage;

  @override
  Widget build(BuildContext context) => FutureBuilder<File>(
        future: onResolveImage(path),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: Icon(Icons.image_outlined, size: 44));
          }
          return Image.file(snapshot.data!,
              fit: BoxFit.contain,
              cacheWidth: 480,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image_outlined));
        },
      );
}

class _PhotoInboxEditor extends StatefulWidget {
  const _PhotoInboxEditor({
    required this.draft,
    required this.categories,
    required this.onResolveImage,
    required this.onPickPhotos,
  });

  final PhotoInboxDraft draft;
  final List<CategoryDraft> categories;
  final Future<File> Function(String) onResolveImage;
  final Future<List<PhotoInboxImage>> Function() onPickPhotos;

  @override
  State<_PhotoInboxEditor> createState() => _PhotoInboxEditorState();
}

class _PhotoInboxEditorState extends State<_PhotoInboxEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.draft.name);
  late final TextEditingController _brand =
      TextEditingController(text: widget.draft.brand);
  late final TextEditingController _notes =
      TextEditingController(text: widget.draft.notes);
  late final List<PhotoInboxImage> _images = [...widget.draft.images];
  late String _category = widget.draft.category;
  late String _subcategory = widget.draft.subcategory;

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoryMatches =
        widget.categories.where((item) => item.name == _category);
    final subcategories = categoryMatches.isEmpty
        ? <String>[]
        : categoryMatches.first.subcategories;
    return AlertDialog(
      title: const Text('Photo product draft'),
      content: SizedBox(
        width: 620,
        height: 600,
        child: ListView(children: [
          TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Product name (can be added later)',
              )),
          DropdownButtonFormField<String>(
            initialValue:
                widget.categories.any((item) => item.name == _category)
                    ? _category
                    : null,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final item in widget.categories)
                DropdownMenuItem(value: item.name, child: Text(item.name))
            ],
            onChanged: (value) => setState(() {
              _category = value ?? '';
              _subcategory = '';
            }),
          ),
          DropdownButtonFormField<String>(
            initialValue:
                subcategories.contains(_subcategory) ? _subcategory : null,
            decoration: const InputDecoration(labelText: 'Subcategory'),
            items: [
              for (final item in subcategories)
                DropdownMenuItem(value: item, child: Text(item))
            ],
            onChanged: (value) => setState(() => _subcategory = value ?? ''),
          ),
          TextField(
              controller: _brand,
              decoration: const InputDecoration(labelText: 'Brand')),
          TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              try {
                final added = await widget.onPickPhotos();
                if (mounted) {
                  setState(() => _images.addAll(added));
                }
              } on Object catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not add photos: $error')));
                }
              }
            },
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Add More Photos'),
          ),
          for (var i = 0; i < _images.length; i++)
            Card(
                child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                SizedBox(
                    width: 90,
                    height: 80,
                    child: _InboxPhoto(
                        path: _images[i].path,
                        onResolveImage: widget.onResolveImage)),
                const SizedBox(width: 12),
                Expanded(
                    child: TextFormField(
                  initialValue: _images[i].finish,
                  decoration:
                      const InputDecoration(labelText: 'Finish / colour'),
                  onChanged: (value) =>
                      _images[i] = _images[i].copyWith(finish: value),
                )),
                IconButton(
                  tooltip: 'Remove from this draft',
                  onPressed: _images.length <= 1
                      ? null
                      : () => setState(() => _images.removeAt(i)),
                  icon: const Icon(Icons.close),
                ),
              ]),
            )),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(
                context,
                widget.draft.copyWith(
                  name: _name.text.trim(),
                  category: _category,
                  subcategory: _subcategory,
                  brand: _brand.text.trim(),
                  notes: _notes.text.trim(),
                  images: _images,
                )),
            child: const Text('Save Draft')),
      ],
    );
  }
}
