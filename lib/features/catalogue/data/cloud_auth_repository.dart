import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'cloud_catalogue_repository.dart';

class CloudAuthException implements Exception {
  const CloudAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum CrimsonUserRole {
  customer,
  owner,
  admin;

  static CrimsonUserRole fromText(String value) {
    final clean = value.trim().toLowerCase();
    return CrimsonUserRole.values.firstWhere(
      (role) => role.name == clean,
      orElse: () => CrimsonUserRole.customer,
    );
  }

  String get label => switch (this) {
        CrimsonUserRole.customer => 'Customer',
        CrimsonUserRole.owner => 'Owner',
        CrimsonUserRole.admin => 'Admin',
      };
}

class CrimsonProfile {
  const CrimsonProfile({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.isActive,
  });

  const CrimsonProfile.localAdmin()
      : userId = 'local-admin',
        displayName = 'Local Admin',
        role = CrimsonUserRole.admin,
        isActive = true;

  final String userId;
  final String displayName;
  final CrimsonUserRole role;
  final bool isActive;

  bool get canViewProducts => isActive;
  bool get canShare =>
      isActive &&
      (role == CrimsonUserRole.owner || role == CrimsonUserRole.admin);
  bool get canExportPdf => canShare;
  bool get canEditProducts => isActive && role == CrimsonUserRole.admin;
  bool get canManageCatalogue => canEditProducts;

  String get roleLabel => role.label;

  factory CrimsonProfile.fromJson(Map<String, Object?> json) {
    return CrimsonProfile(
      userId: (json['user_id'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      role: CrimsonUserRole.fromText((json['role'] ?? '').toString()),
      isActive: json['is_active'] != false,
    );
  }
}

class CloudAuthSession {
  const CloudAuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
    required this.email,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String userId;
  final String email;

  bool get isValid =>
      accessToken.isNotEmpty && refreshToken.isNotEmpty && userId.isNotEmpty;

  bool get expiresSoon => DateTime.now()
      .toUtc()
      .isAfter(expiresAt.subtract(const Duration(minutes: 2)));

  Map<String, Object?> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toUtc().toIso8601String(),
        'user_id': userId,
        'email': email,
      };

  factory CloudAuthSession.fromJson(Map<String, Object?> json) {
    return CloudAuthSession(
      accessToken: (json['access_token'] ?? '').toString(),
      refreshToken: (json['refresh_token'] ?? '').toString(),
      expiresAt:
          DateTime.tryParse((json['expires_at'] ?? '').toString())?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      userId: (json['user_id'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
    );
  }
}

class CloudAuthRepository {
  const CloudAuthRepository(this.settings);

  final CloudCatalogueSettings settings;

  Future<CloudAuthSession> signIn({
    required String email,
    required String password,
  }) async {
    final decoded = await _postAuth(
      '/auth/v1/token?grant_type=password',
      {
        'email': email.trim(),
        'password': password,
      },
    );
    return _sessionFromAuthResponse(decoded, fallbackEmail: email.trim());
  }

  Future<CloudAuthSession> refresh(CloudAuthSession session) async {
    final decoded = await _postAuth(
      '/auth/v1/token?grant_type=refresh_token',
      {'refresh_token': session.refreshToken},
    );
    return _sessionFromAuthResponse(decoded, fallbackEmail: session.email);
  }

  Future<void> signOut(CloudAuthSession session) async {
    try {
      final request = await HttpClient()
          .postUrl(_uri('/auth/v1/logout'))
          .timeout(const Duration(seconds: 10));
      request.headers.set('apikey', settings.anonKey);
      request.headers.set('Authorization', 'Bearer ${session.accessToken}');
      await request.close().timeout(const Duration(seconds: 10));
    } on Object {
      // Local logout should still work if the network is unavailable.
    }
  }

  Future<CrimsonProfile> fetchProfile(CloudAuthSession session) async {
    final request = await HttpClient()
        .getUrl(_uri(
          '/rest/v1/crimson_profiles?user_id=eq.${Uri.encodeComponent(session.userId)}'
          '&select=user_id,display_name,role,is_active&limit=1',
        ))
        .timeout(const Duration(seconds: 12));
    request.headers.set('apikey', settings.anonKey);
    request.headers.set('Authorization', 'Bearer ${session.accessToken}');
    request.headers.set('Content-Type', 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 12));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudAuthException(_friendlyAuthError(body));
    }
    final decoded = jsonDecode(body);
    if (decoded is! List || decoded.isEmpty || decoded.first is! Map) {
      throw const CloudAuthException(
        'Access not assigned. Ask admin to add this user role.',
      );
    }
    final profile = CrimsonProfile.fromJson(
      Map<String, Object?>.from(decoded.first as Map),
    );
    if (!profile.isActive) {
      throw const CloudAuthException('Access disabled. Please contact admin.');
    }
    return profile;
  }

  Future<Map<String, Object?>> _postAuth(
    String path,
    Map<String, Object?> payload,
  ) async {
    final request = await HttpClient()
        .postUrl(_uri(path))
        .timeout(const Duration(seconds: 12));
    request.headers.set('apikey', settings.anonKey);
    request.headers.set('Content-Type', 'application/json');
    request.add(utf8.encode(jsonEncode(payload)));
    final response = await request.close().timeout(const Duration(seconds: 12));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudAuthException(_friendlyAuthError(body));
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const CloudAuthException('Login response was not valid.');
    }
    return Map<String, Object?>.from(decoded);
  }

