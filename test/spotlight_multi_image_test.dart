import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crimson_catalogue_studio/features/catalogue/data/premium_export_service.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show FontLoader;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory proofDirectory;
  late List<String> imagePaths;

  setUpAll(() async {
    if (Platform.isWindows) {
      final loader = FontLoader('Segoe UI');
      for (final name in ['segoeui.ttf', 'segoeuib.ttf']) {
        loader.addFont(File('${Platform.environment['WINDIR']}/Fonts/$name')
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes)));
      }
      await loader.load();
    }
    proofDirectory = await Directory('build/spotlight-layout-proof').create(
      recursive: true,
    );
    imagePaths = [
      await _writeSolidImage(
        proofDirectory,
        'red.png',
        const ui.Color(0xFFFF0000),
      ),
      await _writeSolidImage(
        proofDirectory,
        'green.png',
        const ui.Color(0xFF00FF00),
      ),
      await _writeSolidImage(
        proofDirectory,
        'blue.png',
        const ui.Color(0xFF0000FF),
      ),
      await _writeSolidImage(
        proofDirectory,
        'yellow.png',
        const ui.Color(0xFFFFFF00),
      ),
      await _writeSolidImage(
        proofDirectory,
        'purple.png',
        const ui.Color(0xFF800080),
      ),
    ];
  });

  test('spotlight image supports clean borderless 1 to 4 image layouts',
      () async {
    const service = PremiumExportService();
    for (var count = 1; count <= 4; count++) {
      final product = _productWithImages(imagePaths.take(count).toList());
      final output = File(
        '${proofDirectory.path}/spotlight-$count-images.png',
      );
      await service.exportProductSpotlightImage(
        product: product,
        path: output.absolute.path,
      );
      expect(await output.exists(), isTrue);
      expect(await output.length(), greaterThan(1000));

      final html = service.buildProductSpotlightHtml(product);
      expect(html, contains('class="photo count-$count"'));
      expect(RegExp('class="photo-tile"').allMatches(html).length, count);
      expect(html, isNot(contains('MATT BLACK')));
      expect(html, isNot(contains('ROSE GOLD')));
      expect(
        html,
        isNot(contains('.photo-tile { border:')),
      );
    }
  });

  test('three-image spotlight keeps all image areas equal-sized', () async {
    final file = File('${proofDirectory.path}/spotlight-3-images.png');
    if (!await file.exists()) {
      await const PremiumExportService().exportProductSpotlightImage(
        product: _productWithImages(imagePaths.take(3).toList()),
        path: file.absolute.path,
      );
    }

    final codec = await ui.instantiateImageCodec(await file.readAsBytes());
    final image = (await codec.getNextFrame()).image;
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(bytes, isNotNull);
    final pixels = bytes!.buffer.asUint8List();
    final red = _colorBounds(pixels, image.width, image.height, 0);
    final green = _colorBounds(pixels, image.width, image.height, 1);
    final blue = _colorBounds(pixels, image.width, image.height, 2);

    expect(red, isNotNull);
    expect(green, isNotNull);
    expect(blue, isNotNull);
    expect((red!.width - green!.width).abs(), lessThanOrEqualTo(2));
    expect((green.width - blue!.width).abs(), lessThanOrEqualTo(2));
    expect((red.height - green.height).abs(), lessThanOrEqualTo(2));
    expect((green.height - blue.height).abs(), lessThanOrEqualTo(2));
    expect(red.centerX, closeTo((green.centerX + blue.centerX) / 2, 2));
    expect(red.centerY, lessThan(green.centerY));
    expect(green.centerY, closeTo(blue.centerY, 2));
  });

  test('three-image spotlight PDF is generated successfully', () async {
    final output = File(
      '${proofDirectory.path}/spotlight-3-images.pdf',
    );
    await const PremiumExportService().exportProductSpotlightPdf(
      product: _productWithImages(imagePaths.take(3).toList()),
      path: output.absolute.path,
    );
    final bytes = await output.readAsBytes();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  }, skip: !Platform.isWindows);

  test('five photos continue on a second image page', () async {
    const service = PremiumExportService();
    final product = _productWithImages(imagePaths);
    final files = await service.exportProductSpotlightImages(
      product: product,
      path: '${proofDirectory.path}/spotlight-five.png',
    );
    expect(files, hasLength(2));
    expect(files[1], endsWith('_page_2.png'));
    for (final path in files) {
      expect(await File(path).length(), greaterThan(1000));
    }
    final html = service.buildProductSpotlightHtml(product);
    expect(RegExp('class="photo-tile"').allMatches(html).length, 5);
    expect(RegExp('class="page"').allMatches(html).length, 2);
    expect(html, isNot(contains('class="more"')));
    final htmlFile = File('${proofDirectory.path}/spotlight-five.html');
    await service.exportProductSpotlightHtml(
        product: product, path: htmlFile.absolute.path);
    expect(await htmlFile.exists(), isTrue);
  });

  test('five photos produce a multi-page Windows PDF', () async {
    final file = File('${proofDirectory.path}/spotlight-five.pdf');
    await const PremiumExportService().exportProductSpotlightPdf(
      product: _productWithImages(imagePaths),
      path: file.absolute.path,
    );
    expect(String.fromCharCodes((await file.readAsBytes()).take(5)), '%PDF-');
  }, skip: !Platform.isWindows);

  test('wide and long variation tables continue without dropping values',
      () async {
    final product = ProductDraft(
      name: 'A LONG MORTISE PRODUCT NAME THAT SHOULD STAY ABOVE THE PHOTOS',
      category: 'Mortise Locks',
      subcategory: 'Fullart',
      brand: 'Crimson',
      imagePaths: imagePaths.take(2).toList(),
      variations: [
        for (var finish = 1; finish <= 6; finish++)
          for (var size = 1; size <= 7; size++)
            VariationDraft(
              size: 'SIZE $size',
              finish: 'FINISH $finish',
              price: '${100 * finish + size}',
            ),
      ],
    );
    const service = PremiumExportService();
    final pages = await service.renderProductSpotlightPages(product);
    expect(pages, hasLength(4));
    final html = service.buildProductSpotlightHtml(product);
    expect(RegExp('class="page(?: table-only)?"').allMatches(html).length, 4);
    expect(html, contains('SIZE 7'));
    expect(html, contains('FINISH 6'));
    expect(html, contains('Rs. 607'));
    expect(html, contains('MORTISE LOCKS'));
    expect(html, isNot(contains('<div class="brand">')));
  });

  test('white photo margins are trimmed so hardware fills the page', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
    canvas.drawRect(const ui.Rect.fromLTWH(270, 90, 72, 420),
        ui.Paint()..color = const ui.Color(0xFF292929));
    canvas.drawRect(const ui.Rect.fromLTWH(300, 260, 185, 52),
        ui.Paint()..color = const ui.Color(0xFF292929));
    final image = await recorder.endRecording().toImage(600, 600);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final photo = File('${proofDirectory.path}/white-backed-handle.png');
    await photo.writeAsBytes(bytes!.buffer.asUint8List());

    final output = File('${proofDirectory.path}/white-handle-spotlight.png');
    await const PremiumExportService().exportProductSpotlightImage(
      product: _productWithImages([photo.absolute.path]),
      path: output.absolute.path,
    );
    final codec = await ui.instantiateImageCodec(await output.readAsBytes());
    final result = (await codec.getNextFrame()).image;
    final rgba = await result.toByteData(format: ui.ImageByteFormat.rawRgba);
    final pixels = rgba!.buffer.asUint8List();
    var top = 1006;
    var bottom = 316;
    for (var y = 316; y < 1006; y++) {
      for (var x = 70; x < 1130; x++) {
        final offset = (y * result.width + x) * 4;
        if (pixels[offset] < 75 &&
            pixels[offset + 1] < 75 &&
            pixels[offset + 2] < 75) {
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
    }
    expect(bottom - top, greaterThan(500));
  });
}

