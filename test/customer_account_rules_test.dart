import 'package:crimson_catalogue_studio/features/catalogue/domain/customer_account_rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';

void main() {
  test('regular customer names are unique after case and whitespace normalization', () {
    expect(validateRegularCustomerName('  HEMANT  KUMAR ', ['Hemant Kumar']), isNotNull);
    expect(validateRegularCustomerName('Rahul', ['Hemant Kumar']), isNull);
    expect(validateRegularCustomerName('   ', []), isNotNull);
  });

  test('user IDs have a normalized, predictable form', () {
    expect(normalizeCustomerUserId(' Hemant01 '), 'hemant01');
    expect(validateCustomerUserId(' Hemant01 '), isNull);
    expect(validateCustomerUserId('hemant@example.com'), isNotNull);
  });

  test('regular orders require an account and retail orders cannot attach one', () {
    expect(validateOrderCustomer(kind: CustomerOrderKind.regular, customerName: 'Hemant'), isNotNull);
    expect(validateOrderCustomer(kind: CustomerOrderKind.regular, customerName: 'Hemant', customerAccountId: 'id-1'), isNull);
    expect(validateOrderCustomer(kind: CustomerOrderKind.retail, customerName: 'Hemant'), isNull);
    expect(validateOrderCustomer(kind: CustomerOrderKind.retail, customerName: 'Hemant', customerAccountId: 'id-1'), isNotNull);
  });

  test('old orders stay unassigned and new account links survive updates', () {
    final old = CustomerOrderDraft.fromJson({'id': 'old', 'orderNumber': 'A1', 'customerName': 'Hemant'});
    expect(old.customerType, 'legacy');
    expect(old.customerAccountId, isEmpty);
    final linked = old.copyWith(customerType: 'regular', customerAccountId: 'user-1');
    final restored = CustomerOrderDraft.fromJson(linked.copyWith(customerNotes: 'updated').toJson());
    expect(restored.customerType, 'regular');
    expect(restored.customerAccountId, 'user-1');
    expect(restored.customerNotes, 'updated');
  });
}
