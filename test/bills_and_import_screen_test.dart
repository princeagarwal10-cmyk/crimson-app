import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crimson_catalogue_studio/features/catalogue/data/cloud_catalogue_repository.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/customer_bill.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/tally_stock_import.dart';
import 'package:crimson_catalogue_studio/features/catalogue/presentation/customer_bills_screen.dart';
import 'package:crimson_catalogue_studio/features/catalogue/presentation/tally_stock_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBillsRepository extends CloudCatalogueRepository {
  FakeBillsRepository()
      : super(const CloudCatalogueSettings(
            supabaseUrl: 'http://localhost', anonKey: 'test'));
  @override
  Future<List<CustomerBill>> pullBills() async => [
        const CustomerBill(
            id: '1',
            billNumber: 'BILL-1',
            orderId: 'order',
            createdAt: '2026-11-24',
            payload: {
              'customerName': 'ABC Hardware',
              'orderNumber': 'ORD-1',
              'total': 342,
              'items': [
                {
                  'productName': 'Handle',
                  'quantity': 4,
                  'unitPrice': 100,
                  'lineTotal': 360
                }
              ]
            })
      ];
}

class FakeTallyRepository extends CloudCatalogueRepository {
  FakeTallyRepository()
      : super(const CloudCatalogueSettings(
            supabaseUrl: 'http://localhost', anonKey: 'test'));
  TallyStockLink? saved;
  Map<String, Object?>? committed;
  @override
  Future<Map<String, TallyStockLink>> pullTallyLinks() async => {};
  @override
  Future<VersionedCataloguePayload> pullVersionedForStock() async =>
      VersionedCataloguePayload(payload: {
        'products': [
          ProductDraft(
                  id: 'p',
                  name: 'AKSH HANDLE 6',
                  sku: 'sku',
                  category: 'handles',
                  subcategory: 'test')
              .toJson()
        ],
        'stockVouchers': []
      }, revision: 'revision');
  @override
  Future<void> saveTallyLink(TallyStockRow row, TallyStockLink link) async {
    saved = link;
  }

  @override
  Future<bool> writeStockPayloadIfUnchanged(
      {required String revision, required Map<String, Object?> payload}) async {
    committed = payload;
    return true;
  }
}

void main() {
  testWidgets('customer can view a returned bill and its dispatched line',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: CustomerBillsScreen(
            repository: () async => FakeBillsRepository())));
    await tester.pumpAndSettle();
    expect(find.text('BILL-1'), findsOneWidget);
    await tester.tap(find.text('BILL-1'));
    await tester.pumpAndSettle();
    expect(find.text('Handle'), findsOneWidget);
    expect(find.text('Customer: ABC Hardware'), findsOneWidget);
    expect(find.text('Total: Rs. 342'), findsOneWidget);
  });

  testWidgets('stock import opens with no data or write action',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: TallyStockReviewScreen(variations: [])));
    expect(find.text('Choose Excel file'), findsOneWidget);
    expect(find.text('Apply reviewed stock'), findsNothing);
  });

  testWidgets('an admin can review a spreadsheet and save a product link',
      (tester) async {
    final path = await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('tally_ui_');
      addTearDown(() => directory.delete(recursive: true));
      final archive = Archive()
        ..addFile(ArchiveFile.string('xl/worksheets/sheet1.xml',
            '<worksheet><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>AKSH HANDLE 6</t></is></c><c r="B1" t="inlineStr"><is><t>24 PCS</t></is></c></row></sheetData></worksheet>'));
      final file = File('${directory.path}${Platform.pathSeparator}stock.xlsx');
      await file.writeAsBytes(ZipEncoder().encode(archive)!);
      return file.path;
    });
    final repository = FakeTallyRepository();
    await tester.pumpWidget(MaterialApp(
        home: TallyStockReviewScreen(variations: const [
      TallyMatchCandidate(
          targetKey: 'p|sku||',
          label: 'AKSH HANDLE 6',
          productId: 'p',
          productName: 'AKSH HANDLE 6',
          stockSku: 'sku')
    ], repository: () async => repository, pickWorkbook: () async => path)));
    await tester.tap(find.text('Choose Excel file'));
    await tester.pumpAndSettle();
    expect(find.text('AKSH HANDLE 6'), findsOneWidget);
    await tester.tap(find.text('Link'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AKSH HANDLE 6').last);
    await tester.pumpAndSettle();
    expect(repository.saved?.targetKey, 'p|sku||');
    expect(find.textContaining('1 saved links'), findsOneWidget);
    await tester.tap(find.text('Set Tally snapshot date and time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply reviewed stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply stock'));
    await tester.pumpAndSettle();
    final vouchers = repository.committed?['stockVouchers'] as List;
    expect((vouchers.single['items'] as List).single['quantity'], 24);
  });
}
