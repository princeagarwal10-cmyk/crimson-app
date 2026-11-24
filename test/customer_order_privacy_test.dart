import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/customer_order_privacy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account ID controls visibility; names, retail and legacy orders do not', () {
    final orders = [
      CustomerOrderDraft(id: 'h', orderNumber: '1', customerName: 'Hemant', customerType: 'regular', customerAccountId: 'hemant-id'),
      CustomerOrderDraft(id: 'r', orderNumber: '2', customerName: 'Rahul', customerType: 'regular', customerAccountId: 'rahul-id'),
      CustomerOrderDraft(id: 'retail', orderNumber: '3', customerName: 'Hemant', customerType: 'retail'),
      CustomerOrderDraft(id: 'legacy', orderNumber: '4', customerName: 'Hemant'),
      CustomerOrderDraft(id: 'invalid', orderNumber: '5', customerName: 'Hemant', customerType: 'retail', customerAccountId: 'hemant-id'),
    ];
    expect(visibleOrdersForCustomer(orders, 'hemant-id').map((o) => o.id), ['h']);
    expect(visibleOrdersForCustomer(orders, 'rahul-id').map((o) => o.id), ['r']);
    expect(visibleOrdersForCustomer(orders, ''), isEmpty);
  });
}
