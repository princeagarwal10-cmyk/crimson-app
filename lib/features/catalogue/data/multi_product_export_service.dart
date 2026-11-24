import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../core/rules/catalogue_rules.dart';
import '../domain/catalogue_models.dart';
import 'premium_export_service.dart';
import 'windows_pdf_writer.dart';

enum CatalogueImageLayout { classic, multiImage }

class MultiProductExportService {
  const MultiProductExportService();

  static const brandWebsite = 'www.mycrimson.in';
  static const brandPhone = '+91 89278 78935';
  static const brandInstagram = '@crimson.decor';

  Future<List<String>> exportImages({
    required List<ProductDraft> products,
    required String path,
    CatalogueImageLayout imageLayout = CatalogueImageLayout.classic,
  }) async {
    _requireProducts(products);
    final chunks = _chunks(products, _productsPerPage(products));
    final pages = <String>[];
    for (var index = 0; index < chunks.length; index++) {
      final target = chunks.length == 1
          ? _ensureExtension(path, '.png')
          : _numberedPath(path, index + 1, '.png');
      await _renderPage(chunks[index], target, imageLayout);
      pages.add(target);
    }
    return pages;
  }

  Future<List<String>> exportStickerSheetImages({
    required List<ProductDraft> products,
    required String path,
  }) async {
    _requireProducts(products);
    final chunks = _chunks(products, 21);
    final pages = <String>[];
    for (var index = 0; index < chunks.length; index++) {
      final target = chunks.length == 1
          ? _ensureExtension(path, '.png')
          : _numberedPath(path, index + 1, '.png');
      await _renderStickerSheet(chunks[index], target);
      pages.add(target);
    }
    return pages;
  }

  Future<void> exportPdf({
    required List<ProductDraft> products,
    required String path,
    CatalogueImageLayout imageLayout = CatalogueImageLayout.classic,
  }) async {
    _requireProducts(products);
    final edge = _edgeExecutable();
    if (edge == null) {
      throw const FileSystemException(
        'Microsoft Edge is required to create the PDF on Windows.',
      );
    }
    final target = _ensureExtension(path, '.pdf');
    final temporary =
        await Directory.systemTemp.createTemp('crimson_multi_catalogue_');
    try {
      // Use the same page renderer as Android's createPdfFromImages flow.
      // Printing pre-rendered pages prevents browser CSS from reflowing the
      // image gallery, finish labels, and pricing tables differently.
      final pages = await exportImages(
        products: products,
        path: '${temporary.path}/catalogue-page.png',
        imageLayout: imageLayout,
      );
      final html = File('${temporary.path}/catalogue.html');
      final pageHtml = pages
          .map(
            (page) =>
                '<section class="rendered-page"><img src="${_html(File(page).absolute.uri.toString())}" alt="Catalogue page"></section>',
          )
          .join();
      await html
          .writeAsString('''<!doctype html><html><head><meta charset="utf-8">
<title>Crimson Decore Catalogue</title><style>
@page{size:A4 portrait;margin:0}
html,body{margin:0;padding:0;background:white}
.rendered-page{width:210mm;height:297mm;margin:0;padding:0;overflow:hidden;break-after:page;page-break-after:always}
.rendered-page:last-child{break-after:auto;page-break-after:auto}
.rendered-page img{display:block;width:100%;height:100%;object-fit:contain;object-position:center}
</style></head><body>$pageHtml</body></html>''');
      await const WindowsPdfWriter().write(
        edgeExecutable: edge,
        html: html,
        temporary: temporary,
        path: target,
      );
    } finally {
      await WindowsPdfWriter.cleanup(temporary);
    }
  }