  CloudAuthSession _sessionFromAuthResponse(
    Map<String, Object?> decoded, {
    required String fallbackEmail,
  }) {
    final user = decoded['user'];
    final userMap =
        user is Map ? Map<String, Object?>.from(user) : <String, Object?>{};
    final accessToken = (decoded['access_token'] ?? '').toString();
    final refreshToken = (decoded['refresh_token'] ?? '').toString();
    final expiresIn =
        int.tryParse((decoded['expires_in'] ?? '').toString()) ?? 3600;
    final userId = (userMap['id'] ?? '').toString();
    final email = (userMap['email'] ?? fallbackEmail).toString();
    if (accessToken.isEmpty || refreshToken.isEmpty || userId.isEmpty) {
      throw const CloudAuthException('Login token missing. Please try again.');
    }
    return CloudAuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().toUtc().add(Duration(seconds: expiresIn)),
      userId: userId,
      email: email,
    );
  }

  Uri _uri(String path) {
    final base = settings.supabaseUrl.endsWith('/')
        ? settings.supabaseUrl.substring(0, settings.supabaseUrl.length - 1)
        : settings.supabaseUrl;
    return Uri.parse('$base$path');
  }

  String _friendlyAuthError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final message = (decoded['msg'] ??
                decoded['message'] ??
                decoded['error_description'] ??
                decoded['error'] ??
                '')
            .toString();
        if (message.trim().isNotEmpty) return message;
      }
    } on Object {
      // Use raw body below.
    }
    return body.trim().isEmpty ? 'Login failed. Please try again.' : body;
  }
}

class CloudAuthSessionStore {
  const CloudAuthSessionStore({this.file});

  final File? file;

  Future<CloudAuthSession?> load() async {
    final target = file ?? await defaultFile();
    if (!await target.exists()) return null;
    try {
      final decoded = jsonDecode(await target.readAsString());
      if (decoded is! Map) return null;
      final session =
          CloudAuthSession.fromJson(Map<String, Object?>.from(decoded));
      return session.isValid ? session : null;
    } on Object {
      return null;
    }
  }

  Future<void> save(CloudAuthSession session) async {
    final target = file ?? await defaultFile();
    await target.parent.create(recursive: true);
    await target.writeAsString(jsonEncode(session.toJson()));
  }

  Future<void> clear() async {
    final target = file ?? await defaultFile();
    if (await target.exists()) await target.delete();
  }

  static Future<File> defaultFile() async {
    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('com.mycrimson.cataloguestudio/storage');
        final filesDir =
            (await channel.invokeMethod<String>('filesDir'))?.trim();
        if (filesDir != null && filesDir.isNotEmpty) {
          return File(
            '$filesDir${Platform.pathSeparator}crimson_auth_session.json',
          );
        }
      } on Object {
        // Fall through to temp fallback for tests.
      }
    }
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.trim().isNotEmpty) {
      return File(
        '$appData${Platform.pathSeparator}Crimson Catalogue Studio'
        '${Platform.pathSeparator}crimson_auth_session.json',
      );
    }
    return File('data/crimson_auth_session.json');
  }
}
