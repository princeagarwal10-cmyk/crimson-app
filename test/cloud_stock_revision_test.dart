import 'dart:convert';
import 'dart:io';

import 'package:crimson_catalogue_studio/features/catalogue/data/cloud_catalogue_repository.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/tally_stock_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads and saves a confirmed mapping without changing stock', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    Map<String, dynamic>? saved;
    server.listen((request) async {
      if (request.method == 'GET') {
        request.response.write(jsonEncode([
          {
            'source_key': 'NAME:HANDLE|WAREHOUSE:',
            'target_identity': 'target',
            'unit': 'PCS',
            'multiplier': 1
          }
        ]));
      } else {
        saved = jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
        request.response.statusCode = 201;
      }
      await request.response.close();
    });
    final repository = CloudCatalogueRepository(
        CloudCatalogueSettings(
            supabaseUrl: 'http://127.0.0.1:${server.port}', anonKey: 'test'),
        accessToken: 'test');
    final mappings = await repository.pullTallyLinks();
    final row = parseTallyStockRows([
      ['Handle', '2 PCS']
    ], itemColumn: 0, quantityColumn: 1)
        .single;
    expect(mappings[row.sourceKey]?.targetKey, 'target');
    await repository.saveTallyLink(row, mappings[row.sourceKey]!);
    expect(saved?['source_key'], row.sourceKey);
    expect(saved?['target_identity'], 'target');
    expect(saved?.containsKey('quantity'), isFalse);
  });
  test('conditional stock write preserves revision and rejects a stale preview',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <HttpRequest>[];
    Map<String, dynamic>? sent;
    server.listen((request) async {
      requests.add(request);
      if (request.method == 'GET') {
        request.response.write(jsonEncode([
          {
            'payload': {'stockVouchers': [], 'futureField': 42},
            'updated_at': '2026-11-24T12:00:00+00:00'
          }
        ]));
      } else {
        sent = jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
        request.response.write('false');
      }
      await request.response.close();
    });
    final repository = CloudCatalogueRepository(
        CloudCatalogueSettings(
            supabaseUrl: 'http://127.0.0.1:${server.port}', anonKey: 'test'),
        accessToken: 'test');
    final snapshot = await repository.pullVersionedForStock();
    expect(snapshot.payload['futureField'], 42);
    expect(
        await repository.writeStockPayloadIfUnchanged(
            revision: snapshot.revision, payload: snapshot.payload),
        isFalse);
    expect(requests.last.uri.path, '/rest/v1/rpc/crimson_apply_tally_stock');
    expect(sent?['p_expected'], '2026-11-24T12:00:00+00:00');
  });
}
