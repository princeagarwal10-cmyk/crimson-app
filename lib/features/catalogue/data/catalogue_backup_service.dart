import 'dart:convert';
import 'dart:io';

import '../domain/catalogue_models.dart';

class CatalogueBackupService {
  const CatalogueBackupService();

  Future<void> exportBackup({
    required CatalogueState state,
    required String path,
  }) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert({
        'format': 'crimson-catalogue-backup-v1',
        'exportedAt': DateTime.now().toIso8601String(),
        'catalogue': state.toJson(),
      }),
    );
  }

  Future<CatalogueState> readBackup(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const FileSystemException('The selected backup file is missing.');
    }

    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('This is not a valid Crimson backup.');
    }

    final root = Map<String, Object?>.from(decoded);
    final catalogueValue = root['catalogue'];
    final catalogue = catalogueValue is Map
        ? Map<String, Object?>.from(catalogueValue)
        : root;

    if (catalogue['products'] is! List) {
      throw const FormatException(
        'This backup does not contain a product catalogue.',
      );
    }
    return CatalogueState.fromJson(catalogue);
  }
}
