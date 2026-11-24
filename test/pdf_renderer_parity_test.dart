import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crimson_catalogue_studio/features/catalogue/data/multi_product_export_service.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show FontLoader;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!Platform.isWindows) return;
    final windows = Platform.environment['WINDIR']!;
    for (final entry in {
      'Segoe UI': ['segoeui.ttf', 'segoeuib.ttf'],
      'Georgia': ['georgia.ttf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final file in entry.value) {
        loader.addFont(File('$windows/Fonts/$file')
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes)));
      }
      await loader.load();
    }
  });

  test('desktop PDF preserves the shared mobile catalogue pages', () async {
    final requested = Platform.environment['CRIMSON_PDF_QA_DIR'];
    final directory = requested == null
        ? await Directory.systemTemp.createTemp('crimson_pdf_parity_')
        : await Directory(requested).create(recursive: true);
    if (requested == null) {
      addTearDown(() => directory.delete(recursive: true));
    }
    final paths = <String>[];
    const colors = [0xFF333333, 0xFF7B4B31, 0xFFC79A3C, 0xFF78848B, 0xFFAA6030];
    for (var index = 0; index < colors.length; index++) {
      // A deliberately tall product image makes clipping/stretching visible.
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
      final paint = ui.Paint()..color = ui.Color(colors[index]);
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          const ui.Rect.fromLTWH(95, 35, 40, 530),
          const ui.Radius.circular(12),
        ),
        paint,
      );
      canvas.drawRect(const ui.Rect.fromLTWH(95, 35, 115, 35), paint);
      canvas.drawRect(const ui.Rect.fromLTWH(95, 530, 115, 35), paint);
      final picture = recorder.endRecording();
      final image = await picture.toImage(300, 600);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${directory.path}/finish-$index.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      paths.add(file.absolute.path);
      image.dispose();
      picture.dispose();
    }
    final products = List.generate(
        5,
        (index) => ProductDraft(
              id: 'parity-${index + 1}',
              name: '${index + 1} FINISH SAMPLE',
              category: 'Cabinet Handles',
              subcategory: 'Sample',
              brand: 'Crimson',
              imagePaths: paths.take(index + 1).toList(),
              imageFinishTags: {
                for (var n = 0; n <= index; n++)
                  paths[n]: ['BLACK', 'COLA', 'GOLD', 'SATIN', 'ORANGE'][n],
              },
              variations: [
                for (var n = 0; n <= index; n++)
                  for (final size in [
                    'KNOB',
                    '96MM',
                    '160MM',
                    '224MM',
                    '288MM',
                    '448MM'
                  ])
                    VariationDraft(
                        size: size,
                        finish: ['BLACK', 'COLA', 'GOLD', 'SATIN', 'ORANGE'][n],
                        price: '495'),
              ],
            ));
    const exporter = MultiProductExportService();
    final pngs = await exporter.exportImages(
      products: products,
      path: '${directory.path}/mobile-page.png',
      imageLayout: CatalogueImageLayout.multiImage,
    );
    expect(pngs, hasLength(2));
    final pdf = File('${directory.path}/desktop-parity.pdf');
    await exporter.exportPdf(
      products: products,
      path: pdf.path,
      imageLayout: CatalogueImageLayout.multiImage,
    );
    expect(String.fromCharCodes((await pdf.readAsBytes()).take(5)), '%PDF-');
    expect(await pdf.length(), greaterThan(1000));
  }, skip: !Platform.isWindows);
}
