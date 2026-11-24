import 'package:crimson_catalogue_studio/features/catalogue/domain/customer_bill_privacy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only the matching regular customer sees a finalized bill', () {
    bool canView(String viewer, String owner, String type, bool finalized) =>
        customerCanViewBill(
            signedInUserId: viewer,
            customerAccountId: owner,
            customerType: type,
            isFinalized: finalized);
    expect(canView('hemant-id', 'hemant-id', 'regular', true), isTrue);
    expect(canView('rahul-id', 'hemant-id', 'regular', true), isFalse);
    expect(canView('hemant-id', 'hemant-id', 'regular', false), isFalse);
    expect(canView('hemant-id', 'hemant-id', 'retail', true), isFalse);
    expect(canView('', '', 'regular', true), isFalse);
  });
}
