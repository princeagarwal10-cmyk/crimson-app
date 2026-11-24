/// Customer-facing bills are scoped to a regular customer's account ID.
/// A matching name is never sufficient to grant access.
bool customerCanViewBill({
  required String signedInUserId,
  required String customerAccountId,
  required String customerType,
  required bool isFinalized,
}) {
  final userId = signedInUserId.trim();
  return isFinalized &&
      customerType == 'regular' &&
      userId.isNotEmpty &&
      customerAccountId.trim().isNotEmpty &&
      customerAccountId.trim() == userId;
}
