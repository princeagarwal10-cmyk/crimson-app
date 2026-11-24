import 'dart:convert';
import 'dart:io';
import 'cloud_auth_repository.dart';
import 'cloud_catalogue_repository.dart';

class ManagedCustomer {
  const ManagedCustomer({required this.userId, required this.loginId, required this.name, required this.role, required this.status, this.phone = '', this.address = '', this.city = ''});
  final String userId, loginId, name, role, status, phone, address, city;
  factory ManagedCustomer.fromJson(Map<String, dynamic> row) => ManagedCustomer(
    userId: (row['user_id'] ?? '').toString(), loginId: (row['login_id'] ?? '').toString(), name: (row['display_name'] ?? '').toString(), role: (row['role'] ?? '').toString(), status: (row['status'] ?? '').toString(), phone: (row['phone'] ?? '').toString(), address: (row['address'] ?? '').toString(), city: (row['city'] ?? '').toString());
}

class CustomerManagementRepository {
  const CustomerManagementRepository({required this.settings, required this.session});
  final CloudCatalogueSettings settings;
  final CloudAuthSession session;

  Future<Map<String, dynamic>> _request(Map<String, dynamic> payload) async {
    final base = settings.supabaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('$base/functions/v1/crimson-admin-customers')).timeout(const Duration(seconds: 12));
      request.headers.set('apikey', settings.anonKey);
      request.headers.set('Authorization', 'Bearer ${session.accessToken}');
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await response.transform(utf8.decoder).join();
      dynamic decoded;
      try { decoded = jsonDecode(body); } on FormatException { decoded = {}; }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(decoded is Map && decoded['error'] != null ? decoded['error'].toString() : 'Customer service is unavailable.');
      }
      if (decoded is! Map) throw StateError('Invalid response from customer service.');
      return Map<String, dynamic>.from(decoded);
    } finally { client.close(); }
  }

  Future<List<ManagedCustomer>> list() async {
    final result = await _request({'action': 'list'});
    return (result['customers'] as List? ?? const []).whereType<Map>().map((row) => ManagedCustomer.fromJson(Map<String, dynamic>.from(row))).toList();
  }

  Future<void> create({required String name, required String userId, required String password, required String role, required String phone, required String address, required String city}) async {
    await _request({'action': 'create', 'name': name, 'userId': userId, 'password': password, 'role': role, 'phone': phone, 'address': address, 'city': city});
  }
}