  String buildHtml(
    List<ProductDraft> products, {
    CatalogueImageLayout imageLayout = CatalogueImageLayout.classic,
  }) {
    _requireProducts(products);
    final pages =
        _chunks(products, _productsPerPage(products)).map((pageProducts) {
      final cards =
          pageProducts.map((product) => _cardHtml(product, imageLayout)).join();
      return '''
<section class="catalogue-page">
  <header><div class="logo"><span>CD</span><div><b>CRIMSON</b><small>DECORE</small></div></div><h1>${_html(_pageTitle(pageProducts))}</h1></header>
  <div class="rule"></div>
  <div class="rows">$cards</div>
  <footer><span>$brandWebsite</span><i></i><span>$brandInstagram</span><i></i><span>$brandPhone</span></footer>
</section>''';
    }).join();
    return '''<!doctype html><html><head><meta charset="utf-8"><title>Crimson Decore Catalogue</title>
<style>
@page{size:A4 portrait;margin:0}*{box-sizing:border-box}body{margin:0;background:#eef0f3;color:#1c1c1e;font-family:"Segoe UI",Arial,sans-serif}.catalogue-page{width:794px;height:1123px;margin:0 auto;padding:30px 34px 22px;background:#fff;break-after:page;page-break-after:always;overflow:hidden;display:flex;flex-direction:column}.catalogue-page:last-child{break-after:auto;page-break-after:auto}header{height:68px;display:flex;align-items:center;justify-content:space-between}.logo{color:#8B0F2E;display:flex;align-items:center;gap:12px}.logo>span{width:44px;height:44px;border:3px solid #8B0F2E;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:16px;font-weight:800}.logo div{display:flex;flex-direction:column}.logo b{font-family:Georgia,serif;font-size:24px;letter-spacing:5px;font-weight:500}.logo small{font-size:9px;letter-spacing:8px}header h1{margin:0;font-size:19px;letter-spacing:1.3px;text-transform:uppercase}.rule{height:2px;background:#9D1239;margin:6px 0 18px}.rows{flex:1;display:grid;grid-template-rows:repeat(3,1fr);gap:16px}.card{min-width:0;display:grid;grid-template-columns:42% 1fr;gap:22px;padding-bottom:16px;border-bottom:1px solid #E5E7EB}.card:last-child{border-bottom:0}.photo{height:246px;display:flex;align-items:center;justify-content:center;background:#fff;overflow:hidden}.photo img{width:100%;height:100%;object-fit:contain}.placeholder{width:100%;height:100%;display:flex;align-items:center;justify-content:center;background:#F7F8FA;color:#9D1239;font-size:42px;font-weight:900}.details{min-width:0}.title-row{display:flex;align-items:center;margin-bottom:10px}.product-name{font-size:21px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.finish-note{margin:0 0 10px;color:#6B7280;font-size:13px}.matrix{width:100%;border-collapse:collapse;table-layout:fixed;font-size:13px}.matrix th{padding:9px 7px;background:#F8E4EA;color:#1c1c1e;text-align:center;font-weight:800;border:1px solid #E0BFC8}.matrix th:first-child,.matrix td:first-child{text-align:left;width:24%}.matrix-wide{font-size:11px}.matrix-wide th{padding:8px 4px}.matrix-wide td{padding:8px 4px}.matrix-wide th:first-child,.matrix-wide td:first-child{width:22%}.matrix td{padding:9px 7px;text-align:center;border:1px solid #D9DCE1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.matrix tbody tr:nth-child(even) td{background:#F7F8FA}.matrix-stack{width:100%}.matrix-gap{height:8px}.matrix-dense{font-size:12px}.matrix-dense th{padding:8px 5px}.matrix-dense td{padding:8px 5px}.simple-price{display:inline-block;margin-top:4px;background:#F8E4EA;padding:14px 16px;font-size:20px;font-weight:800;color:#8B0F2E}.more{margin-top:5px;color:#6B7280;font-size:10px}footer{height:34px;border-top:2px solid #9D1239;display:flex;align-items:flex-end;justify-content:center;gap:14px;font-size:11px}footer i{width:1px;height:15px;background:#9D1239}
/* Multi-image mode only changes the existing 42% photo column. */
.card{overflow:hidden}.details{overflow:hidden}.photo-gallery{display:grid;gap:8px;padding:2px}.photo-gallery.count-2,.photo-gallery.count-3{grid-template-columns:1fr}.photo-gallery.count-2{grid-template-rows:repeat(2,minmax(0,1fr))}.photo-gallery.count-3{grid-template-rows:repeat(3,minmax(0,1fr))}.photo-gallery.count-4{grid-template-columns:repeat(2,minmax(0,1fr));grid-template-rows:repeat(2,minmax(0,1fr))}.photo-tile{position:relative;min-width:0;min-height:0;display:flex;align-items:center;justify-content:center;overflow:hidden;background:#fff;border:1px solid #E5E7EB;border-radius:3px}.photo-tile img{padding:6px}.photo-label{position:absolute;left:0;right:0;bottom:0;min-width:0;padding:3px 4px;background:rgba(255,255,255,.92);color:#374151;font-size:11px;font-weight:800;line-height:14px;text-align:center;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.photo-more{position:absolute;right:4px;top:4px;padding:2px 5px;border-radius:10px;background:#9D1239;color:#fff;font-size:11px;font-weight:800}.matrix{max-width:100%;font-variant-numeric:tabular-nums}.matrix-stack{max-width:100%;overflow:hidden}.matrix-wide{font-size:12px}.matrix-wide th,.matrix-wide td{padding:6px 3px}.matrix-dense th,.matrix-dense td{padding:5px 3px}.matrix th,.matrix td{overflow:hidden;text-overflow:ellipsis}.matrix td:first-child{white-space:normal;overflow-wrap:anywhere;line-height:1.15}.finish-note{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
</style></head><body>$pages</body></html>''';
  }

