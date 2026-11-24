import 'catalogue_models.dart';

/// Defense in depth for a customer session. Server row-level access is the
/// authority; records with missing ownership or retail status stay private.
List<CustomerOrderDraft> visibleOrdersForCustomer(
    Iterable<CustomerOrderDraft> orders, String userId) {
  final id = userId.trim();
  if (id.isEmpty) return const [];
  return orders.where((order) =>
      order.customerType == 'regular' && order.customerAccountId == id).toList(growable: false);
}
