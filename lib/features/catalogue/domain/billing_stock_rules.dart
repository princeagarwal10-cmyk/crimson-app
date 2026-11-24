import 'catalogue_models.dart';
import 'simple_bill.dart';

/// Calculates an outward voucher for a bill, without mutating any state.
/// The database must atomically enforce one bill per order and save both the
/// bill and any voucher; this local check alone cannot prevent concurrent writes.
StockVoucherDraft? planBillStockVoucher({
  required CustomerOrderDraft order,
  required Iterable<StockVoucherDraft> existingVouchers,
  required String billNumber,
  required DateTime createdAt,
}) {
  final preview = previewSimpleBill(order);
  if (billNumber.trim().isEmpty) throw StateError('Bill number is required.');
  final reference = 'ORDER:${order.id}';
  if (existingVouchers.any((voucher) => voucher.reference == reference)) {
    // Orders dispatched by an older release already have a stock deduction.
    return null;
  }
  final items = order.items
      .where((line) => line.dispatchedQuantity > 0)
      .map(
        (line) => StockVoucherItemDraft(
          stockItemId: line.stockItemId,
          productId: line.productId,
          productName: line.productName,
          stockSku: line.stockSku,
          brand: line.brand,
          size: line.size,
          finish: line.finish,
          quantity: line.dispatchedQuantity,
          notes: '${preview.orderNumber} / ${billNumber.trim()}',
        ),
      )
      .toList(growable: false);
  return StockVoucherDraft(
    type: StockVoucherType.outward,
    voucherNumber: 'BILL-${billNumber.trim()}',
    date: createdAt.toIso8601String(),
    partyName: order.customerName,
    reference: reference,
    notes: 'Stock outward for bill ${billNumber.trim()}',
    items: items,
    createdAt: createdAt.toUtc().toIso8601String(),
  );
}
