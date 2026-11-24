/// Rules for customer account creation and order ownership.
/// Existing catalogue data is not modified by these functions.
enum CustomerOrderKind { regular, retail }

String normalizeCustomerName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

String normalizeCustomerUserId(String value) => value.trim().toLowerCase();

String? validateRegularCustomerName(String name, Iterable<String> existingNames) {
  final normalized = normalizeCustomerName(name);
  if (normalized.isEmpty) return 'Enter the customer name.';
  if (existingNames.any((existing) => normalizeCustomerName(existing) == normalized)) {
    return 'A customer with this name already exists.';
  }
  return null;
}

String? validateCustomerUserId(String value) {
  final normalized = normalizeCustomerUserId(value);
  if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,31}$').hasMatch(normalized)) {
    return 'Use 3–32 letters, numbers, dots, underscores or hyphens.';
  }
  return null;
}

String? validateOrderCustomer({
  required CustomerOrderKind kind,
  required String customerName,
  String? customerAccountId,
}) {
  if (normalizeCustomerName(customerName).isEmpty) return 'Enter the customer name.';
  if (kind == CustomerOrderKind.regular && (customerAccountId?.trim().isEmpty ?? true)) {
    return 'Select a registered customer.';
  }
  if (kind == CustomerOrderKind.retail && (customerAccountId?.trim().isNotEmpty ?? false)) {
    return 'Retail orders cannot be linked to a customer account.';
  }
  return null;
}
