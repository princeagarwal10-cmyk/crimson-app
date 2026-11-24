import 'catalogue_models.dart';

/// A bill preview only. Creating a durable bill and deducting stock must be
/// performed atomically by the backend, never by this calculation.
class SimpleBillPreview {
  const SimpleBillPreview(
      {required this.orderId,
      required this.orderNumber,
      required this.customerAccountId,
      required this.customerType,
      required this.customerName,
      required this.lines,
      required this.additionalDiscountPercent});

  final String orderId,
      orderNumber,
      customerAccountId,
      customerType,
      customerName;
  final List<SimpleBillLine> lines;
  final double additionalDiscountPercent;

  double get subtotal => lines.fold(0, (sum, line) => sum + line.total);
  double get total =>
      (subtotal * (1 - additionalDiscountPercent / 100) * 100).round() / 100;
}

class SimpleBillLine {
  const SimpleBillLine(
      {required this.productId,
      required this.productName,
      required this.size,
      required this.finish,
      required this.brand,
      required this.quantity,
      required this.unitPrice,
      required this.discountText,
      required this.discountedUnitPrice});
  final String productId, productName, size, finish, brand, discountText;
  final double quantity, unitPrice, discountedUnitPrice;
  double get total => (quantity * discountedUnitPrice * 100).round() / 100;
}

SimpleBillPreview previewSimpleBill(CustomerOrderDraft order) {
  if (order.status != CustomerOrderStatus.dispatched &&
      order.status != CustomerOrderStatus.delivered) {
    throw StateError('A bill can only be generated after dispatch.');
  }
  if (order.customerType == 'regular' &&
      order.customerAccountId.trim().isEmpty) {
    throw StateError('The regular customer must have an account.');
  }
  if (!order.additionalDiscountPercent.isFinite ||
      order.additionalDiscountPercent < 0 ||
      order.additionalDiscountPercent > 100) {
    throw StateError('Invalid additional discount.');
  }
  final lines = <SimpleBillLine>[];
  for (final item in order.items) {
    final qty = item.dispatchedQuantity;
    if (!qty.isFinite ||
        qty < 0 ||
        qty > item.effectiveApprovedQuantity ||
        !item.unitPrice.isFinite ||
        item.unitPrice < 0) {
      throw StateError('Invalid dispatched quantity or rate.');
    }
    if (qty == 0) continue;
    lines.add(SimpleBillLine(
        productId: item.productId,
        productName: item.productName,
        size: item.size,
        finish: item.finish,
        brand: item.brand,
        quantity: qty,
        unitPrice: item.unitPrice,
        discountText: item.effectiveDiscountText,
        discountedUnitPrice: item.discountedUnitPrice));
  }
  if (lines.isEmpty) throw StateError('No dispatched items to bill.');
  return SimpleBillPreview(
      orderId: order.id,
      orderNumber: order.orderNumber,
      customerAccountId: order.customerAccountId,
      customerType: order.customerType,
      customerName: order.customerName,
      lines: List.unmodifiable(lines),
      additionalDiscountPercent: order.additionalDiscountPercent);
}
