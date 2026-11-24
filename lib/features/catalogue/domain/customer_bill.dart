class CustomerBill {
  const CustomerBill(
      {required this.id,
      required this.billNumber,
      required this.orderId,
      required this.createdAt,
      required this.payload});
  final String id, billNumber, orderId, createdAt;
  final Map<String, Object?> payload;

  factory CustomerBill.fromRow(Map<String, dynamic> row) {
    final raw = row['payload'];
    return CustomerBill(
        id: (row['id'] ?? '').toString(),
        billNumber: (row['bill_number'] ?? '').toString(),
        orderId: (row['order_id'] ?? '').toString(),
        createdAt: (row['created_at'] ?? '').toString(),
        payload: raw is Map ? Map<String, Object?>.from(raw) : {});
  }

  String get orderNumber => (payload['orderNumber'] ?? '').toString();
  String get customerName => (payload['customerName'] ?? '').toString();
  String get total => (payload['total'] ?? '0').toString();
  List<Map<String, Object?>> get items =>
      (payload['items'] is List ? payload['items'] as List : const [])
          .whereType<Map>()
          .map((value) => Map<String, Object?>.from(value))
          .toList();
}
