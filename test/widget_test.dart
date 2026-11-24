import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:crimson_catalogue_studio/features/catalogue/data/local_catalogue_repository.dart';
import 'package:crimson_catalogue_studio/features/catalogue/data/sample_catalogue_data.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';
import 'package:crimson_catalogue_studio/main.dart';

class _MemoryRepository extends LocalCatalogueRepository {
  CatalogueState state = sampleCatalogueState;
  @override
  Future<CatalogueState> load() async => state;
  @override
  Future<void> save(CatalogueState next) async { state = next; }
}

void main() {
  testWidgets('Crimson Flutter Version 1.0 catalogue dashboard opens',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _MemoryRepository();

    await tester.pumpWidget(CrimsonCatalogueStudioApp(
      repository: repository,
      enableCloud: false,
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Crimson'), findsWidgets);
    expect(find.text('Catalogue Studio'), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Recent Products'), findsOneWidget);
    expect(find.text('W Astha'), findsWidgets);
  });

  testWidgets('add product uses the four-step catalogue builder',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _MemoryRepository();

    await tester.pumpWidget(CrimsonCatalogueStudioApp(
      repository: repository,
      enableCloud: false,
    ));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Add Product').first);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Product details'), findsOneWidget);
    expect(find.text('Product information'), findsOneWidget);
    expect(find.text('Product preview'), findsOneWidget);
    expect(find.byTooltip('Add category'), findsOneWidget);

    await tester.tap(find.text('Continue to photos'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Product photos'), findsOneWidget);
    expect(find.text('Browse photos'), findsOneWidget);

    await tester.tap(find.text('Continue to variations'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Variations and pricing'), findsOneWidget);
    expect(find.text('Price matrix'), findsOneWidget);

    await tester.tap(find.text('Review product'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Review new product'), findsOneWidget);
    expect(find.text('Catalogue summary'), findsOneWidget);
    expect(find.text('Save product'), findsOneWidget);
  });
}
