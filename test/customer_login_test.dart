import 'package:crimson_catalogue_studio/features/catalogue/domain/customer_login.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('user ID resolves consistently without using the customer email', () {
    expect(customerLoginEmail(' HEMANT01 '), customerLoginEmail('hemant01'));
    expect(customerLoginEmail('hemant01'), 'unbsw2ylooqydc@users.mycrimson.in');
    expect(customerLoginEmail('admin@example.com'), 'admin@example.com');
    expect(() => customerLoginEmail('x'), throwsFormatException);
  });
}
