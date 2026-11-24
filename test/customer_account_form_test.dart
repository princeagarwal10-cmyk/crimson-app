import 'package:crimson_catalogue_studio/features/catalogue/presentation/customer_account_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('duplicate names are rejected before creating an account', (tester) async {
    var created = false;
    await tester.pumpWidget(MaterialApp(home: CustomerAccountForm(
      existingNames: const ['Hemant Kumar'],
      onCreate: ({required name, required userId, required password, required role, required phone, required address, required city}) async { created = true; },
    )));
    await tester.enterText(find.widgetWithText(TextFormField, 'Customer name'), ' HEMANT  KUMAR ');
    await tester.enterText(find.widgetWithText(TextFormField, 'User ID'), 'hemant01');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'password123');
    await tester.ensureVisible(find.text('Create customer'));
    await tester.tap(find.text('Create customer'));
    await tester.pumpAndSettle();
    expect(find.text('A customer with this name already exists.'), findsOneWidget);
    expect(created, isFalse);
  });
}
