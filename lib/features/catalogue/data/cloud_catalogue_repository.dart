import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/catalogue_models.dart';
import '../domain/tally_stock_import.dart';
import '../domain/customer_bill.dart';

class CloudCatalogueSettings {
  const CloudCatalogueSettings({
    required this.supabaseUrl,
    required this.anonKey,
    this.email = '',
    this.password = '',
    this.workspaceId = 'default',
  });

  final String supabaseUrl;
  final String anonKey;
  final String email;
  final String password;
  final String workspaceId;

  bool get isConfigured => supabaseUrl.isNotEmpty && anonKey.isNotEmpty;

  static Future<CloudCatalogueSettings?> load() async {
    const envUrl = String.fromEnvironment('CRIMSON_SUPABASE_URL');
    const envKey = String.fromEnvironment('CRIMSON_SUPABASE_ANON_KEY');
    const envEmail = String.fromEnvironment('CRIMSON_SUPABASE_EMAIL');
    const envPassword = String.fromEnvironment('CRIMSON_SUPABASE_PASSWORD');
    const envWorkspace = String.fromEnvironment('CRIMSON_WORKSPACE_ID');
    if (envUrl.trim().isNotEmpty && envKey.trim().isNotEmpty) {
      return CloudCatalogueSettings(
        supabaseUrl: envUrl.trim(),
        anonKey: envKey.trim(),
        email: envEmail.trim(),
        password: envPassword.trim(),
        workspaceId: envWorkspace.trim().isEmpty ? 'default' : envWorkspace,
      );
    }

    for (final file in await _candidateConfigFiles()) {
      if (!await file.exists()) continue;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) continue;
      final settings = _fromDecodedConfig(decoded);
      if (settings != null) return settings;
    }

    return _loadBundledConfig();
  }

  static Future<CloudCatalogueSettings?> _loadBundledConfig() async {
    try {
      final raw = await rootBundle
          .loadString('assets/config/crimson_cloud_config.json');
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return _fromDecodedConfig(decoded);
    } on Object {
      return null;
    }
  }

  static CloudCatalogueSettings? _fromDecodedConfig(
    Map<dynamic, dynamic> decoded,
  ) {
    final url = (decoded['supabaseUrl'] ?? decoded['supabase_url'] ?? '')
        .toString()
        .trim();
    final key =
        (decoded['anonKey'] ?? decoded['anon_key'] ?? '').toString().trim();
    if (url.isEmpty || key.isEmpty) return null;
    final workspace = (decoded['workspaceId'] ?? decoded['workspace_id'] ?? '')
        .toString()
        .trim();
    return CloudCatalogueSettings(
      supabaseUrl: url,
      anonKey: key,
      email: (decoded['email'] ?? '').toString().trim(),
      password: (decoded['password'] ?? '').toString(),
      workspaceId: workspace.isEmpty ? 'default' : workspace,
    );
  }

  static Future<List<File>> _candidateConfigFiles() async {
    final files = <File>[];
    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('com.mycrimson.cataloguestudio/storage');
        final filesDir =
            (await channel.invokeMethod<String>('filesDir'))?.trim();
        if (filesDir != null && filesDir.isNotEmpty) {
          files.add(File(
              '$filesDir${Platform.pathSeparator}crimson_cloud_config.json'));
          files.add(File(
              '$filesDir${Platform.pathSeparator}data${Platform.pathSeparator}crimson_cloud_config.json'));
        }
      } on Object {
        // Desktop and tests do not provide the Android storage channel.
      }
    }

    files.add(File('data/crimson_cloud_config.json'));
    final executableDir = File(Platform.resolvedExecutable).parent;
    files.add(File(
        '${executableDir.path}${Platform.pathSeparator}data${Platform.pathSeparator}crimson_cloud_config.json'));
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.trim().isNotEmpty) {
      files.add(File(
          '$appData${Platform.pathSeparator}Crimson Catalogue Studio${Platform.pathSeparator}crimson_cloud_config.json'));
    }
    return files;
  }
}

class VersionedCataloguePayload {
  const VersionedCataloguePayload(
      {required this.payload, required this.revision});
  final Map<String, Object?> payload;
  final String revision;
}