ProductDraft _productWithImages(List<String> paths) {
  return ProductDraft(
    id: 'spotlight-layout-proof',
    name: 'Equal Image Layout',
    category: 'Cabinet Handles',
    subcategory: 'Welset',
    brand: 'Crimson',
    imagePaths: paths,
    imageFinishTags: {
      if (paths.isNotEmpty) paths.first: 'MATT BLACK',
      if (paths.length > 1) paths[1]: 'ROSE GOLD',
    },
    variations: const [
      VariationDraft(size: '96MM', finish: 'Matt Black', price: '300'),
      VariationDraft(size: '160MM', finish: 'Rose Gold', price: '495'),
    ],
  );
}

Future<String> _writeSolidImage(
  Directory directory,
  String name,
  ui.Color color,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 289, 255),
    ui.Paint()..color = color,
  );
  final image = await recorder.endRecording().toImage(289, 255);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${directory.path}/$name');
  await file.writeAsBytes(png!.buffer.asUint8List());
  return file.absolute.path;
}

_Bounds? _colorBounds(
  List<int> pixels,
  int width,
  int height,
  int colorIndex,
) {
  var minX = width;
  var minY = height;
  var maxX = -1;
  var maxY = -1;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      final r = pixels[offset];
      final g = pixels[offset + 1];
      final b = pixels[offset + 2];
      final matches = switch (colorIndex) {
        0 => r > 240 && g < 15 && b < 15,
        1 => r < 15 && g > 240 && b < 15,
        _ => r < 15 && g < 15 && b > 240,
      };
      if (matches) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return null;
  return _Bounds(minX, minY, maxX, maxY);
}

class _Bounds {
  const _Bounds(this.minX, this.minY, this.maxX, this.maxY);

  final int minX;
  final int minY;
  final int maxX;
  final int maxY;

  int get width => maxX - minX + 1;
  int get height => maxY - minY + 1;
  double get centerX => (minX + maxX) / 2;
  double get centerY => (minY + maxY) / 2;
}
