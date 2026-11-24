import 'dart:io';

import 'package:crimson_catalogue_studio/features/catalogue/data/multi_product_export_service.dart';
import 'package:crimson_catalogue_studio/features/catalogue/data/premium_export_service.dart';
import 'package:crimson_catalogue_studio/features/catalogue/data/windows_pdf_writer.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _LockedTemporaryDirectory extends Fake implements Directory {
  @override
  Future<bool> exists() async => true;

  @override
  Future<Directory> delete({bool recursive = false}) async =>
      throw const FileSystemException('The browser still has a file open.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory scratch;
  late ProductDraft product;

  setUp(() async {
    scratch = await Directory('build').createTemp('pdf-save-regression-');
    final image = await File('assets/branding/crimson_wordmark.png')
        .copy('${scratch.path}/sample image.png');
    product = ProductDraft(
      id: 'pdf-regression-only',
      name: 'PDF Export Check',
      category: 'Cabinet Handles',
      subcategory: 'Test',
      brand: 'Crimson',
      imagePaths: [image.absolute.path],
      variations: const [
        VariationDraft(size: '96MM', finish: 'Black', price: '300'),
        VariationDraft(size: '160MM', finish: 'Black', price: '495'),
      ],
    );
  });

  tearDown(() => WindowsPdfWriter.cleanup(scratch));

  test('locked temporary profile cannot turn PDF success into an error',
      () async {
    await WindowsPdfWriter.cleanup(_LockedTemporaryDirectory());
  });

  test(
      'multi-image PDF saves to a spaced Unicode path and replaces a prior PDF',
      () async {
    final paths = <String>[];
    for (var index = 0; index < 3; index++) {
      final image = await File(product.imagePaths.single)
          .copy('${scratch.path}/finish $index.png');
      paths.add(image.absolute.path);
    }
    final item = product.copyWith(
      imagePaths: paths,
      imageFinishTags: {
        for (var i = 0; i < paths.length; i++) paths[i]: 'Finish $i'
      },
    );
    final output = File('${scratch.path}/Customer Catalogues/रंग & sizes.pdf');
    await output.parent.create();
    await output.writeAsString('prior output');
    await const MultiProductExportService().exportPdf(
      products: [item],
      path: output.absolute.path,
      imageLayout: CatalogueImageLayout.multiImage,
    );
    final bytes = await output.readAsBytes();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
    expect(
        await output.parent.list().where((entry) => entry is Directory).length,
        0);
  }, skip: !Platform.isWindows);

  test('spotlight PDF also uses the safe writer', () async {
    final output = File('${scratch.path}/Spotlight sample.pdf');
    await const PremiumExportService().exportProductSpotlightPdf(
      product: product,
      path: output.absolute.path,
    );
    expect(String.fromCharCodes((await output.readAsBytes()).take(5)), '%PDF-');
  }, skip: !Platform.isWindows);

  test(
      'unwritable destination reports saving failure and preserves its contents',
      () async {
    final blocked = await Directory('${scratch.path}/occupied.pdf').create();
    final original = File('${blocked.path}/keep.txt');
    await original.writeAsString('existing contents');
    await expectLater(
      const MultiProductExportService().exportPdf(
        products: [product],
        path: blocked.absolute.path,
      ),
      throwsA(isA<FileSystemException>().having(
        (error) => error.message,
        'actionable save error',
        contains('The PDF was generated, but could not be saved'),
      )),
    );
    expect(await original.readAsString(), 'existing contents');
  }, skip: !Platform.isWindows);

  test('converter failure never accepts or overwrites a previous output',
      () async {
    final output = File('${scratch.path}/existing.pdf');
    await output.writeAsString('%PDF-prior output to preserve');
    final temporary = await Directory('${scratch.path}/conversion').create();
    final html = await File('${temporary.path}/input.html')
        .writeAsString('<html></html>');
    await expectLater(
      const WindowsPdfWriter().write(
        edgeExecutable:
            '${Platform.environment['WINDIR']}\\System32\\where.exe',
        html: html,
        temporary: temporary,
        path: output.absolute.path,
      ),
      throwsA(isA<FileSystemException>().having(
        (error) => error.message,
        'generation failure',
        contains('PDF generation failed'),
      )),
    );
    expect(await output.readAsString(), '%PDF-prior output to preserve');
  }, skip: !Platform.isWindows);
}
