import 'package:crimson_catalogue_studio/features/catalogue/domain/billing_stock_rules.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final order = CustomerOrderDraft(
      id: 'ord1',
      orderNumber: 'ORD-1',
      customerType: 'regular',
      customerAccountId: 'account',
      customerName: 'ABC',
      status: CustomerOrderStatus.dispatched,
      items: const [
        CustomerOrderItemDraft(
            productId: 'p1',
            productName: 'Handle',
            quantity: 10,
            approvedQuantity: 8,
            dispatchedQuantity: 4,
            unitPrice: 100)
      ]);

  test('billing plans a single outward for dispatched quantity', () {
    final voucher = planBillStockVoucher(
        order: order,
        existingVouchers: [],
        billNumber: '1',
        createdAt: DateTime.utc(2026, 11, 24));
    expect(voucher!.type, StockVoucherType.outward);
    expect(voucher.items.single.quantity, 4);
    expect(voucher.reference, 'ORDER:ord1');
    expect(
        planBillStockVoucher(
            order: order,
            existingVouchers: [voucher],
            billNumber: '1',
            createdAt: DateTime.utc(2026, 11, 24)),
        isNull);
  });

  test('historical dispatch voucher prevents a second stock deduction', () {
    final old = StockVoucherDraft(
        type: StockVoucherType.outward,
        voucherNumber: 'OLD',
        date: '2026-01-01',
        reference: 'ORDER:ord1');
    expect(
        planBillStockVoucher(
            order: order,
            existingVouchers: [old],
            billNumber: '2',
            createdAt: DateTime.utc(2026, 11, 24)),
        isNull);
  });
}
