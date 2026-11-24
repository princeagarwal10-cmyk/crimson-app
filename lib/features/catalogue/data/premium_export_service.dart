import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

import '../../../core/rules/catalogue_rules.dart';
import '../domain/catalogue_models.dart';
import 'windows_pdf_writer.dart';

class PremiumExportService {
  const PremiumExportService();

  static const brandWebsite = 'www.mycrimson.in';
  static const brandPhone = '+91 89278 78935';
  static const brandInstagram = '@crimson.decor';

  Future<void> exportPriceStickerImage({
    required ProductDraft product,
    required String path,
    String? finish,
  }) async {
    final targetPath = _ensureExtension(path, '.png');
    final bytes = await renderPriceStickerPng(product: product, finish: finish);
    await File(targetPath).parent.create(recursive: true);
    await File(targetPath).writeAsBytes(bytes);
  }

  Future<Uint8List> renderPriceStickerPng({
    required ProductDraft product,
    String? finish,
  }) async {
    const width = 1417;
    const height = 945;
    const designWidth = 709.0;
    const designHeight = 472.0;
    const text = ui.Color(0xFF050505);
    const muted = ui.Color(0xFF333333);
    const crimson = ui.Color(0xFF8B0F2E);
    final rows = _stickerRows(product, finish: finish);
    final finishLabel = _stickerFinish(product, finish: finish);
    final logo = await _stickerLogoImage();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
    canvas.scale(width / designWidth, height / designHeight);

    final rowCount = rows.isEmpty ? 1 : rows.length;
    final rowFont = rowCount > 7
        ? 30.0
        : rowCount > 5
            ? 34.0
            : 39.0;
    final rowGap = rowCount > 7
        ? 45.0
        : rowCount > 5
            ? 50.0
            : 56.0;
    final startY = rowCount > 6 ? 44.0 : 52.0;
    final leftWidth = rowCount > 6 ? 186.0 : 210.0;
    final priceX = rowCount > 6 ? 220.0 : 235.0;

    for (var index = 0; index < rows.length; index++) {
      final y = startY + index * rowGap;
      _drawText(canvas, rows[index].label.toUpperCase(), 24, y, leftWidth,
          rowFont, text,
          weight: ui.FontWeight.w500, maxLines: 1);
      _drawText(canvas, rows[index].price, priceX, y, 145, rowFont, text,
          weight: ui.FontWeight.w500, maxLines: 1);
    }

    _drawCrimsonStickerLogo(
      canvas,
      logo,
      const ui.Rect.fromLTWH(420, 24, 255, 88),
    );
    final title = cleanText(product.name).isEmpty ? 'PRODUCT' : product.name;
    _drawText(canvas, title.toUpperCase(), 340, 185, 332, 52, text,
        weight: ui.FontWeight.w700, align: ui.TextAlign.center, maxLines: 2);
    canvas.drawRect(
      const ui.Rect.fromLTWH(340, 264, 330, 3),
      ui.Paint()..color = text,
    );
    if (finishLabel.isNotEmpty) {
      _drawText(canvas, finishLabel.toUpperCase(), 356, 314, 300, 36, muted,
          weight: ui.FontWeight.w500, align: ui.TextAlign.center, maxLines: 2);
    }
    _drawText(canvas, '*T&C Apply', 570, 424, 100, 17, muted,
        align: ui.TextAlign.right, maxLines: 1);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, designWidth, designHeight),
      ui.Paint()
        ..color = crimson.withValues(alpha: 0.10)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final image = await recorder.endRecording().toImage(width, height);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) {
      throw const FileSystemException('Could not render price sticker.');
    }
    return png.buffer.asUint8List();
  }

  Future<void> exportPriceStickerPdf({
    required ProductDraft product,
    required String path,
    String? finish,
  }) async {
    final targetPath = _ensureExtension(path, '.pdf');
    final edge = _edgeExecutable();
    if (edge == null) {
      throw const FileSystemException(
        'Microsoft Edge is required to create the sticker PDF.',
      );
    }
    final temporary = await Directory.systemTemp.createTemp(
      'crimson_60x40_sticker_',
    );
    try {
      final imageFile = File('${temporary.path}\\sticker.png');
      final htmlFile = File('${temporary.path}\\sticker.html');
      await imageFile.writeAsBytes(
        await renderPriceStickerPng(product: product, finish: finish),
      );
      final html = '<!doctype html><html><head><meta charset="utf-8"><style>'
          '@page{size:60mm 40mm;margin:0}'
          'html,body{margin:0;width:60mm;height:40mm;background:white}'
          'img{width:60mm;height:40mm;display:block}'
          '</style></head><body><img src="${_imageUri(imageFile.path)}"></body></html>';
      await htmlFile.writeAsString(html);
      await const WindowsPdfWriter().write(
        edgeExecutable: edge,
        html: htmlFile,
        temporary: temporary,
        path: targetPath,
      );
    } finally {
      await WindowsPdfWriter.cleanup(temporary);
    }
  }

  Future<void> exportProductSpotlightImage({
    required ProductDraft product,
    required String path,
  }) async {
    await exportProductSpotlightImages(product: product, path: path);
  }

  /// Saves each A4 page as a separate PNG. A one-page product keeps the
  /// requested filename; later pages receive a `_page_N` suffix.
  Future<List<String>> exportProductSpotlightImages({
    required ProductDraft product,
    required String path,
  }) async {
    final targetPath = _ensureExtension(path, '.png');
    final pages = await renderProductSpotlightPages(product);
    final result = <String>[];
    for (var index = 0; index < pages.length; index++) {
      final pagePath = index == 0
          ? targetPath
          : '${targetPath.substring(0, targetPath.length - 4)}_page_${index + 1}.png';
      final file = File(pagePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(pages[index]);
      result.add(pagePath);
    }
    return result;
  }

  Future<List<Uint8List>> renderProductSpotlightPages(
      ProductDraft product) async {
    final paths = _productImagePaths(product);
    final matrix = variationPriceMatrix(product.variations);
    final tables = _spotlightTableSlices(matrix);
    final imagePageCount = math.max(1, (paths.length / 4).ceil());
    final pageCount = math.max(imagePageCount, tables.length);
    final result = <Uint8List>[];
    for (var page = 0; page < pageCount; page++) {
      final pagePaths = paths.skip(page * 4).take(4).toList();
      final table = tables[page < tables.length ? page : 0];
      result.add(await _renderProductSpotlightPage(
        product: product,
        imagePaths: pagePaths,
        table: table,
        pageNumber: page + 1,
        pageCount: pageCount,
      ));
    }
    return result;
  }

  Future<Uint8List> _renderProductSpotlightPage({
    required ProductDraft product,
    required List<String> imagePaths,
    required _SpotlightTableSlice table,
    required int pageNumber,
    required int pageCount,
  }) async {
    const width = 1200;
    const height = 1697;
    const crimson = ui.Color(0xFF8B0F2E);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFFFDFBF8), ui.BlendMode.src);

    _drawText(canvas, 'Crimson', 70, 62, 340, 52, crimson,
        weight: ui.FontWeight.w800, maxLines: 1);
    _drawText(canvas, 'DECORE', 78, 120, 210, 15, crimson,
        weight: ui.FontWeight.w700, letterSpacing: 7, maxLines: 1);
    _drawText(canvas, product.category.toUpperCase(), 655, 84, 475, 25, crimson,
        weight: ui.FontWeight.w800, align: ui.TextAlign.right, maxLines: 2);
    canvas.drawRect(
        const ui.Rect.fromLTWH(70, 156, 1060, 5), ui.Paint()..color = crimson);

    _drawSpotlightTitle(canvas, product.name.toUpperCase(), 70, 194, 1060);
    final code = cleanText(product.internalProductCode);
    if (code.isNotEmpty) {
      _drawText(canvas, code, 72, 276, 450, 17, const ui.Color(0xFF777075),
          weight: ui.FontWeight.w600, maxLines: 1);
    }
    if (pageNumber > 1) {
      _drawText(
          canvas, 'CONTINUED', 900, 276, 230, 17, const ui.Color(0xFF777075),
          align: ui.TextAlign.right, maxLines: 1);
    }

    if (imagePaths.isNotEmpty) {
      await _drawProductImages(
          canvas, imagePaths, const ui.Rect.fromLTWH(70, 316, 1060, 690));
    }
    if (imagePaths.isEmpty && pageNumber == 1) {
      _drawImagePlaceholder(canvas, const ui.Rect.fromLTWH(70, 316, 1060, 690));
    }

    final tableTop = imagePaths.isEmpty && pageNumber > 1 ? 360.0 : 1100.0;
    _drawText(canvas, 'PRICE VARIATIONS', 70, tableTop - 52, 600, 27, crimson,
        weight: ui.FontWeight.w800, maxLines: 1);
    _drawMatrix(canvas, table, ui.Rect.fromLTWH(70, tableTop, 1060, 350));

    canvas.drawRect(const ui.Rect.fromLTWH(0, 1547, 1200, 150),
        ui.Paint()..color = crimson);
    _drawText(
        canvas, brandWebsite, 80, 1589, 290, 19, const ui.Color(0xFFFFFFFF),
        weight: ui.FontWeight.w700, maxLines: 1);
    _drawText(
        canvas, brandInstagram, 80, 1627, 290, 17, const ui.Color(0xFFFFFFFF),
        weight: ui.FontWeight.w600, maxLines: 1);
    _drawText(canvas, 'DESIGNED TO DEFINE. BUILT TO LAST.', 390, 1607, 490, 19,
        const ui.Color(0xFFFFFFFF),
        weight: ui.FontWeight.w700,
        letterSpacing: 2,
        align: ui.TextAlign.center,
        maxLines: 1);
    _drawText(canvas, brandPhone, 900, 1589, 230, 18,
        const ui.Color(0xFFFFFFFF),
        weight: ui.FontWeight.w700, align: ui.TextAlign.right, maxLines: 1);
    _drawText(canvas, '$pageNumber / $pageCount', 900, 1627, 230, 18,
        const ui.Color(0xFFFFFFFF),
        weight: ui.FontWeight.w700, align: ui.TextAlign.right, maxLines: 1);

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (png == null) {
      throw const FileSystemException('Could not render product spotlight.');
    }
    return png.buffer.asUint8List();
  }

  Future<void> exportProductSpotlightHtml({
    required ProductDraft product,
    required String path,
  }) async {
    final targetPath = _ensureExtension(path, '.html');
    await File(targetPath).parent.create(recursive: true);
    await File(targetPath).writeAsString(buildProductSpotlightHtml(product));
  }

  Future<void> exportProductSpotlightPdf({
    required ProductDraft product,
    required String path,
  }) async {
    final targetPath = _ensureExtension(path, '.pdf');
    final edge = _edgeExecutable();
    if (edge == null) {
      throw const FileSystemException(
        'Microsoft Edge is required to create the PDF.',
      );
    }

    final tempDirectory = await Directory.systemTemp.createTemp(
      'crimson_product_pdf_',
    );
    try {
      final imagePaths = await exportProductSpotlightImages(
          product: product,
          path: '${tempDirectory.path}/product-spotlight.png');
      final htmlFile = File('${tempDirectory.path}/product-spotlight.html');
      final pages = imagePaths
          .map((imagePath) =>
              '<div class="page"><img src="${_imageUri(imagePath)}"></div>')
          .join();
      await htmlFile.writeAsString(
        '<!doctype html><html><head><meta charset="utf-8"><style>'
        '@page{size:A4 portrait;margin:0}'
        'html,body{margin:0;background:white}'
        '.page{width:210mm;height:297mm;page-break-after:always;overflow:hidden}'
        '.page:last-child{page-break-after:auto}'
        'img{width:210mm;height:297mm;display:block;object-fit:contain}'
        '</style></head><body>$pages</body></html>',
      );
      await const WindowsPdfWriter().write(
        edgeExecutable: edge,
        html: htmlFile,
        temporary: tempDirectory,
        path: targetPath,
      );
    } finally {
      await WindowsPdfWriter.cleanup(tempDirectory);
    }
  }

  String buildProductSpotlightHtml(ProductDraft product) {
    final matrix = variationPriceMatrix(product.variations);
    final imagePaths = _productImagePaths(product);
    final tables = _spotlightTableSlices(matrix);
    final pageCount =
        math.max(math.max(1, (imagePaths.length / 4).ceil()), tables.length);
    final pages = StringBuffer();
    for (var page = 0; page < pageCount; page++) {
      final pagePaths = imagePaths.skip(page * 4).take(4).toList();
      final table = tables[page < tables.length ? page : 0];
      final photoTiles = pagePaths
          .map((path) =>
              '<div class="photo-tile"><img src="${_html(_imageUri(path))}" alt="${_html(product.name)}"></div>')
          .join();
      final columns = table.sizes
          .map((size) => '<th>${_html(size.toUpperCase())}</th>')
          .join();
      final rows = table.finishes.map((finish) {
        final cells = table.sizes
            .map((size) =>
                '<td>${_html(_displayPrice(matrix.prices[matrix.key(finish, size)]))}</td>')
            .join();
        return '<tr><td class="finish">${_html(finish)}</td>$cells</tr>';
      }).join();
      pages.write('''
<main class="page${pagePaths.isEmpty && page > 0 ? ' table-only' : ''}">
  <div class="top"><div class="logo">Crimson<small>DECORE</small></div><div class="category">${_html(product.category.toUpperCase())}</div></div>
  <div class="rule"></div>
  <h1 style="font-size:${_spotlightHtmlTitleSize(product.name)}px">${_html(product.name.toUpperCase())}</h1>
  <div class="meta">${_html(product.internalProductCode)}${page > 0 ? '<span>CONTINUED</span>' : ''}</div>
  <div class="photo count-${pagePaths.isEmpty ? 1 : pagePaths.length}">${pagePaths.isEmpty ? (page == 0 ? '<div class="placeholder">C</div>' : '') : photoTiles}</div>
  <div class="matrix-title">PRICE VARIATIONS</div>
  <table><thead><tr><th>FINISH</th>$columns</tr></thead><tbody>$rows</tbody></table>
  <div class="footer"><span>$brandWebsite<br>$brandInstagram</span><span class="tagline">DESIGNED TO DEFINE. BUILT TO LAST.</span><span>$brandPhone<br>${page + 1} / $pageCount</span></div>
</main>
''');
    }

    return '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>${_html(product.name)} - Crimson Product Spotlight</title>
<style>
@page { size: A4 portrait; margin: 0; }
* { box-sizing: border-box; }
body { margin: 0; background: #fff; color: #1c1c1e; font-family: "Segoe UI", Arial, sans-serif; }
.page { width: 210mm; height: 297mm; margin: 0 auto; background: #fffdf9; padding: 39px 46px 0; position: relative; overflow: hidden; page-break-after: always; }
.page:last-child { page-break-after: auto; }
.top { display: flex; justify-content: space-between; align-items: center; color: #8B0F2E; font-weight: 800; }
.logo { font-size: 34px; font-family: Georgia,serif; }
.logo small { display: block; font: 700 11px Arial,sans-serif; letter-spacing: 5px; margin-left: 4px; }
.category { font-size: 16px; letter-spacing: .5px; text-align: right; max-width: 60%; }
.rule { height: 4px; background: #8B0F2E; margin: 15px 0 20px; }
h1 { margin: 0; color: #8B0F2E; line-height: 1.08; overflow-wrap: anywhere; max-height: 90px; overflow: hidden; }
.meta { height: 28px; color: #777075; font-size: 12px; letter-spacing: .6px; margin-top: 8px; }
.meta span { float: right; }
.photo { height: 445px; display: grid; gap: 9px; margin: 4px 0 23px; }
.table-only .photo { height: 0; margin: 42px 0 16px; }
.photo.count-1 { grid-template-columns: 1fr; grid-template-rows: 1fr; }
.photo.count-2 { grid-template-columns: repeat(2, minmax(0, 1fr)); grid-template-rows: 1fr; }
.photo.count-3, .photo.count-4 { grid-template-columns: repeat(2, minmax(0, 1fr)); grid-template-rows: repeat(2, minmax(0, 1fr)); }
.photo.count-3 .photo-tile:first-child { grid-column: 1 / 3; width: calc((100% - 9px) / 2); justify-self: center; }
.photo-tile { min-width: 0; min-height: 0; display: flex; align-items: center; justify-content: center; overflow: hidden; background: #fff; }
.photo-tile img { width: 100%; height: 100%; object-fit: contain; }
.placeholder { display:flex; align-items:center; justify-content:center; color:#8B0F2E; font-size:64px; }
.matrix-title { color: #8B0F2E; font-weight: 800; font-size: 18px; margin-bottom: 9px; }
table { width: 100%; border-collapse: collapse; table-layout: fixed; font-size: 14px; }
th { background: #8B0F2E; color: white; text-align: center; padding: 10px 8px; font-size: 14px; overflow-wrap: anywhere; }
th:first-child, td:first-child { text-align: left; width: 27%; }
td { padding: 10px 8px; text-align: center; border-bottom: 1px solid #E5E7EB; overflow-wrap: anywhere; }
tbody tr:nth-child(even) { background:#f8f5f5; }
.finish { font-weight: 700; }
.footer { position: absolute; left:0; right:0; bottom:0; height: 95px; padding: 0 46px; background:#8B0F2E; color:white; display:grid; grid-template-columns:1fr 1.7fr 1fr; align-items:center; gap:20px; font-weight:700; font-size:11px; }
.footer .tagline { text-align:center; letter-spacing:1.4px; }
.footer span:last-child { text-align:right; }
</style>
</head>
<body>
$pages
</body>
</html>
''';
  }

  Future<void> _drawProductImages(
      ui.Canvas canvas, List<String> imagePaths, ui.Rect rect) async {
    final imageRects = _spotlightImageRects(rect, imagePaths.length);
    for (var index = 0; index < imagePaths.length; index++) {
      final imageRect = imageRects[index];
      try {
        final bytes = await _imageBytes(imagePaths[index]);
        final image = await _decodeImage(bytes);
        final src = await _spotlightSubjectRect(image);
        final fitted = _containRect(src.size, imageRect);
        canvas.drawImageRect(
          image,
          src,
          fitted,
          ui.Paint()..filterQuality = ui.FilterQuality.high,
        );
      } on Object {
        _drawImagePlaceholder(canvas, imageRect);
      }
    }
  }

  /// Trim uniform white or transparent photo margins before fitting the
  /// hardware into its tile. Photos with a complex background stay intact.
  Future<ui.Rect> _spotlightSubjectRect(ui.Image image) async {
    final full =
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return full;
    final pixels = data.buffer.asUint8List();
    final width = image.width;
    final height = image.height;
    final corners = [
      0,
      (width - 1) * 4,
      (height - 1) * width * 4,
      ((height * width) - 1) * 4,
    ];
    final transparent = corners.every((index) => pixels[index + 3] < 20);
    final white = corners.every((index) =>
        pixels[index + 3] > 240 &&
        pixels[index] > 230 &&
        pixels[index + 1] > 230 &&
        pixels[index + 2] > 230);
    if (!transparent && !white) return full;

    final step = math.max(1, math.max(width, height) ~/ 1000);
    var left = width;
    var top = height;
    var right = -1;
    var bottom = -1;
    var foreground = 0;
    for (var y = 0; y < height; y += step) {
      for (var x = 0; x < width; x += step) {
        final offset = (y * width + x) * 4;
        final subject = transparent
            ? pixels[offset + 3] > 24
            : pixels[offset + 3] > 24 &&
                (pixels[offset] < 222 ||
                    pixels[offset + 1] < 222 ||
                    pixels[offset + 2] < 222);
        if (!subject) continue;
        foreground++;
        left = math.min(left, x);
        top = math.min(top, y);
        right = math.max(right, x);
        bottom = math.max(bottom, y);
      }
    }
    final sampled = ((width / step).ceil() * (height / step).ceil());
    if (right < left || foreground < sampled * .001) return full;
    final marginX = math.max(6, (right - left) * .06).round();
    final marginY = math.max(6, (bottom - top) * .06).round();
    final cropLeft = math.max(0, left - marginX).toDouble();
    final cropTop = math.max(0, top - marginY).toDouble();
    final cropRight = math.min(width, right + step + marginX).toDouble();
    final cropBottom = math.min(height, bottom + step + marginY).toDouble();
    if (cropRight <= cropLeft || cropBottom <= cropTop) return full;
    return ui.Rect.fromLTRB(cropLeft, cropTop, cropRight, cropBottom);
  }

  List<_SpotlightTableSlice> _spotlightTableSlices(VariationMatrix matrix) {
    if (matrix.finishes.isEmpty || matrix.sizes.isEmpty) {
      return [_SpotlightTableSlice(matrix, const [], const [])];
    }
    final result = <_SpotlightTableSlice>[];
    for (var row = 0; row < matrix.finishes.length; row += 5) {
      for (var column = 0; column < matrix.sizes.length; column += 5) {
        result.add(_SpotlightTableSlice(
          matrix,
          matrix.finishes
              .sublist(row, math.min(row + 5, matrix.finishes.length)),
          matrix.sizes
              .sublist(column, math.min(column + 5, matrix.sizes.length)),
        ));
      }
    }
    return result;
  }

  List<ui.Rect> _spotlightImageRects(ui.Rect rect, int imageCount) {
    const gap = 12.0;
    if (imageCount <= 1) return [rect];
    if (imageCount == 2) {
      final tileWidth = (rect.width - gap) / 2;
      return [
        ui.Rect.fromLTWH(rect.left, rect.top, tileWidth, rect.height),
        ui.Rect.fromLTWH(
          rect.left + tileWidth + gap,
          rect.top,
          tileWidth,
          rect.height,
        ),
      ];
    }

    final tileWidth = (rect.width - gap) / 2;
    final tileHeight = (rect.height - gap) / 2;
    final left = rect.left;
    final right = rect.left + tileWidth + gap;
    final bottom = rect.top + tileHeight + gap;
    if (imageCount == 3) {
      return [
        ui.Rect.fromLTWH(
          rect.left + (rect.width - tileWidth) / 2,
          rect.top,
          tileWidth,
          tileHeight,
        ),
        ui.Rect.fromLTWH(left, bottom, tileWidth, tileHeight),
        ui.Rect.fromLTWH(right, bottom, tileWidth, tileHeight),
      ];
    }
    return [
      ui.Rect.fromLTWH(left, rect.top, tileWidth, tileHeight),
      ui.Rect.fromLTWH(right, rect.top, tileWidth, tileHeight),
      ui.Rect.fromLTWH(left, bottom, tileWidth, tileHeight),
      ui.Rect.fromLTWH(right, bottom, tileWidth, tileHeight),
    ];
  }

  void _drawImagePlaceholder(ui.Canvas canvas, ui.Rect rect) {
    _drawText(
      canvas,
      'C',
      rect.left + rect.width / 2 - 34,
      rect.top + rect.height / 2 - 48,
      80,
      88,
      const ui.Color(0xFF8B0F2E),
      weight: ui.FontWeight.w800,
    );
  }

  void _drawMatrix(ui.Canvas canvas, _SpotlightTableSlice table, ui.Rect rect) {
    const crimson = ui.Color(0xFF8B0F2E);
    const text = ui.Color(0xFF1C1C1E);
    const border = ui.Color(0xFFE5E7EB);
    if (table.sizes.isEmpty || table.finishes.isEmpty) {
      _drawText(canvas, 'No price variations added.', rect.left, rect.top,
          rect.width, 22, text,
          maxLines: 1);
      return;
    }
    final columns = ['FINISH', ...table.sizes];
    const firstWidth = 280.0;
    final priceWidth = (rect.width - firstWidth) / table.sizes.length;
    const rowHeight = 55.0;
    canvas.drawRect(
        ui.Rect.fromLTWH(rect.left, rect.top, rect.width, rowHeight),
        ui.Paint()..color = crimson);
    for (var i = 0; i < columns.length; i++) {
      final left =
          i == 0 ? rect.left : rect.left + firstWidth + (i - 1) * priceWidth;
      final width = i == 0 ? firstWidth : priceWidth;
      _drawText(canvas, columns[i].toUpperCase(), left + 14, rect.top + 14,
          width - 28, 19, const ui.Color(0xFFFFFFFF),
          weight: ui.FontWeight.w800,
          align: i == 0 ? ui.TextAlign.left : ui.TextAlign.center,
          maxLines: 2);
    }
    for (var row = 0; row < table.finishes.length; row++) {
      final y = rect.top + rowHeight + (row * rowHeight);
      canvas.drawRect(
          ui.Rect.fromLTWH(rect.left, y, rect.width, rowHeight),
          ui.Paint()
            ..color = row.isEven
                ? const ui.Color(0xFFFFFFFF)
                : const ui.Color(0xFFF7F8FA));
      final finish = table.finishes[row];
      _drawText(
          canvas, finish, rect.left + 14, y + 10, firstWidth - 28, 19, text,
          weight: ui.FontWeight.w600, maxLines: 2);
      for (var col = 0; col < table.sizes.length; col++) {
        final size = table.sizes[col];
        final price =
            _displayPrice(table.matrix.prices[table.matrix.key(finish, size)]);
        _drawText(canvas, price, rect.left + firstWidth + col * priceWidth + 8,
            y + 13, priceWidth - 16, 19, text,
            align: ui.TextAlign.center, maxLines: 2);
      }
      canvas.drawLine(ui.Offset(rect.left, y + rowHeight),
          ui.Offset(rect.right, y + rowHeight), ui.Paint()..color = border);
    }
  }

  void _drawSpotlightTitle(
      ui.Canvas canvas, String title, double x, double y, double width) {
    for (var size = 52.0; size >= 26; size -= 2) {
      final paragraph = (ui.ParagraphBuilder(ui.ParagraphStyle(
        fontSize: size,
        fontFamily: 'Segoe UI',
        fontWeight: ui.FontWeight.w800,
      ))
            ..pushStyle(ui.TextStyle(
                color: const ui.Color(0xFF8B0F2E),
                fontWeight: ui.FontWeight.w800))
            ..addText(title))
          .build()
        ..layout(ui.ParagraphConstraints(width: width));
      if (paragraph.height <= 108 || size == 26) {
        _drawText(canvas, title, x, y, width, size, const ui.Color(0xFF8B0F2E),
            weight: ui.FontWeight.w800, maxLines: 3);
        return;
      }
    }
  }

  int _spotlightHtmlTitleSize(String title) {
    final length = cleanText(title).length;
    if (length > 85) return 18;
    if (length > 55) return 22;
    if (length > 38) return 28;
    return 34;
  }

  void _drawText(ui.Canvas canvas, String text, double x, double y,
      double width, double size, ui.Color color,
      {ui.FontWeight weight = ui.FontWeight.normal,
      double letterSpacing = 0,
      ui.TextAlign align = ui.TextAlign.left,
      int maxLines = 3}) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontSize: size,
      fontFamily: 'Segoe UI',
      fontWeight: weight,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: '...',
    ))
      ..pushStyle(ui.TextStyle(
          color: color, fontWeight: weight, letterSpacing: letterSpacing))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: width));
    canvas.drawParagraph(paragraph, ui.Offset(x, y));
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  ui.Rect _containRect(ui.Size source, ui.Rect target) {
    final scale =
        math.min(target.width / source.width, target.height / source.height);
    final width = source.width * scale;
    final height = source.height * scale;
    return ui.Rect.fromLTWH(
      target.left + (target.width - width) / 2,
      target.top + (target.height - height) / 2,
      width,
      height,
    );
  }

  List<String> _productImagePaths(ProductDraft product) {
    final paths = <String>[];
    final seen = <String>{};
    for (final path in [...product.imagePaths, product.imagePath]) {
      final clean = cleanText(path);
      if (clean.isNotEmpty && seen.add(clean)) paths.add(clean);
    }
    return paths;
  }

  Future<Uint8List> _imageBytes(String path) async {
    final uri = Uri.tryParse(path);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final client = HttpClient();
      try {
        final request = await client.getUrl(uri);
        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException(
            'Image returned ${response.statusCode}',
            uri: uri,
          );
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
        }
        return Uint8List.fromList(bytes);
      } finally {
        client.close(force: true);
      }
    }
    return File(path).readAsBytes();
  }

  String _imageUri(String path) {
    final uri = Uri.tryParse(path);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return uri.toString();
    }
    return Uri.file(path).toString();
  }

  Future<ui.Image?> _stickerLogoImage() async {
    try {
      final data = await rootBundle.load(
        'assets/branding/crimson_wordmark.png',
      );
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
      );
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  void _drawCrimsonStickerLogo(
    ui.Canvas canvas,
    ui.Image? logo,
    ui.Rect rect,
  ) {
    if (logo == null) {
      _drawText(
        canvas,
        'Crimson',
        rect.left,
        rect.top + 10,
        rect.width,
        42,
        const ui.Color(0xFF9F1239),
        weight: ui.FontWeight.w800,
        align: ui.TextAlign.center,
        maxLines: 1,
      );
      return;
    }
    final source = ui.Rect.fromLTWH(
      0,
      0,
      logo.width.toDouble(),
      logo.height.toDouble(),
    );
    final target = _containRect(source.size, rect);
    canvas.drawImageRect(
      logo,
      source,
      target,
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
  }

  List<_StickerRow> _stickerRows(ProductDraft product, {String? finish}) {
    final matrix = variationPriceMatrix(product.variations);
    if (matrix.sizes.isNotEmpty && matrix.finishes.isNotEmpty) {
      final cleanFinish = cleanText(finish);
      final selectedFinish = cleanFinish.isEmpty
          ? matrix.finishes.first
          : matrix.finishes.firstWhere(
              (value) =>
                  cleanText(value).toLowerCase() == cleanFinish.toLowerCase(),
              orElse: () => matrix.finishes.first,
            );
      return matrix.sizes
          .map(
            (size) => _StickerRow(
              size == '-' ? 'PRICE' : size,
              _stickerPrice(matrix.prices[matrix.key(selectedFinish, size)]),
            ),
          )
          .toList(growable: false);
    }
    final directPrice = cleanText(product.sellingPrice);
    if (directPrice.isNotEmpty && directPrice != '0' && directPrice != '0.00') {
      final label =
          cleanText(product.sizeSpec).isEmpty ? 'PRICE' : product.sizeSpec;
      return [_StickerRow(label, _stickerPrice(directPrice))];
    }
    final rows = <_StickerRow>[];
    for (final variation in product.variations) {
      final parts = [
        cleanText(variation.size),
        cleanText(variation.breadth),
        cleanText(variation.length),
        cleanText(variation.height),
        cleanText(variation.thickness),
      ].where((value) => value.isNotEmpty).toList();
      rows.add(_StickerRow(parts.isEmpty ? 'PRICE' : parts.join(' x '),
          _stickerPrice(variation.price)));
    }
    return rows.isEmpty ? const [_StickerRow('PRICE', '-')] : rows;
  }

  String _stickerFinish(ProductDraft product, {String? finish}) {
    final chosen = cleanText(finish);
    if (chosen.isNotEmpty && chosen != '-') return chosen;
    final matrix = variationPriceMatrix(product.variations);
    final matrixFinish = matrix.finishes.map(cleanText).firstWhere(
          (value) => value.isNotEmpty && value != '-',
          orElse: () => '',
        );
    if (matrixFinish.isNotEmpty) return matrixFinish;
    return cleanText(product.finishColor);
  }

  String _stickerPrice(String? value) {
    final valueText = cleanText(value);
    if (valueText.isEmpty || valueText == '0.00') return '-';
    return formatCompactPrice(valueText);
  }

  String _displayPrice(String? value) {
    final text = cleanText(value);
    if (text.isEmpty || (double.tryParse(text) ?? 0) <= 0) return '-';
    return 'Rs. ${formatCompactPrice(text)}';
  }

  String _ensureExtension(String path, String extension) {
    final clean = path.trim();
    if (clean.toLowerCase().endsWith(extension)) return clean;
    return '$clean$extension';
  }

  String? _edgeExecutable() {
    final programFiles = Platform.environment['PROGRAMFILES'];
    final programFilesX86 = Platform.environment['PROGRAMFILES(X86)'];
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final candidates = <String>[
      if (programFilesX86 != null)
        '$programFilesX86\\Microsoft\\Edge\\Application\\msedge.exe',
      if (programFiles != null)
        '$programFiles\\Microsoft\\Edge\\Application\\msedge.exe',
      if (localAppData != null)
        '$localAppData\\Microsoft\\Edge\\Application\\msedge.exe',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  String _html(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}

class _StickerRow {
  const _StickerRow(this.label, this.price);

  final String label;
  final String price;
}

class _SpotlightTableSlice {
  const _SpotlightTableSlice(this.matrix, this.finishes, this.sizes);

  final VariationMatrix matrix;
  final List<String> finishes;
  final List<String> sizes;
}
