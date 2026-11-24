import 'package:crimson_catalogue_studio/features/catalogue/domain/stock_availability.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/catalogue_models.dart';
import 'package:crimson_catalogue_studio/main.dart' show LiveStockSnapshot;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stock boundaries and unrecorded stock remain distinct', () {
    expect(stockAvailabilityFor(null), StockAvailability.notRecorded);
    expect(stockAvailabilityFor(0), StockAvailability.outOfStock);
    expect(stockAvailabilityFor(-3), StockAvailability.outOfStock);
    expect(stockAvailabilityFor(1), StockAvailability.lowStock);
    expect(stockAvailabilityFor(49), StockAvailability.lowStock);
    expect(stockAvailabilityFor(50), StockAvailability.inStock);
    expect(stockAvailabilityFor(120), StockAvailability.inStock);
  });

  test('approved orders do not reduce recorded stock before billing', () {
    const gold96 = VariationDraft(size: '96MM', finish: 'Gold', price: '100');
    const gold160 = VariationDraft(size: '160MM', finish: 'Gold', price: '120');
    const black96 = VariationDraft(size: '96MM', finish: 'Black', price: '100');
    const black160 = VariationDraft(size: '160MM', finish: 'Black', price: '120');
    final product = ProductDraft(
      id: 'handle-1',
      name: 'Handle',
      category: 'Cabinet Handles',
      subcategory: 'Welset',
      variations: [gold96, gold160, black96, black160],
    );
    StockVoucherItemDraft line(String size, String finish, double quantity) =>
        StockVoucherItemDraft(
          productId: product.id,
          productName: product.name,
          size: size,
          finish: finish,
          quantity: quantity,
        );
    final state = CatalogueState(
      products: [product],
      stockVouchers: [
        StockVoucherDraft(
          type: StockVoucherType.inward,
          voucherNumber: 'STK-1',
          date: '2026-11-15',
          items: [
            line('96MM', 'Gold', 51),
            line('160MM', 'Gold', 49),
            line('96MM', 'Black', 5),
          ],
        ),
        StockVoucherDraft(
          type: StockVoucherType.outward,
          voucherNumber: 'STK-2',
          date: '2026-11-15',
          items: [line('96MM', 'Black', 5)],
        ),
      ],
      customerOrders: [
        CustomerOrderDraft(
          orderNumber: 'ORD-1',
          status: CustomerOrderStatus.confirmed,
          items: [
            CustomerOrderItemDraft(
              productId: product.id,
              productName: product.name,
              size: '96MM',
              finish: 'Gold',
              quantity: 2,
              unitPrice: 100,
              approvedQuantity: 2,
            ),
          ],
        ),
      ],
    );
    final snapshot = LiveStockSnapshot.fromState(state);
    expect(snapshot.statusFor(product, gold96), StockAvailability.inStock);
    expect(snapshot.statusFor(product, gold160), StockAvailability.lowStock);
    expect(snapshot.statusFor(product, black96), StockAvailability.outOfStock);
    expect(snapshot.statusFor(product, black160), StockAvailability.notRecorded);
  });

  test('status-only catalogue keeps statuses without inventory quantities', () {
    const gold96 = VariationDraft(size: '96MM', finish: 'Gold', price: '100');
    const gold160 = VariationDraft(size: '160MM', finish: 'Gold', price: '120');
    const black96 = VariationDraft(size: '96MM', finish: 'Black', price: '100');
    final product = ProductDraft(id: 'p1', name: 'Handle', category: 'Cabinet Handles', subcategory: 'Welset', variations: [gold96, gold160, black96]);
    final original = CatalogueState(products: [product], customerStockStatuses: const {'p1|96mm|gold': 'inStock', 'p1|160mm|gold': 'lowStock', 'p1|96mm|black': 'outOfStock'});
    final restored = CatalogueState.fromJson(original.copyWith().toJson());
    final snapshot = LiveStockSnapshot.fromState(restored);
    expect(restored.stockVouchers, isEmpty);
    expect(snapshot.statusFor(product, gold96), StockAvailability.inStock);
    expect(snapshot.statusFor(product, gold160), StockAvailability.lowStock);
    expect(snapshot.statusFor(product, black96), StockAvailability.outOfStock);
  });
}
