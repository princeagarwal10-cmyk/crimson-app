import 'package:flutter_test/flutter_test.dart';

import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';

void main() {
  test('category discount survives catalogue serialization', () {
    const state = CatalogueState(categories: [
      CategoryDraft(name: 'Cabinet Handles', discountPercent: 20),
    ]);

    final restored = CatalogueState.fromJson(state.toJson());
    expect(categoryDiscountFor(restored.categories, 'CABINET HANDLES'), 20);
    expect(categoryDiscountFor(restored.categories, 'Other'), 0);
    expect(
        CategoryDraft.fromJson({'name': 'Older category'}).discountPercent, 0);
  });

  test('line and additional discounts compound without changing base rates',
      () {
    const handle = CustomerOrderItemDraft(
      productId: 'handle',
      productName: 'W CARENS',
      quantity: 2,
      unitPrice: 520,
      defaultDiscount: '20%',
      approvedQuantity: 1,
    );
    const knob = CustomerOrderItemDraft(
      productId: 'knob',
      productName: 'Knob',
      quantity: 1,
      unitPrice: 315,
      approvedQuantity: 0,
    );
    final order = CustomerOrderDraft(
      orderNumber: 'TEST-1',
      items: const [handle, knob],
      additionalDiscountPercent: 10,
    );

    expect(handle.unitPrice, 520);
    expect(handle.discountedUnitPrice, 416);
    expect(order.baseSubtotal, 1355);
    expect(order.lineDiscountTotal, 208);
    expect(order.discountedSubtotal, 1147);
    expect(order.additionalDiscountAmount, closeTo(114.7, 0.0001));
    expect(order.total, closeTo(1032.3, 0.0001));
    expect(order.approvedTotal, closeTo(374.4, 0.0001));

    final restored = CustomerOrderDraft.fromJson(order.toJson());
    expect(restored.additionalDiscountPercent, 10);
    expect(restored.total, closeTo(order.total, 0.0001));
  });

  test('admin can explicitly replace a category discount with zero', () {
    const item = CustomerOrderItemDraft(
      productId: 'handle',
      productName: 'W CARENS',
      quantity: 1,
      unitPrice: 520,
      defaultDiscount: '20%',
      finalDiscount: '0%',
    );
    expect(item.lineTotal, 520);
    expect(CustomerOrderItemDraft.fromJson(item.toJson()).lineTotal, 520);
  });
}
