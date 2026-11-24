import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CachedCatalogueImage extends StatefulWidget {
  const CachedCatalogueImage({
    super.key,
    required this.url,
    required this.fit,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.cacheWidth,
    this.fallbackBuilder,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final AlignmentGeometry alignment;
  final int? cacheWidth;
  final WidgetBuilder? fallbackBuilder;

  @override
  State<CachedCatalogueImage> createState() => _CachedCatalogueImageState();
}

class _CachedCatalogueImageState extends State<CachedCatalogueImage> {
  File? _cachedFile;
  Object? _error;
  Future<File>? _future;

  @override
  void initState() {
    super.initState();
    _startLoad();
  }

  @override
  void didUpdateWidget(CachedCatalogueImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _startLoad();
  }

  void _startLoad() {
    final url = widget.url.trim();
    _cachedFile = null;
    _error = null;
    if (url.isEmpty) {
      _future = null;
      return;
    }
    final future = CatalogueImageDiskCache.fileForUrl(url);
    _future = future;
    future.then((file) {
      if (!mounted || _future != future) return;
      setState(() => _cachedFile = file);
    }).catchError((Object error) {
      if (!mounted || _future != future) return;
      setState(() => _error = error);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fallback = widget.fallbackBuilder?.call(context) ?? const SizedBox();
    final file = _cachedFile;
    if (file == null) return fallback;
    if (_error != null) return fallback;
    return Image.file(
      file,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      alignment: widget.alignment,
      cacheWidth: widget.cacheWidth,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class CatalogueImageDiskCache {
  CatalogueImageDiskCache._();

  static final Map<String, Future<File>> _inFlight = <String, Future<File>>{};
  static Future<Directory>? _cacheDirectory;

  static Future<File> fileForUrl(String rawUrl) {
    final url = rawUrl.trim();
    if (url.isEmpty) return Future.error(ArgumentError('Image URL is empty.'));
    return _inFlight.putIfAbsent(url, () async {
      try {
        final directory = await _directory();
        final file = File(
          '${directory.path}${Platform.pathSeparator}${_cacheFileName(url)}',
        );
        if (await file.exists() && await file.length() > 0) return file;
        return await _download(url, file);
      } finally {
        _inFlight.remove(url);
      }
    });
  }

  static Future<Directory> _directory() {
    return _cacheDirectory ??= _resolveDirectory();
  }

  static Future<Directory> _resolveDirectory() async {
    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('com.mycrimson.cataloguestudio/storage');
        final filesDir = (await channel.invokeMethod<String>('filesDir')) ?? '';
        if (filesDir.trim().isNotEmpty) {
          final directory = Directory(
            '${filesDir.trim()}${Platform.pathSeparator}image_cache',
          );
          await directory.create(recursive: true);
          return directory;
        }
      } on Object {
        // Fall through to the platform-neutral cache fallback.
      }
    }

    final appData = Platform.environment['APPDATA'];
    final directory = Directory(
      appData == null || appData.trim().isEmpty
          ? '${Directory.systemTemp.path}${Platform.pathSeparator}Crimson Catalogue Studio${Platform.pathSeparator}image_cache'
          : '$appData${Platform.pathSeparator}Crimson Catalogue Studio${Platform.pathSeparator}image_cache',
    );
    await directory.create(recursive: true);
    return directory;
  }

  static Future<File> _download(String url, File target) async {
    final uri = Uri.parse(url);
    final request =
        await HttpClient().getUrl(uri).timeout(const Duration(seconds: 20));
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Image download failed with status ${response.statusCode}',
        uri: uri,
      );
    }

    await target.parent.create(recursive: true);
    final tempFile = File('${target.path}.download');
    final sink = tempFile.openWrite();
    try {
      await response.pipe(sink);
      await sink.flush();
      await sink.close();
      if (await tempFile.length() == 0) {
        throw const FileSystemException('Downloaded image was empty.');
      }
      if (await target.exists()) await target.delete();
      await tempFile.rename(target.path);
      return target;
    } catch (_) {
      try {
        await sink.close();
      } on Object {
        // Ignore close failures after a download error.
      }
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } on Object {
          // Best-effort cleanup only.
        }
      }
      rethrow;
    }
  }

  static String _cacheFileName(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path ?? url;
    final extension = _extension(path);
    return '${_fnv1a(url)}$extension';
  }

  static String _extension(String path) {
    final clean = path.split('?').first.toLowerCase();
    final dot = clean.lastIndexOf('.');
    if (dot < 0 || dot == clean.length - 1) return '.img';
    final ext = clean.substring(dot);
    if (ext.length > 6 || ext.contains('/')) return '.img';
    return ext;
  }

  static String _fnv1a(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
