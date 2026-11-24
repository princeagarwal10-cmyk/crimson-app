import 'dart:io';

class ProductImageStorage {
  ProductImageStorage({Directory? imagesDirectory})
      : _imagesDirectory = imagesDirectory ?? _defaultImagesDirectory();

  final Directory _imagesDirectory;

  String get imagesPath => _imagesDirectory.path;

  Future<String> copyIntoManagedFolder({
    required String sourcePath,
    required String productName,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Product image not found', sourcePath);
    }

    await _imagesDirectory.create(recursive: true);

    final extension = _extension(source.path);
    if (!_supportedExtensions.contains(extension.toLowerCase())) {
      throw FileSystemException('Unsupported image format', sourcePath);
    }

    final sourceName = _fileNameWithoutExtension(source.path);
    final baseName = _safeFileName(
      [productName, sourceName]
          .where((part) => part.trim().isNotEmpty)
          .join('_'),
    );
    final target = await _availableTargetFile(baseName, extension);
    await source.copy(target.path);
    return target.path;
  }

  Future<File> _availableTargetFile(String baseName, String extension) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    var index = 0;
    while (true) {
      final suffix = index == 0 ? stamp.toString() : '${stamp}_$index';
      final target = File('${_imagesDirectory.path}${Platform.pathSeparator}'
          '${baseName}_$suffix$extension');
      if (!await target.exists()) return target;
      index += 1;
    }
  }

  static Directory _defaultImagesDirectory() {
    if (Platform.isAndroid) {
      return Directory(
          '/data/user/0/com.mycrimson.cataloguestudio/files/images');
    }
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.trim().isNotEmpty) {
      return Directory('$appData\\Crimson Catalogue Studio\\images');
    }
    return Directory('data/images');
  }

  static String _extension(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot);
  }

  static String _fileNameWithoutExtension(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? name : name.substring(0, dot);
  }

  static String _safeFileName(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return cleaned.isEmpty ? 'product_image' : cleaned;
  }

  static const _supportedExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.bmp',
  };
}