class CloudCatalogueRepository {
  CloudCatalogueRepository(this.settings,
      {String accessToken = '', this.customerSafe = false})
      : _accessToken = accessToken;

  final CloudCatalogueSettings settings;
  final bool customerSafe;
  String _accessToken;
  bool lastPullHadDuplicateProductIds = false;

  Future<List<CustomerBill>> pullBills() async {
    final bills = <CustomerBill>[];
    const pageSize = 1000;
    for (var offset = 0;; offset += pageSize) {
      final uri = _tableUri('crimson_customer_bills',
          'workspace_id=eq.${Uri.encodeQueryComponent(settings.workspaceId)}&state=eq.finalized&select=id,bill_number,order_id,payload,created_at&order=created_at.desc,id.desc&limit=$pageSize&offset=$offset');
      final request =
          await HttpClient().getUrl(uri).timeout(const Duration(seconds: 12));
      (await _headers()).forEach(request.headers.set);
      final response =
          await request.close().timeout(const Duration(seconds: 12));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CloudCatalogueException(body);
      }
      final decoded = jsonDecode(body);
      if (decoded is! List) {
        throw const CloudCatalogueException('Invalid bill response.');
      }
      bills.addAll(decoded
          .whereType<Map>()
          .map((row) => CustomerBill.fromRow(Map<String, dynamic>.from(row))));
      if (decoded.length < pageSize) break;
    }
    return bills;
  }

  Future<void> generateSimpleBill(String orderId) async {
    if (customerSafe || orderId.trim().isEmpty) {
      throw StateError('Admin access and an order are required.');
    }
    final request = await HttpClient()
        .postUrl(
            Uri.parse('$_baseUrl/rest/v1/rpc/crimson_generate_simple_bill'))
        .timeout(const Duration(seconds: 12));
    (await _headers()).forEach(request.headers.set);
    request.add(utf8.encode(jsonEncode({'p_order_id': orderId})));
    final response = await request.close().timeout(const Duration(seconds: 12));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudCatalogueException(body);
    }
  }

  Future<Map<String, TallyStockLink>> pullTallyLinks() async {
    if (customerSafe) throw StateError('Admin access required.');
    final result = <String, TallyStockLink>{};
    const pageSize = 1000;
    for (var offset = 0;; offset += pageSize) {
      final uri = _tableUri('crimson_tally_stock_links',
          'workspace_id=eq.${Uri.encodeQueryComponent(settings.workspaceId)}&select=source_key,target_identity,unit,multiplier,conversion_confirmed&order=source_key&limit=$pageSize&offset=$offset');
      final request =
          await HttpClient().getUrl(uri).timeout(const Duration(seconds: 12));
      (await _headers()).forEach(request.headers.set);
      final response =
          await request.close().timeout(const Duration(seconds: 12));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CloudCatalogueException(body);
      }
      final rows = jsonDecode(body);
      if (rows is! List) {
        throw const CloudCatalogueException('Invalid mapping response.');
      }
      for (final row in rows.whereType<Map>()) {
        final key = (row['source_key'] ?? '').toString();
        final target = (row['target_identity'] ?? '').toString();
        final unit = (row['unit'] ?? '').toString();
        final multiplier =
            double.tryParse((row['multiplier'] ?? '').toString());
        if (key.isNotEmpty &&
            target.isNotEmpty &&
            unit.isNotEmpty &&
            multiplier != null) {
          result[key] = TallyStockLink(
              sourceKey: key,
              targetKey: target,
              unit: unit,
              multiplier: multiplier,
              conversionConfirmed: row['conversion_confirmed'] == true);
        }
      }
      if (rows.length < pageSize) break;
    }
    return result;
  }

  Future<void> saveTallyLink(TallyStockRow row, TallyStockLink link) async {
    if (customerSafe) throw StateError('Admin access required.');
    if (row.sourceKey != link.sourceKey ||
        link.targetKey.trim().isEmpty ||
        link.unit.trim().isEmpty ||
        !link.multiplier.isFinite ||
        link.multiplier <= 0) {
      throw StateError('Invalid stock mapping.');
    }
    final uri = _tableUri(
        'crimson_tally_stock_links', 'on_conflict=workspace_id,source_key');
    final request =
        await HttpClient().postUrl(uri).timeout(const Duration(seconds: 12));
    (await _headers()).forEach(request.headers.set);
    request.headers.set('Prefer', 'resolution=merge-duplicates');
    request.add(utf8.encode(jsonEncode({
      'workspace_id': settings.workspaceId,
      'source_key': row.sourceKey,
      'source_name': row.itemName,
      'target_identity': link.targetKey,
      'unit': link.unit.toUpperCase(),
      'multiplier': link.multiplier,
      'conversion_confirmed': link.conversionConfirmed,
      'updated_at': DateTime.now().toUtc().toIso8601String()
    })));
    final response = await request.close().timeout(const Duration(seconds: 12));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudCatalogueException(body);
    }
  }

  void setAccessToken(String accessToken) => _accessToken = accessToken;

  String get _baseUrl => settings.supabaseUrl.endsWith('/')
      ? settings.supabaseUrl.substring(0, settings.supabaseUrl.length - 1)
      : settings.supabaseUrl;

  Uri _restUri(String query) {
    return Uri.parse('$_baseUrl/rest/v1/crimson_catalogue_live?$query');
  }

  Uri _tableUri(String table, String query) {
    return Uri.parse('$_baseUrl/rest/v1/$table?$query');
  }

  Future<Map<String, String>> _headers() async => {
        'apikey': settings.anonKey,
        'Authorization': 'Bearer ${await _bearerToken()}',
        'Content-Type': 'application/json',
      };

  Future<String> _bearerToken() async {
    if (_accessToken.isNotEmpty) return _accessToken;
    if (settings.email.isEmpty || settings.password.isEmpty) {
      return settings.anonKey;
    }
    final base = settings.supabaseUrl.endsWith('/')
        ? settings.supabaseUrl.substring(0, settings.supabaseUrl.length - 1)
        : settings.supabaseUrl;
    final request = await HttpClient()
        .postUrl(Uri.parse('$base/auth/v1/token?grant_type=password'))
        .timeout(const Duration(seconds: 12));
    request.headers.set('apikey', settings.anonKey);
    request.headers.set('Content-Type', 'application/json');
    request.add(utf8.encode(jsonEncode({
      'email': settings.email,
      'password': settings.password,
    })));
    final response = await request.close().timeout(const Duration(seconds: 12));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudCatalogueException(body);
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['access_token'] == null) {
      throw const CloudCatalogueException('Login token missing.');
    }
    return _accessToken = decoded['access_token'].toString();
  }

  Future<CatalogueState?> pull() async {
    final target = customerSafe
        ? Uri.parse(
            '$_baseUrl/rest/v1/rpc/crimson_customer_catalogue?requested_workspace=${Uri.encodeQueryComponent(settings.workspaceId)}')
        : _restUri(
            'workspace_id=eq.${settings.workspaceId}&select=payload&limit=1');
    final request =
        await HttpClient().getUrl(target).timeout(const Duration(seconds: 12));
    (await _headers()).forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 12));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudCatalogueException(body);
    }
    final decoded = jsonDecode(body);
    if (decoded is! List || decoded.isEmpty) return null;
    final first = decoded.first;
    if (first is! Map) return null;
    final payload = first['payload'];
    if (payload is! Map) return null;
    lastPullHadDuplicateProductIds = _hasDuplicateProductIds(payload);
    final catalogue =
        CatalogueState.fromJson(Map<String, Object?>.from(payload));
    return customerSafe
        ? catalogue
        : catalogue.copyWith(photoInbox: await pullPhotoInbox());
  }

  /// Read the raw admin document and server revision without normalising or
  /// dropping fields that a newer client may have stored.
  Future<VersionedCataloguePayload> pullVersionedForStock() async {
    if (customerSafe) throw StateError('Admin access required.');
    final uri = Uri.parse('$_baseUrl/rest/v1/crimson_catalogue_live').replace(
      queryParameters: {
        'workspace_id': 'eq.${settings.workspaceId}',
        'select': 'payload,updated_at',
        'limit': '1',
      },
    );
    final request =
        await HttpClient().getUrl(uri).timeout(const Duration(seconds: 12));
    (await _headers()).forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 12));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudCatalogueException(body);
    }
    final rows = jsonDecode(body);
    if (rows is! List || rows.length != 1 || rows.first is! Map) {
      throw const CloudCatalogueException('Cloud catalogue is unavailable.');
    }
    final row = rows.first as Map;
    final payload = row['payload'];
    final revision = row['updated_at']?.toString() ?? '';
    if (payload is! Map || revision.isEmpty) {
      throw const CloudCatalogueException('Cloud revision is unavailable.');
    }
    return VersionedCataloguePayload(
        payload: Map<String, Object?>.from(payload), revision: revision);
  }

  /// Server-side atomic compare-and-swap; false means the preview is stale.
  Future<bool> writeStockPayloadIfUnchanged(
      {required String revision, required Map<String, Object?> payload}) async {
    if (customerSafe) throw StateError('Admin access required.');
    if (revision.trim().isEmpty) {
      throw StateError('Cloud revision is required.');
    }
    if (settings.workspaceId != 'default') {
      throw StateError('Unsupported workspace.');
    }
    final uri = Uri.parse('$_baseUrl/rest/v1/rpc/crimson_apply_tally_stock');
    final request =
        await HttpClient().postUrl(uri).timeout(const Duration(seconds: 12));
    (await _headers()).forEach(request.headers.set);
    request.add(utf8.encode(jsonEncode({
      'p_expected': revision,
      'p_payload': payload,
    })));
    final response = await request.close().timeout(const Duration(seconds: 12));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudCatalogueException(body);
    }
    final result = jsonDecode(body);
    if (result is! bool) {
      throw const CloudCatalogueException('Unexpected stock save response.');
    }
    return result;
  }

  Future<List<PhotoInboxDraft>> pullPhotoInbox() async {
    final request = await HttpClient()
        .getUrl(_tableUri('crimson_photo_inbox',
            'workspace_id=eq.${Uri.encodeComponent(settings.workspaceId)}&select=payload'))
        .timeout(const Duration(seconds: 12));
    (await _headers()).forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 12));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Older installations can continue using the catalogue until the
      // additive photo inbox migration is installed.
      if (response.statusCode == 404) return const [];
      throw CloudCatalogueException(body);
    }
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];
    return decoded.whereType<Map>().map((row) {
      final payload = row['payload'];
      return payload is Map
          ? PhotoInboxDraft.fromJson(Map<String, Object?>.from(payload))
          : PhotoInboxDraft();
    }).toList();
  }

  Future<bool> isPhotoInboxReady() async {
    try {
      final request = await HttpClient()
          .getUrl(_tableUri('crimson_photo_inbox', 'select=id&limit=0'))
          .timeout(const Duration(seconds: 10));
      (await _headers()).forEach(request.headers.set);
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 300;
    } on Object {
      return false;
    }
  }

  Future<List<CustomerOrderDraft>> pullCustomerOrders() async {
    final request = await HttpClient()
        .getUrl(_tableUri(
          'crimson_customer_orders',
          'workspace_id=eq.${Uri.encodeComponent(settings.workspaceId)}&select=id,order_number,customer_user_id,status,payload,created_at,updated_at&order=created_at.desc',
        ))
        .timeout(const Duration(seconds: 12));
    (await _headers()).forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 12));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudCatalogueException(body);
    }
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((row) => _orderFromCloudRow(Map<String, Object?>.from(row)))
        .toList();
  }

  Future<CustomerOrderDraft> saveCustomerOrder(
    CustomerOrderDraft order, {
    required String userId,
    required String email,
    bool assignServerNumber = false,
  }) async {
    if (!assignServerNumber) {
      final patched = await _patchCustomerOrder(order);
      if (patched != null) return patched;
    }
    return _insertCustomerOrder(
      assignServerNumber ? order.copyWith(orderNumber: '') : order,
      userId: userId,
      email: email,
      assignServerNumber: assignServerNumber,
    );
  }

  Future<CustomerOrderDraft?> _patchCustomerOrder(
    CustomerOrderDraft order,
  ) async {
    final id = _cleanText(order.id);
    if (id.isEmpty) return null;
    final payload = order.toJson();
    final request = await HttpClient()
        .patchUrl(_tableUri(
          'crimson_customer_orders',
          'id=eq.${Uri.encodeComponent(id)}&select=id,order_number,customer_user_id,status,payload,created_at,updated_at',
        ))
        .timeout(const Duration(seconds: 12));
    (await _headers()).forEach(request.headers.set);
    request.headers.set('Prefer', 'return=representation');
    request.add(utf8.encode(jsonEncode({
      'order_number': _cleanText(order.orderNumber).isEmpty
          ? null
          : _cleanText(order.orderNumber),
      'status': order.status.name,
      'payload': payload,
    })));
    final response = await request.close().timeout(const Duration(seconds: 12));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudCatalogueException(body);
    }
    final decoded = jsonDecode(body);
    if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
      return _orderFromCloudRow(
          Map<String, Object?>.from(decoded.first as Map));
    }
    return null;
  }

  Future<CustomerOrderDraft> _insertCustomerOrder(
    CustomerOrderDraft order, {
    required String userId,
    required String email,
    required bool assignServerNumber,
  }) async {
    final payload = order.toJson();
    final request = await HttpClient()
        .postUrl(_tableUri('crimson_customer_orders',
            'select=id,order_number,customer_user_id,status,payload,created_at,updated_at'))
        .timeout(const Duration(seconds: 12));
    (await _headers()).forEach(request.headers.set);
    request.headers.set('Prefer', 'return=representation');
    request.add(utf8.encode(jsonEncode({
      'id': order.id,
      'workspace_id': settings.workspaceId,
      'order_number': assignServerNumber ? null : _cleanText(order.orderNumber),
      'customer_user_id': userId,
      'customer_email': email,
      'status': order.status.name,
      'payload': payload,
    })));
    final response = await request.close().timeout(const Duration(seconds: 12));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudCatalogueException(body);
    }
    final decoded = jsonDecode(body);
    if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
      return _orderFromCloudRow(
          Map<String, Object?>.from(decoded.first as Map));
    }
    return order;
  }

  CustomerOrderDraft _orderFromCloudRow(Map<String, Object?> row) {
    final payload = row['payload'];
    final payloadMap = payload is Map
        ? Map<String, Object?>.from(payload)
        : <String, Object?>{};
    final accountId = (row['customer_user_id'] ?? '').toString();
    if (accountId.isNotEmpty && payloadMap['customerType'] != 'retail') {
      payloadMap['customerAccountId'] = accountId;
      payloadMap['customerType'] = 'regular';
    }
    final id = _cleanText((row['id'] ?? payloadMap['id'] ?? '').toString());
    final orderNumber = _cleanText(
      (row['order_number'] ?? payloadMap['orderNumber'] ?? '').toString(),
    );
    final status =
        _cleanText((row['status'] ?? payloadMap['status'] ?? '').toString());
    final createdAt = _cleanText(
      (row['created_at'] ?? payloadMap['createdAt'] ?? '').toString(),
    );
    final updatedAt = _cleanText(
      (row['updated_at'] ?? payloadMap['updatedAt'] ?? '').toString(),
    );
    payloadMap['id'] = id.isEmpty ? payloadMap['id'] : id;
    payloadMap['orderNumber'] =
        orderNumber.isEmpty ? payloadMap['orderNumber'] : orderNumber;
    payloadMap['status'] = status.isEmpty ? payloadMap['status'] : status;
    payloadMap['createdAt'] =
        createdAt.isEmpty ? payloadMap['createdAt'] : createdAt;
    payloadMap['updatedAt'] =
        updatedAt.isEmpty ? payloadMap['updatedAt'] : updatedAt;
    return CustomerOrderDraft.fromJson(payloadMap);
  }

  Future<CatalogueState> push(
    CatalogueState state, {
    CatalogueState? previousState,
  }) async {
    final syncTime = DateTime.now().toUtc().toIso8601String();
    final cloudState = (await _stateWithCloudImages(state)).copyWith(
      updatedAt: syncTime,
    );
    if (cloudState.photoInbox.isNotEmpty) {
      await _savePhotoInbox(cloudState.photoInbox, syncTime);
    }
    final request = await HttpClient()
        .postUrl(_restUri('on_conflict=workspace_id'))
        .timeout(const Duration(seconds: 12));
    (await _headers()).forEach(request.headers.set);
    request.headers.set('Prefer', 'resolution=merge-duplicates');
    request.add(utf8.encode(jsonEncode([
      {
        'workspace_id': settings.workspaceId,
        'payload': cloudState.toJson()..remove('photoInbox'),
        'updated_at': syncTime,
      }
    ])));
    final response = await request.close().timeout(const Duration(seconds: 12));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudCatalogueException(body);
    }
    await _deleteRemovedCloudImages(previousState, cloudState);
    return cloudState;
  }

  Future<void> _savePhotoInbox(
      List<PhotoInboxDraft> drafts, String syncTime) async {
    final request = await HttpClient()
        .postUrl(
            _tableUri('crimson_photo_inbox', 'on_conflict=workspace_id,id'))
        .timeout(const Duration(seconds: 12));
    (await _headers()).forEach(request.headers.set);
    request.headers.set('Prefer', 'resolution=merge-duplicates');
    request.add(utf8.encode(jsonEncode([
      for (final draft in drafts)
        {
          'workspace_id': settings.workspaceId,
          'id': draft.id,
          'payload': draft.toJson(),
          'updated_at': syncTime,
        },
    ])));
    final response = await request.close().timeout(const Duration(seconds: 12));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudCatalogueException('Photo inbox sync failed: $body');
    }
  }

  Future<CatalogueState> _stateWithCloudImages(CatalogueState state) async {
    final uploaded = <String, String>{};
    final products = <ProductDraft>[];
    for (final product in state.products) {
      final allPaths = <String>[...product.imagePaths, product.imagePath];
      final replacements = <String, String>{};
      for (final rawPath in allPaths) {
        final path = rawPath.trim();
        if (path.isEmpty || _isNetworkPath(path)) continue;
        final file = File(path);
        if (!await file.exists()) continue;
        replacements[path] =
            uploaded[path] ??= await _uploadImage(file, product.id);
      }
      if (replacements.isEmpty) {
        products.add(product);
        continue;
      }
      String replacePath(String path) => replacements[path.trim()] ?? path;
      final imageFinishTags = <String, String>{};
      for (final entry in product.imageFinishTags.entries) {
        final path = replacePath(entry.key);
        final finish = entry.value.trim();
        if (path.trim().isNotEmpty && finish.isNotEmpty) {
          imageFinishTags[path] = finish;
        }
      }
      products.add(product.copyWith(
        imagePath: replacePath(product.imagePath),
        imagePaths: product.imagePaths.map(replacePath).toList(),
        imageFinishTags: imageFinishTags,
      ));
    }

    Future<String> cloudPath(String rawPath, String ownerId) async {
      final path = rawPath.trim();
      if (path.isEmpty || _isNetworkPath(path)) return path;
      final file = File(path);
      if (!await file.exists()) return path;
      return uploaded[path] ??= await _uploadImage(file, ownerId);
    }

    final categories = <CategoryDraft>[];
    for (final category in state.categories) {
      final subcategoryImages = <String, String>{};
      for (final entry in category.subcategoryImages.entries) {
        subcategoryImages[entry.key] = await cloudPath(
          entry.value,
          'subcategory-${category.name}-${entry.key}',
        );
      }
      categories.add(category.copyWith(
        imagePath: await cloudPath(
          category.imagePath,
          'category-${category.name}',
        ),
        subcategoryImages: subcategoryImages,
      ));
    }

    final brandImages = <String, String>{};
    for (final entry in state.brandImages.entries) {
      brandImages[entry.key] = await cloudPath(
        entry.value,
        'brand-${entry.key}',
      );
    }

    final bannerImagePaths = <String>[];
    for (var index = 0; index < state.bannerImagePaths.length; index++) {
      bannerImagePaths.add(await cloudPath(
        state.bannerImagePaths[index],
        'banner-$index',
      ));
    }

    final photoInbox = <PhotoInboxDraft>[];
    for (final draft in state.photoInbox) {
      final images = <PhotoInboxImage>[];
      for (final image in draft.images) {
        final path = image.path.trim();
        if (path.isEmpty || _isNetworkPath(path)) {
          images.add(image);
          continue;
        }
        final file = File(path);
        if (!await file.exists()) {
          images.add(image);
          continue;
        }
        images.add(image.copyWith(
          path: uploaded[path] ??= await _uploadImage(
            file,
            draft.id,
            bucket: 'crimson-photo-inbox',
            private: true,
          ),
        ));
      }
      photoInbox.add(draft.copyWith(images: images));
    }
    return state.copyWith(
      products: products,
      photoInbox: photoInbox,
      categories: categories,
      brandImages: brandImages,
      bannerImagePaths: bannerImagePaths,
    );
  }

  Future<String> _uploadImage(
    File file,
    String productId, {
    String bucket = 'product-images',
    bool private = false,
  }) async {
    final base = settings.supabaseUrl.endsWith('/')
        ? settings.supabaseUrl.substring(0, settings.supabaseUrl.length - 1)
        : settings.supabaseUrl;
    final fileName = _safeFileName(file.path);
    final uploadId = DateTime.now().microsecondsSinceEpoch.toString();
    final storagePath =
        '${private ? 'photo-inbox' : 'flutter-catalogue'}/${_safeSegment(productId)}/$uploadId/$fileName';
    final encodedPath =
        storagePath.split('/').map(Uri.encodeComponent).join('/');
    final request = await HttpClient()
        .postUrl(Uri.parse('$base/storage/v1/object/$bucket/$encodedPath'))
        .timeout(const Duration(seconds: 30));
    request.headers.set('apikey', settings.anonKey);
    request.headers.set('Authorization', 'Bearer ${await _bearerToken()}');
    request.headers.set('Content-Type', _mimeType(file.path));
    request.add(await file.readAsBytes());
    final response = await request.close().timeout(const Duration(seconds: 30));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudCatalogueException('Image upload failed for $fileName: $body');
    }
    return '$base/storage/v1/object/${private ? 'authenticated' : 'public'}/$bucket/$encodedPath';
  }

  Future<File> resolvePhotoInboxImage(String path) async {
    if (!_isNetworkPath(path)) return File(path);
    final prefix =
        '$_baseUrl/storage/v1/object/authenticated/crimson-photo-inbox/';
    if (!path.startsWith(prefix)) {
      throw const CloudCatalogueException('Invalid photo inbox image path.');
    }
    final cached = File('${Directory.systemTemp.path}${Platform.pathSeparator}'
        'crimson-photo-${path.hashCode.toUnsigned(32)}${_imageExtension(path)}');
    if (await cached.exists() && await cached.length() > 0) return cached;
    final request = await HttpClient()
        .getUrl(Uri.parse(path))
        .timeout(const Duration(seconds: 30));
    request.headers.set('apikey', settings.anonKey);
    request.headers.set('Authorization', 'Bearer ${await _bearerToken()}');
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const CloudCatalogueException(
          'Photo inbox image could not be loaded.');
    }
    final bytes = await response.fold<List<int>>(<int>[], (data, chunk) {
      data.addAll(chunk);
      return data;
    });
    await cached.writeAsBytes(bytes, flush: true);
    return cached;
  }

  static String _imageExtension(String path) {
    final fileName = Uri.tryParse(path)?.pathSegments.last ?? path;
    final dot = fileName.lastIndexOf('.');
    if (dot < 0) return '.jpg';
    final extension = fileName.substring(dot).toLowerCase();
    return {'.jpg', '.jpeg', '.png', '.webp', '.heic'}.contains(extension)
        ? extension
        : '.jpg';
  }

  Future<void> _deleteRemovedCloudImages(
    CatalogueState? previousState,
    CatalogueState nextState,
  ) async {
    if (previousState == null) return;
    final previous = _networkImageUrls(previousState).toSet();
    final next = _networkImageUrls(nextState).toSet();
    final removedPaths = previous
        .difference(next)
        .map(_storageObjectPath)
        .whereType<String>()
        .toList();
    if (removedPaths.isEmpty) return;

    try {
      for (var offset = 0; offset < removedPaths.length; offset += 1000) {
        final end = offset + 1000 < removedPaths.length
            ? offset + 1000
            : removedPaths.length;
        await _deleteStorageObjects(removedPaths.sublist(offset, end));
      }
    } on Object {
      // The catalogue payload is already authoritative. Cleanup is best-effort
      // so a missing DELETE policy cannot make a successful sync look offline.
    }
  }

  Future<void> _deleteStorageObjects(List<String> storagePaths) async {
    final base = settings.supabaseUrl.endsWith('/')
        ? settings.supabaseUrl.substring(0, settings.supabaseUrl.length - 1)
        : settings.supabaseUrl;
    final request = await HttpClient()
        .deleteUrl(Uri.parse('$base/storage/v1/object/product-images'))
        .timeout(const Duration(seconds: 20));
    request.headers.set('apikey', settings.anonKey);
    request.headers.set('Authorization', 'Bearer ${await _bearerToken()}');
    request.headers.set('Content-Type', 'application/json');
    request.add(utf8.encode(jsonEncode({'prefixes': storagePaths})));
    final response = await request.close().timeout(const Duration(seconds: 20));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudCatalogueException('Image cleanup failed: $body');
    }
  }

  static Iterable<String> _networkImageUrls(CatalogueState state) sync* {
    for (final product in state.products) {
      for (final rawPath in [...product.imagePaths, product.imagePath]) {
        final path = rawPath.trim();
        if (_isNetworkPath(path)) yield path;
      }
    }
    for (final category in state.categories) {
      if (_isNetworkPath(category.imagePath.trim())) {
        yield category.imagePath.trim();
      }
      for (final path in category.subcategoryImages.values) {
        if (_isNetworkPath(path.trim())) yield path.trim();
      }
    }
    for (final path in state.brandImages.values) {
      if (_isNetworkPath(path.trim())) yield path.trim();
    }
    for (final path in state.bannerImagePaths) {
      if (_isNetworkPath(path.trim())) yield path.trim();
    }
  }

  String? _storageObjectPath(String publicUrl) {
    final base = settings.supabaseUrl.endsWith('/')
        ? settings.supabaseUrl.substring(0, settings.supabaseUrl.length - 1)
        : settings.supabaseUrl;
    if (!publicUrl.startsWith(base)) return null;
    const publicPrefix = '/storage/v1/object/public/product-images/';
    const authenticatedPrefix =
        '/storage/v1/object/authenticated/product-images/';
    final uri = Uri.tryParse(publicUrl);
    if (uri == null) return null;
    final path = uri.path;
    final prefix = path.startsWith(publicPrefix)
        ? publicPrefix
        : path.startsWith(authenticatedPrefix)
            ? authenticatedPrefix
            : null;
    if (prefix == null) return null;
    final encodedObjectPath = path.substring(prefix.length);
    if (encodedObjectPath.isEmpty) return null;
    return encodedObjectPath.split('/').map(Uri.decodeComponent).join('/');
  }

  static bool _isNetworkPath(String path) {
    final value = path.toLowerCase();
    return value.startsWith('https://') || value.startsWith('http://');
  }

  static bool _hasDuplicateProductIds(Map<dynamic, dynamic> json) {
    final seen = <String>{};
    final products = json['products'];
    if (products is! List) return false;
    for (final value in products) {
      if (value is! Map) continue;
      final id = (value['id'] ?? '').toString().trim();
      if (id.isEmpty || !seen.add(id)) return true;
    }
    return false;
  }

  static String _safeSegment(String value) {
    final clean = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return clean.isEmpty ? 'product' : clean;
  }

  static String _safeFileName(String path) {
    final original = path.split(RegExp(r'[\\/]')).last;
    final clean = original
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return clean.isEmpty ? 'product_image.jpg' : clean;
  }

  static String _mimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    return 'image/jpeg';
  }
}

class CloudCatalogueException implements Exception {
  const CloudCatalogueException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CloudSyncStatus {
  const CloudSyncStatus._({
    required this.label,
    required this.isWorking,
    required this.isWarning,
  });

  final String label;
  final bool isWorking;
  final bool isWarning;

  const CloudSyncStatus.localOnly()
      : this._(
          label: 'Local only',
          isWorking: false,
          isWarning: false,
        );

  const CloudSyncStatus.saving()
      : this._(
          label: 'Saving...',
          isWorking: true,
          isWarning: false,
        );

  const CloudSyncStatus.saved()
      : this._(
          label: 'Saved',
          isWorking: false,
          isWarning: false,
        );

  const CloudSyncStatus.updated()
      : this._(
          label: 'Updated just now',
          isWorking: false,
          isWarning: false,
        );

  const CloudSyncStatus.offlinePending()
      : this._(
          label: 'Offline - pending',
          isWorking: false,
          isWarning: true,
        );
}

String _cleanText(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ');
