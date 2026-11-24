import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/simple_bill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CustomerOrderDraft order(CustomerOrderStatus status) => CustomerOrderDraft(
          id: 'order1',
          orderNumber: 'ORD-1',
          customerType: 'regular',
          customerAccountId: 'hemant',
          customerName: 'Hemant',
          status: status,
          additionalDiscountPercent: 5,
          items: const [
            CustomerOrderItemDraft(
                productId: 'p',
                productName: 'Handle',
                quantity: 10,
                approvedQuantity: 8,
                dispatchedQuantity: 4,
                unitPrice: 100,
                finalDiscount: '10')
          ]);

  test('bill uses dispatched quantities and applies both discounts without tax',
      () {
    final bill = previewSimpleBill(order(CustomerOrderStatus.dispatched));
    expect(bill.lines.single.quantity, 4);
    expect(bill.subtotal, 360);
    expect(bill.total, 342);
    expect(bill.customerAccountId, 'hemant');
  });
  test('approval and packing cannot generate a bill', () {
    expect(() => previewSimpleBill(order(CustomerOrderStatus.confirmed)),
        throwsStateError);
    expect(() => previewSimpleBill(order(CustomerOrderStatus.packed)),
        throwsStateError);
  });
}