  String _cardHtml(
    ProductDraft product,
    CatalogueImageLayout imageLayout,
  ) {
    final matrix = variationPriceMatrix(product.variations);
    final table = _matrixHtml(product, matrix);
    final finishLine = _finishLine(product, matrix);
    final title = cleanText(product.name);
    final titleRow =
        '<div class="title-row"><span class="product-name">${_html(title)}</span></div>';
    return '''<article class="card">${_photoHtml(product, imageLayout)}<div class="details">$titleRow${finishLine.isEmpty ? '' : '<p class="finish-note">Finish: ${_html(finishLine)}</p>'}$table</div></article>''';
  }

  String _photoHtml(
    ProductDraft product,
    CatalogueImageLayout imageLayout,
  ) {
    final paths = _imagePaths(product);
    if (paths.isEmpty) {
      return '<div class="photo"><div class="placeholder">C</div></div>';
    }
    if (imageLayout == CatalogueImageLayout.classic || paths.length == 1) {
      return '<div class="photo"><img src="${_html(_imageUri(paths.first))}" alt="${_html(product.name)}"></div>';
    }

    final visiblePaths = paths.take(4).toList(growable: false);
    final remaining = math.max(0, paths.length - visiblePaths.length);
    final tileHtml = <String>[];
    for (var index = 0; index < visiblePaths.length; index++) {
      final path = visiblePaths[index];
      final label = _imageFinishTag(product, path);
      final more = index == visiblePaths.length - 1 && remaining > 0
          ? '<span class="photo-more">+$remaining</span>'
          : '';
      tileHtml.add(
        '<div class="photo-tile"><img src="${_html(_imageUri(path))}" alt="${_html(label.isEmpty ? product.name : label)}">${_photoLabelHtml(label)}$more</div>',
      );
    }
    return '<div class="photo photo-gallery count-${visiblePaths.length}">${tileHtml.join()}</div>';
  }

  String _photoLabelHtml(String label) =>
      label.isEmpty ? '' : '<span class="photo-label">${_html(label)}</span>';

  String _matrixHtml(
    ProductDraft product,
    VariationMatrix matrix,
  ) {
    final sizes = matrix.sizes;
    final finishes = matrix.finishes;
    if (sizes.isEmpty || finishes.isEmpty) {
      return '<div class="simple-price">${_html(_simplePrice(product))}</div>';
    }
    final sizeGroups = _chunks(sizes, 7);
    final dense = sizeGroups.length > 1 || finishes.length > 3;
    final tables = sizeGroups.map((group) {
      final columns = group.map((size) => '<th>${_html(size)}</th>').join();
      final rows = finishes.map((finish) {
        final values = group.map((size) {
          final price = matrix.prices[matrix.key(finish, size)];
          return '<td>${_html(_matrixPrice(price))}</td>';
        }).join();
        return '<tr><td>${_html(finish.isEmpty ? 'PRICE' : finish)}</td>$values</tr>';
      }).join();
      final wide = group.length >= 6;
      final classes = [
        'matrix',
        if (dense) 'matrix-dense',
        if (wide) 'matrix-wide'
      ].join(' ');
      return '<table class="$classes"><thead><tr><th>Finish</th>$columns</tr></thead><tbody>$rows</tbody></table>';
    }).join('<div class="matrix-gap"></div>');
    return '<div class="matrix-stack">$tables</div>';
  }

