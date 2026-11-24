import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';
import 'package:crimson_catalogue_studio/features/catalogue/presentation/catalogue_manager_screen.dart';
import 'package:crimson_catalogue_studio/features/catalogue/presentation/catalogue_selection_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _state = CatalogueState(
  products: [
    ProductDraft(
      id: 'cabinet-1',
      name: 'Cabinet Handle One',
      category: 'Cabinet Handles',
      subcategory: 'Monza',
      brand: 'Crimson',
    ),
    ProductDraft(
      id: 'cabinet-2',
      name: 'Cabinet Handle Two',
      category: 'Cabinet Handle',
      subcategory: 'Monza',
      brand: 'Crimson',
    ),
  ],
  categories: const [
    CategoryDraft(name: 'Cabinet Handles', subcategories: ['Monza']),
    CategoryDraft(name: 'Cabinet Handle', subcategories: ['Monza']),
  ],
  brands: const ['Crimson'],
);

void main() {
  testWidgets('catalogue manager shows duplicate review and editor on desktop',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CatalogueManagerScreen(
          state: _state,
          onSaveState: (_) {},
          onOpenProducts: () {},
        ),
      ),
    ));

    expect(find.text('Manage catalogue'), findsOneWidget);
    expect(find.text('2 possible duplicate groups'), findsNothing);
    expect(find.text('1 possible duplicate group'), findsOneWidget);
    expect(find.text('Possible duplicate found'), findsOneWidget);
    expect(find.text('Add cover image'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalogue manager remains scrollable on an Android-size screen',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CatalogueManagerScreen(
          state: _state,
          onSaveState: (_) {},
          onOpenProducts: () {},
        ),
      ),
    ));

    expect(find.text('Manage catalogue'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.byType(ListView), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection bar offers bulk live and hidden actions',
      (tester) async {
    var madeLive = 0;
    var madeHidden = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CatalogueSelectionBar(
          selectedCount: 3,
          visibleCount: 8,
          busy: false,
          onSelectAll: () {},
          onClear: () {},
          onExportImage: () {},
          onExportPdf: () {},
          onMakeLive: () => madeLive += 1,
          onMakeHidden: () => madeHidden += 1,
        ),
      ),
    ));

    await tester.tap(find.byTooltip('Change visibility of selected products'));
    await tester.pumpAndSettle();
    expect(find.text('Make selected live'), findsOneWidget);
    expect(find.text('Hide selected products'), findsOneWidget);

    await tester.tap(find.text('Make selected live'));
    await tester.pumpAndSettle();
    expect(madeLive, 1);
    expect(madeHidden, 0);

    await tester.tap(find.byTooltip('Change visibility of selected products'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide selected products'));
    await tester.pumpAndSettle();
    expect(madeLive, 1);
    expect(madeHidden, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact selection bar fits mobile with visibility actions',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CatalogueSelectionBar(
          selectedCount: 3,
          visibleCount: 8,
          busy: false,
          compact: true,
          onSelectAll: () {},
          onClear: () {},
          onExportImage: () {},
          onExportPdf: () {},
          onExportStickers: () {},
          onMakeLive: () {},
          onMakeHidden: () {},
        ),
      ),
    ));

    expect(find.text('3 products selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
