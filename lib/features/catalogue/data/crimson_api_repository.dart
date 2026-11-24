import 'dart:convert';
import 'dart:io';

import '../domain/catalogue_models.dart';
import 'cloud_auth_repository.dart';

class CrimsonApiSettings {
  const CrimsonApiSettings({
    required this.apiUrl,
  });

  final String apiUrl;

  bool get isConfigured => apiUrl.trim().isNotEmpty;

  static CrimsonApiSettings? loadFromEnvironment() {
    const apiUrl = String.fromEnvironment('CRIMSON_API_URL');
    if (apiUrl.trim().isEmpty) return null;
    return CrimsonApiSettings(apiUrl: apiUrl.trim());
  }
}

class CrimsonApiSession {
  const CrimsonApiSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.profile,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final CrimsonProfile profile;

  bool get expiresSoon => DateTime.now()
      .toUtc()
      .isAfter(expiresAt.subtract(const Duration(minutes: 2)));
}

class CrimsonApiException implements Exception {
  const CrimsonApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CrimsonApiRepository {
  CrimsonApiRepository(this.settings);

  final CrimsonApiSettings settings;

  Future<CrimsonApiSession> login({
    required String email,
    required String password,
    String deviceName = '',
  }) async {
    final decoded = await _post(
      '/auth/login',
      {
        'email': email,
        'password': password,
        'device_name': deviceName,
      },
    );
    return _sessionFromJson(decoded);
  }

  Future<CrimsonApiSession> refresh(String refreshToken) async {
    final decoded = await _post(
      '/auth/refresh',
      {'refresh_token': refreshToken},
    );
    return _sessionFromJson(decoded);
  }

  Future<void> logout(String accessToken) async {
    await _post('/auth/logout', const {}, accessToken: accessToken);
  }

  Future<CatalogueState?> pullCatalogue(String accessToken) async {
    final decoded = await _get('/catalogue/home', accessToken: accessToken);
    final payload = decoded['payload'];
    if (payload is! Map) return null;
    return CatalogueState.fromJson(Map<String, Object?>.from(payload));
  }

  Future<List<Map<String, Object?>>> sessions(String accessToken) async {
    final decoded = await _get('/me/sessions', accessToken: accessToken);
    if (decoded['items'] is List) {
      return (decoded['items'] as List)
          .whereType<Map>()
          .map((item) => Map<String, Object?>.from(item))
          .toList();
    }
    return const [];
  }

  Future<Map<String, Object?>> _get(
    String path, {
    required String accessToken,
  }) async {
    final request = await HttpClient()
        .getUrl(_uri(path))
        .timeout(const Duration(seconds: 15));
    request.headers.set('Authorization', 'Bearer $accessToken');
    final response = await request.close().timeout(const Duration(seconds: 15));
    return _decodeResponse(response);
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> payload, {
    String accessToken = '',
  }) async {
    final request = await HttpClient()
        .postUrl(_uri(path))
        .timeout(const Duration(seconds: 15));
    request.headers.set('Content-Type', 'application/json');
    if (accessToken.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $accessToken');
    }
    request.add(utf8.encode(jsonEncode(payload)));
    final response = await request.close().timeout(const Duration(seconds: 15));
    return _decodeResponse(response);
  }

  Future<Map<String, Object?>> _decodeResponse(HttpClientResponse response) async {
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CrimsonApiException(_friendlyMessage(body));
    }
    if (body.trim().isEmpty) return const {};
    final decoded = jsonDecode(body);
    if (decoded is Map) return Map<String, Object?>.from(decoded);
    if (decoded is List) return {'items': decoded};
    return const {};
  }

  CrimsonApiSession _sessionFromJson(Map<String, Object?> decoded) {
    final profileJson = decoded['profile'];
    final profile = profileJson is Map
        ? CrimsonProfile.fromJson(Map<String, Object?>.from(profileJson))
        : const CrimsonProfile.localAdmin();
    final expiresIn =
        int.tryParse((decoded['expires_in'] ?? '3600').toString()) ?? 3600;
    return CrimsonApiSession(
      accessToken: (decoded['access_token'] ?? '').toString(),
      refreshToken: (decoded['refresh_token'] ?? '').toString(),
      expiresAt: DateTime.now().toUtc().add(Duration(seconds: expiresIn)),
      profile: profile,
    );
  }

  Uri _uri(String path) {
    final base = settings.apiUrl.endsWith('/')
        ? settings.apiUrl.substring(0, settings.apiUrl.length - 1)
        : settings.apiUrl;
    return Uri.parse('$base$path');
  }

  String _friendlyMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['detail'] != null) {
        return decoded['detail'].toString();
      }
    } on Object {
      // Use the raw text below.
    }
    return body.trim().isEmpty ? 'Crimson API request failed.' : body;
  }
}