  Future<void> _renderStickerSheet(
      List<ProductDraft> products, String path) async {
    const pageWidth = 2480;
    const pageHeight = 3508;
    const stickerWidth = 709.0;
    const stickerHeight = 472.0;
    const columns = 3;
    const rows = 7;
    const horizontalGap = 44.0;
    const verticalGap = 26.0;
    const marginX =
        (pageWidth - columns * stickerWidth - (columns - 1) * horizontalGap) /
            2;
    const marginY =
        (pageHeight - rows * stickerHeight - (rows - 1) * verticalGap) / 2;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
    const stickerService = PremiumExportService();

    for (var index = 0; index < products.length; index++) {
      final column = index % columns;
      final row = index ~/ columns;
      final left = marginX + column * (stickerWidth + horizontalGap);
      final top = marginY + row * (stickerHeight + verticalGap);
      final bytes = await stickerService.renderPriceStickerPng(
        product: products[index],
      );
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final source = ui.Rect.fromLTWH(
        0,
        0,
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      final target = ui.Rect.fromLTWH(left, top, stickerWidth, stickerHeight);
      canvas.drawImageRect(
        frame.image,
        source,
        target,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      canvas.drawRect(
        target,
        ui.Paint()
          ..color = const ui.Color(0xFFE5E7EB)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    final image = await recorder.endRecording().toImage(pageWidth, pageHeight);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw const FileSystemException('Sticker sheet render failed.');
    }
    await File(path).parent.create(recursive: true);
    await File(path).writeAsBytes(bytes.buffer.asUint8List());
  }

  Future<void> _renderPage(
    List<ProductDraft> products,
    String path,
    CatalogueImageLayout imageLayout,
  ) async {
    const width = 1200;
    const height = 1600;
    const crimson = ui.Color(0xFF9D1239);
    const softHeader = ui.Color(0xFFF8E4EA);
    const text = ui.Color(0xFF1C1C1E);
    const muted = ui.Color(0xFF6B7280);
    const border = ui.Color(0xFFE5E7EB);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);

    final logoPaint = ui.Paint()
      ..color = crimson
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(const ui.Offset(84, 68), 31, logoPaint);
    _text(canvas, 'CD', 61, 52, 46, 22, crimson,
        weight: ui.FontWeight.w800, align: ui.TextAlign.center);
    _text(canvas, 'CRIMSON', 132, 45, 350, 35, crimson,
        weight: ui.FontWeight.w600, family: 'Georgia');
    _text(canvas, 'D E C O R E', 138, 86, 260, 15, crimson,
        weight: ui.FontWeight.w600);
    _text(canvas, _pageTitle(products).toUpperCase(), 700, 62, 430, 25, text,
        weight: ui.FontWeight.w700, align: ui.TextAlign.right);
    canvas.drawRect(
        const ui.Rect.fromLTWH(55, 125, 1090, 3), ui.Paint()..color = crimson);

    const left = 55.0;
    const top = 155.0;
    const widthContent = 1090.0;
    const rowGap = 28.0;
    const footerTop = 1508.0;
    const rowHeight = (footerTop - top - (rowGap * 2)) / 3;
    for (var index = 0; index < products.length; index++) {
      final rect = ui.Rect.fromLTWH(
        left,
        top + index * (rowHeight + rowGap),
        widthContent,
        rowHeight,
      );
      await _drawCatalogueRow(
        canvas,
        products[index],
        rect,
        crimson,
        softHeader,
        text,
        muted,
        border,
        imageLayout: imageLayout,
        drawDivider: index != products.length - 1,
      );
    }

    canvas.drawRect(
        const ui.Rect.fromLTWH(55, 1508, 1090, 3), ui.Paint()..color = crimson);
    _text(canvas, brandWebsite, 145, 1535, 260, 19, text,
        weight: ui.FontWeight.w600);
    _text(canvas, brandInstagram, 470, 1535, 260, 19, text,
        weight: ui.FontWeight.w600, align: ui.TextAlign.center);
    _text(canvas, brandPhone, 830, 1535, 260, 19, text,
        weight: ui.FontWeight.w600, align: ui.TextAlign.right);

    final image = await recorder.endRecording().toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw const FileSystemException('Image render failed.');
    await File(path).parent.create(recursive: true);
    await File(path).writeAsBytes(bytes.buffer.asUint8List());
  }

  Future<void> _drawCatalogueRow(
    ui.Canvas canvas,
    ProductDraft product,
    ui.Rect rect,
    ui.Color crimson,
    ui.Color softHeader,
    ui.Color text,
    ui.Color muted,
    ui.Color border, {
    required CatalogueImageLayout imageLayout,
    required bool drawDivider,
  }) async {
    final photoWidth = rect.width * 0.42;
    final photo = ui.Rect.fromLTWH(
      rect.left,
      rect.top,
      photoWidth,
      rect.height - 18,
    );
    await _drawProductImages(
      canvas,
      product,
      photo,
      crimson,
      text,
      imageLayout,
    );

    final detailsLeft = photo.right + 30;
    final detailsWidth = rect.right - detailsLeft;
    final title = cleanText(product.name);
    _text(canvas, title, detailsLeft, rect.top + 8, detailsWidth, 31, text,
        weight: ui.FontWeight.w800);

    final matrix = variationPriceMatrix(product.variations);
    final finishLine = _finishLine(product, matrix);
    if (finishLine.isNotEmpty) {
      _text(canvas, 'Finish: $finishLine', detailsLeft, rect.top + 48,
          detailsWidth, 18, muted);
    }

    _drawMatrix(
      canvas,
      product,
      ui.Rect.fromLTWH(
        detailsLeft,
        rect.top + 78,
        detailsWidth,
        rect.height - 99,
      ),
      crimson,
      softHeader,
      text,
      border,
    );

    if (drawDivider) {
      canvas.drawLine(ui.Offset(rect.left, rect.bottom),
          ui.Offset(rect.right, rect.bottom), ui.Paint()..color = border);
    }
  }

  Future<void> _drawProductImages(
    ui.Canvas canvas,
    ProductDraft product,
    ui.Rect rect,
    ui.Color crimson,
    ui.Color text,
    CatalogueImageLayout imageLayout,
  ) async {
    final paths = _imagePaths(product);
    if (imageLayout == CatalogueImageLayout.classic || paths.length <= 1) {
      await _drawImagePath(
        canvas,
        paths.isEmpty ? null : paths.first,
        rect,
        crimson,
      );
      return;
    }

    final visiblePaths = paths.take(4).toList(growable: false);
    final imageRects = _equalImageRects(rect, visiblePaths.length);
    final remaining = math.max(0, paths.length - visiblePaths.length);
    for (var index = 0; index < visiblePaths.length; index++) {
      final imageRect = imageRects[index];
      final label = _imageFinishTag(product, visiblePaths[index]);
      final contentRect = label.isEmpty
          ? imageRect
          : ui.Rect.fromLTWH(imageRect.left, imageRect.top, imageRect.width,
              imageRect.height - 26);
      await _drawImagePath(canvas, visiblePaths[index], contentRect, crimson);
      canvas.drawRect(
        imageRect,
        ui.Paint()
          ..color = const ui.Color(0xFFE5E7EB)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      _drawImageLabel(
        canvas,
        label,
        imageRect,
        text,
      );
      if (index == visiblePaths.length - 1 && remaining > 0) {
        final badge = ui.Rect.fromLTWH(
          imageRect.right - 45,
          imageRect.top + 4,
          41,
          24,
        );
        canvas.drawRRect(
          ui.RRect.fromRectAndRadius(badge, const ui.Radius.circular(12)),
          ui.Paint()..color = crimson,
        );
        _text(canvas, '+$remaining', badge.left, badge.top + 4, badge.width, 13,
            const ui.Color(0xFFFFFFFF),
            weight: ui.FontWeight.w800, align: ui.TextAlign.center);
      }
    }
  }

  List<ui.Rect> _equalImageRects(ui.Rect rect, int count) {
    const gap = 10.0;
    if (count <= 1) return [rect];
    if (count <= 3) {
      final height = (rect.height - gap * (count - 1)) / count;
      return List.generate(
        count,
        (index) => ui.Rect.fromLTWH(
          rect.left,
          rect.top + index * (height + gap),
          rect.width,
          height,
        ),
        growable: false,
      );
    }
    final width = (rect.width - gap) / 2;
    final height = (rect.height - gap) / 2;
    return List.generate(
      4,
      (index) => ui.Rect.fromLTWH(
        rect.left + (index % 2) * (width + gap),
        rect.top + (index ~/ 2) * (height + gap),
        width,
        height,
      ),
      growable: false,
    );
  }

  Future<void> _drawImagePath(
    ui.Canvas canvas,
    String? path,
    ui.Rect rect,
    ui.Color crimson,
  ) async {
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(rect, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    if (path == null) {
      canvas.drawRect(rect, ui.Paint()..color = const ui.Color(0xFFF7F8FA));
      _text(canvas, 'C', rect.left, rect.top + rect.height * 0.38, rect.width,
          70, crimson,
          weight: ui.FontWeight.w900, align: ui.TextAlign.center);
      canvas.restore();
      return;
    }
    try {
      final bytes = await _imageBytes(path);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final source = ui.Rect.fromLTWH(
          0, 0, image.width.toDouble(), image.height.toDouble());
      final target = _contain(source.size, rect.deflate(8));
      canvas.drawImageRect(image, source, target,
          ui.Paint()..filterQuality = ui.FilterQuality.high);
    } on Object {
      canvas.drawRect(rect, ui.Paint()..color = const ui.Color(0xFFF7F8FA));
      _text(canvas, 'C', rect.left, rect.top + rect.height * 0.38, rect.width,
          70, crimson,
          weight: ui.FontWeight.w900, align: ui.TextAlign.center);
    }
    canvas.restore();
  }

  void _drawImageLabel(
    ui.Canvas canvas,
    String label,
    ui.Rect rect,
    ui.Color text,
  ) {
    if (label.isEmpty) return;
    final labelRect =
        ui.Rect.fromLTWH(rect.left, rect.bottom - 26, rect.width, 26);
    canvas.drawRect(labelRect, ui.Paint()..color = const ui.Color(0xEFFFFFFF));
    _text(canvas, label, labelRect.left + 4, labelRect.top + 5,
        labelRect.width - 8, 13, text,
        weight: ui.FontWeight.w800, align: ui.TextAlign.center);
  }

  void _drawMatrix(
    ui.Canvas canvas,
    ProductDraft product,
    ui.Rect rect,
    ui.Color crimson,
    ui.Color softHeader,
    ui.Color text,
    ui.Color border,
  ) {
    canvas.save();
    canvas.clipRect(rect);
    final matrix = variationPriceMatrix(product.variations);
    final sizes = matrix.sizes;
    final finishes = matrix.finishes;
    if (sizes.isEmpty || finishes.isEmpty) {
      final priceRect = ui.Rect.fromLTWH(rect.left, rect.top, 260, 58);
      canvas.drawRect(priceRect, ui.Paint()..color = softHeader);
      _text(canvas, _simplePrice(product), priceRect.left + 16,
          priceRect.top + 15, priceRect.width - 32, 24, crimson,
          weight: ui.FontWeight.w800);
      canvas.restore();
      return;
    }

    final sizeGroups = _chunks(sizes, 7);
    final gap = sizeGroups.length > 1 ? 10.0 : 0.0;
    final totalRows = sizeGroups.length * (finishes.length + 1);
    final availableHeight = rect.height - gap * (sizeGroups.length - 1);
    final rowHeight =
        math.max(27.0, math.min(43.0, availableHeight / totalRows));
    final headerFont = math.max(13.0, math.min(18.0, rowHeight * 0.44));
    final bodyFont = math.max(12.0, math.min(17.0, rowHeight * 0.40));
    var tableTop = rect.top;

    for (final group in sizeGroups) {
      final columns = ['Finish', ...group];
      final firstColumn = rect.width * (group.length >= 6 ? 0.22 : 0.24);
      final otherColumn = (rect.width - firstColumn) / group.length;
      canvas.drawRect(
          ui.Rect.fromLTWH(rect.left, tableTop, rect.width, rowHeight),
          ui.Paint()..color = softHeader);
      for (var col = 0; col < columns.length; col++) {
        final x = col == 0
            ? rect.left
            : rect.left + firstColumn + (col - 1) * otherColumn;
        final width = col == 0 ? firstColumn : otherColumn;
        final fittedHeaderFont = _fitSingleLineFont(
          columns[col],
          width - 12,
          headerFont,
          13,
        );
        _text(
            canvas,
            columns[col],
            x + 6,
            tableTop + (rowHeight - fittedHeaderFont) / 2,
            width - 12,
            fittedHeaderFont,
            text,
            weight: ui.FontWeight.w800,
            align: col == 0 ? ui.TextAlign.left : ui.TextAlign.center);
        canvas.drawLine(ui.Offset(x, tableTop),
            ui.Offset(x, tableTop + rowHeight), ui.Paint()..color = border);
      }
      canvas.drawLine(
          ui.Offset(rect.right, tableTop),
          ui.Offset(rect.right, tableTop + rowHeight),
          ui.Paint()..color = border);

      for (var row = 0; row < finishes.length; row++) {
        final y = tableTop + rowHeight * (row + 1);
        final finish = finishes[row];
        canvas.drawRect(
            ui.Rect.fromLTWH(rect.left, y, rect.width, rowHeight),
            ui.Paint()
              ..color = row.isEven
                  ? const ui.Color(0xFFFFFFFF)
                  : const ui.Color(0xFFF7F8FA));
        _text(canvas, finish.isEmpty ? 'Price' : finish, rect.left + 8,
            y + (rowHeight - bodyFont) / 2, firstColumn - 16, bodyFont, text);
        for (var col = 0; col < group.length; col++) {
          final x = rect.left + firstColumn + col * otherColumn;
          _text(
              canvas,
              _matrixPrice(matrix.prices[matrix.key(finish, group[col])]),
              x + 6,
              y + (rowHeight - bodyFont) / 2,
              otherColumn - 12,
              bodyFont,
              text,
              align: ui.TextAlign.center);
          canvas.drawLine(ui.Offset(x, y), ui.Offset(x, y + rowHeight),
              ui.Paint()..color = border);
        }
        canvas.drawLine(ui.Offset(rect.right, y),
            ui.Offset(rect.right, y + rowHeight), ui.Paint()..color = border);
        canvas.drawLine(ui.Offset(rect.left, y + rowHeight),
            ui.Offset(rect.right, y + rowHeight), ui.Paint()..color = border);
      }
      tableTop += rowHeight * (finishes.length + 1) + gap;
    }
    canvas.restore();
  }

  Future<Uint8List> _imageBytes(String path) async {
    final uri = Uri.tryParse(path);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final client = HttpClient();
      try {
        final response = await (await client.getUrl(uri)).close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException('Image returned ${response.statusCode}',
              uri: uri);
        }
        final data = <int>[];
        await for (final chunk in response) {
          data.addAll(chunk);
        }
        return Uint8List.fromList(data);
      } finally {
        client.close(force: true);
      }
    }
    return File(path).readAsBytes();
  }

  ui.Rect _contain(ui.Size source, ui.Rect target) {
    final scale =
        math.min(target.width / source.width, target.height / source.height);
    final width = source.width * scale;
    final height = source.height * scale;
    return ui.Rect.fromLTWH(target.left + (target.width - width) / 2,
        target.top + (target.height - height) / 2, width, height);
  }

  void _text(ui.Canvas canvas, String value, double x, double y, double width,
      double size, ui.Color color,
      {ui.FontWeight weight = ui.FontWeight.normal,
      ui.TextAlign align = ui.TextAlign.left,
      String family = 'Segoe UI'}) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: weight,
      textAlign: align,
      maxLines: 2,
      ellipsis: '...',
    ))
      ..pushStyle(ui.TextStyle(color: color, fontWeight: weight))
      ..addText(value);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: width));
    canvas.drawParagraph(paragraph, ui.Offset(x, y));
  }

  double _fitSingleLineFont(
      String value, double width, double preferred, double minimum) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontFamily: 'Segoe UI',
      fontSize: preferred,
      fontWeight: ui.FontWeight.w800,
      maxLines: 1,
    ))
      ..addText(value);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: width));
    final naturalWidth = paragraph.maxIntrinsicWidth;
    paragraph.dispose();
    if (naturalWidth <= width) return preferred;
    return math.max(minimum, preferred * width / naturalWidth * 0.98);
  }

  int _productsPerPage(List<ProductDraft> products) => 3;

  List<List<T>> _chunks<T>(List<T> values, int size) => [
        for (var start = 0; start < values.length; start += size)
          values.sublist(start, math.min(start + size, values.length)),
      ];

  String _pageTitle(List<ProductDraft> products) {
    final categories = products
        .map((product) => cleanText(product.category))
        .where((value) => value.isNotEmpty)
        .toSet();
    return categories.length == 1 ? categories.first : 'Selected Products';
  }

  String _finishLine(ProductDraft product, VariationMatrix matrix) {
    final finishes = matrix.finishes
        .map(cleanText)
        .where((finish) => finish.isNotEmpty)
        .toList();
    if (finishes.isNotEmpty) return finishes.take(4).join(', ');
    return cleanText(product.finishColor);
  }

  List<String> _imagePaths(ProductDraft product) {
    final paths = <String>[];
    final seen = <String>{};
    for (final value in [...product.imagePaths, product.imagePath]) {
      final path = cleanText(value);
      if (path.isNotEmpty && seen.add(path)) paths.add(path);
    }
    return paths;
  }

  String _imageFinishTag(ProductDraft product, String path) {
    for (final entry in product.imageFinishTags.entries) {
      if (cleanText(entry.key) == path) return cleanText(entry.value);
    }
    return '';
  }

  String _imageUri(String path) {
    final uri = Uri.tryParse(path);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return uri.toString();
    }
    return Uri.file(path).toString();
  }

  String _matrixPrice(String? value) {
    final clean = cleanText(value);
    return clean.isEmpty ? '-' : formatCompactPrice(clean);
  }

  String _price(String? value) {
    final clean = cleanText(value);
    return clean.isEmpty ? '-' : 'Rs. ${formatCompactPrice(clean)}';
  }

  String _simplePrice(ProductDraft product) {
    final direct = cleanText(product.sellingPrice);
    if (direct.isNotEmpty) return _price(direct);
    for (final variation in product.variations) {
      if (cleanText(variation.price).isNotEmpty) return _price(variation.price);
    }
    return 'Price pending';
  }

  String _ensureExtension(String path, String extension) =>
      path.toLowerCase().endsWith(extension) ? path : '$path$extension';

  String _numberedPath(String path, int page, String extension) {
    final clean = _ensureExtension(path, extension);
    return '${clean.substring(0, clean.length - extension.length)}_page_$page$extension';
  }

  String? _edgeExecutable() {
    final candidates = <String>[
      if (Platform.environment['PROGRAMFILES(X86)'] case final path?)
        '$path\\Microsoft\\Edge\\Application\\msedge.exe',
      if (Platform.environment['PROGRAMFILES'] case final path?)
        '$path\\Microsoft\\Edge\\Application\\msedge.exe',
      if (Platform.environment['LOCALAPPDATA'] case final path?)
        '$path\\Microsoft\\Edge\\Application\\msedge.exe',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  void _requireProducts(List<ProductDraft> products) {
    if (products.isEmpty) {
      throw const FileSystemException('Select at least one product to export.');
    }
  }

  String _html(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
