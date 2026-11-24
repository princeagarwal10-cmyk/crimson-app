import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/tally_stock_apply.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/tally_stock_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('records an explicit zero for a variation with no stock history', () {
    final product = ProductDraft(
        id: 'p', name: 'Handle', sku: 'p-sku', category: 'c', subcategory: 's');
    final row = parseTallyStockRows([
      ['Handle', '0 PCS']
    ], itemColumn: 0, quantityColumn: 1)
        .single;
    const candidate = TallyMatchCandidate(
        targetKey: 'p|p-sku||',
        label: 'Handle',
        productId: 'p',
        productName: 'Handle',
        stockSku: 'p-sku');
    final links = {
      row.sourceKey: TallyStockLink(
          sourceKey: row.sourceKey, targetKey: candidate.targetKey, unit: 'PCS')
    };
    final preview = prepareTallyStockApply(
        payload: {
          'products': [product.toJson()]
        },
        rows: [row],
        links: links,
        candidates: [candidate],
        snapshotAt: DateTime.utc(2026, 11, 24),
        now: DateTime.utc(2026, 11, 25));
    expect(preview.writtenCount, 1);
    final voucher = (preview.payload['stockVouchers'] as List).single as Map;
    expect((voucher['items'] as List).single['quantity'], 0);
  });
  test('creates only an adjustment and a repeat import does not double stock',
      () {
    final existing = StockVoucherDraft(
        type: StockVoucherType.inward,
        voucherNumber: 'STK1',
        date: '2026-11-20T10:00:00Z',
        createdAt: '2026-11-20T10:00:00Z',
        items: const [
          StockVoucherItemDraft(
              productId: 'p',
              productName: 'Handle',
              stockSku: 'sku',
              size: '10',
              finish: 'Black',
              quantity: 20)
        ]);
    final product = ProductDraft(
        id: 'p',
        name: 'Handle',
        sku: 'sku',
        category: 'c',
        subcategory: 's',
        variations: const [
          VariationDraft(size: '10', finish: 'Black', price: '1')
        ]);
    final payload = <String, Object?>{
      'stockVouchers': [existing.toJson()],
      'products': [product.toJson()],
      'unrelated': 'preserved'
    };
    final row = parseTallyStockRows([
      ['Handle', '25 PCS']
    ], itemColumn: 0, quantityColumn: 1)
        .single;
    const candidate = TallyMatchCandidate(
        targetKey: 'p|sku|10|Black',
        label: 'Handle',
        productId: 'p',
        productName: 'Handle',
        stockSku: 'sku',
        size: '10',
        finish: 'Black');
    final links = {
      row.sourceKey: TallyStockLink(
          sourceKey: row.sourceKey, targetKey: candidate.targetKey, unit: 'PCS')
    };
    final snapshot = DateTime.utc(2026, 11, 21);
    final now = DateTime.utc(2026, 11, 22);
    final preview = prepareTallyStockApply(
        payload: payload,
        rows: [row],
        links: links,
        candidates: [candidate],
        snapshotAt: snapshot,
        now: now);
    expect(preview.writtenCount, 1);
    expect(preview.plan.adjustments.single.difference, 5);
    expect(preview.payload['unrelated'], 'preserved');
    expect((preview.payload['stockVouchers'] as List).length, 2);
    final repeated = prepareTallyStockApply(
        payload: preview.payload,
        rows: [row],
        links: links,
        candidates: [candidate],
        snapshotAt: now,
        now: now.add(const Duration(seconds: 1)));
    expect(repeated.writtenCount, 0);
  });

  test('does not apply movements newer than snapshot or unconverted packets',
      () {
    final v = StockVoucherDraft(
        type: StockVoucherType.inward,
        voucherNumber: '1',
        date: '2026-11-22T00:00:00Z',
        items: const [
          StockVoucherItemDraft(
              productId: 'p',
              productName: 'Handle',
              stockSku: 'p-sku',
              quantity: 2)
        ]);
    final rows = parseTallyStockRows([
      ['Handle', '5 PCS'],
      ['Packet', '2 PKT']
    ], itemColumn: 0, quantityColumn: 1);
    const a = TallyMatchCandidate(
        targetKey: 'p|p-sku||',
        label: 'Handle',
        productId: 'p',
        stockSku: 'p-sku',
        productName: 'Handle');
    const b = TallyMatchCandidate(
        targetKey: 'q|q-sku||',
        label: 'Packet',
        productId: 'q',
        stockSku: 'q-sku',
        productName: 'Packet');
    final links = {
      rows[0].sourceKey: TallyStockLink(
          sourceKey: rows[0].sourceKey, targetKey: a.targetKey, unit: 'PCS'),
      rows[1].sourceKey: TallyStockLink(
          sourceKey: rows[1].sourceKey, targetKey: b.targetKey, unit: 'PKT')
    };
    final products = [
      ProductDraft(
          id: 'p',
          name: 'Handle',
          sku: 'p-sku',
          category: 'c',
          subcategory: 's'),
      ProductDraft(
          id: 'q',
          name: 'Packet',
          sku: 'q-sku',
          category: 'c',
          subcategory: 's')
    ];
    final result = prepareTallyStockApply(
        payload: {
          'stockVouchers': [v.toJson()],
          'products': products.map((p) => p.toJson()).toList()
        },
        rows: rows,
        links: links,
        candidates: [a, b],
        snapshotAt: DateTime.utc(2026, 11, 21),
        now: DateTime.utc(2026, 11, 23));
    expect(result.writtenCount, 0);
    expect(result.plan.blocked.length, 2);
    links[rows[1].sourceKey] = TallyStockLink(
        sourceKey: rows[1].sourceKey,
        targetKey: b.targetKey,
        unit: 'PKT',
        multiplier: 10,
        conversionConfirmed: true);
    final withConversion = prepareTallyStockApply(
        payload: {
          'stockVouchers': [v.toJson()],
          'products': products.map((p) => p.toJson()).toList()
        },
        rows: rows,
        links: links,
        candidates: [a, b],
        snapshotAt: DateTime.utc(2026, 11, 21),
        now: DateTime.utc(2026, 11, 23));
    expect(withConversion.writtenCount, 1);
    expect(withConversion.plan.adjustments.single.closing, 20);
  });
}
