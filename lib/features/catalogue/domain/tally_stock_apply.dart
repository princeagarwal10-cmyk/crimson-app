import 'catalogue_models.dart';
import 'tally_stock_import.dart';

class TallyApplyPreview {
  const TallyApplyPreview(
      {required this.plan, required this.payload, required this.writtenCount});
  final TallyStockPlan plan;
  final Map<String, Object?> payload;
  final int writtenCount;
}

/// Build a new raw cloud document without mutating the existing document.
/// Caller must commit it with the same revision used to create this preview.
TallyApplyPreview prepareTallyStockApply({
  required Map<String, Object?> payload,
  required List<TallyStockRow> rows,
  required Map<String, TallyStockLink> links,
  required List<TallyMatchCandidate> candidates,
  required DateTime snapshotAt,
  required DateTime now,
}) {
  final legacyVouchers = payload['stock_vouchers'];
  if (legacyVouchers != null && (legacyVouchers is! List || legacyVouchers.isNotEmpty)) {
    throw StateError('Legacy stock history needs reconciliation before import.');
  }
  if (snapshotAt.isAfter(now)) {
    throw StateError('Tally snapshot cannot be in the future.');
  }
  final catalogue = CatalogueState.fromJson(payload);
  final products = {
    for (final product in catalogue.products) product.id: product
  };
  bool targetStillExists(TallyMatchCandidate candidate) {
    final product = products[candidate.productId];
    if (product == null || product.isArchived) return false;
    String norm(String value) =>
        value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    if (candidate.stockItemId.trim().isNotEmpty) {
      return catalogue.stockItems.any((item) =>
          item.isActive &&
          item.id == candidate.stockItemId &&
          item.displayProductId == product.id &&
          norm(item.size) == norm(candidate.size) &&
          norm(item.finish) == norm(candidate.finish) &&
          norm(item.brand) == norm(candidate.brand) &&
          norm(item.stockSku.isEmpty ? item.id : item.stockSku) ==
              norm(candidate.stockSku));
    }
    if (norm(product.brand) != norm(candidate.brand)) return false;
    if (product.variations.isEmpty) {
      return norm(product.sizeSpec) == norm(candidate.size) &&
          norm(product.finishColor) == norm(candidate.finish) &&
          norm(product.sku.isNotEmpty
                  ? product.sku
                  : product.internalProductCode) ==
              norm(candidate.stockSku);
    }
    return product.variations
            .where((v) =>
                norm(v.size.isEmpty ? product.sizeSpec : v.size) ==
                    norm(candidate.size) &&
                norm(v.finish.isEmpty ? product.finishColor : v.finish) ==
                    norm(candidate.finish) &&
                norm(v.sku.isNotEmpty
                        ? v.sku
                        : (product.sku.isNotEmpty
                            ? product.sku
                            : product.internalProductCode)) ==
                    norm(candidate.stockSku))
            .length ==
        1;
  }

  final byId = {
    for (final candidate in candidates)
      if (targetStillExists(candidate)) candidate.targetKey: candidate
  };
  final physical = <String, double>{};
  final seen = <String>{};
  final movementTimes = <String, List<DateTime>>{};
  final unknownTime = <String>{};
  final otherWarehouse = <String>{};
  for (final voucher in catalogue.stockVouchers) {
    final sign = switch (voucher.type) {
      StockVoucherType.inward => 1.0,
      StockVoucherType.outward => -1.0,
      StockVoucherType.adjustment => 1.0,
      StockVoucherType.transfer => 0.0,
    };
    final time =
        DateTime.tryParse(voucher.createdAt) ?? DateTime.tryParse(voucher.date);
    for (final item in voucher.items) {
      final identity = item.stockItemId.trim().isNotEmpty
          ? item.stockItemId
          : [item.productId, item.stockSku, item.size, item.finish].join('|');
      physical[identity] = (physical[identity] ?? 0) + item.quantity * sign;
      seen.add(identity);
      if (time == null) {
        unknownTime.add(identity);
      } else {
        (movementTimes[identity] ??= []).add(time);
      }
      if (item.godown.trim().isNotEmpty &&
          item.godown.trim().toLowerCase() != 'main') {
        otherWarehouse.add(identity);
      }
    }
  }
  final plan = planTallyStockImport(rows, links, physical, byId.keys.toSet());
  final blocked = Map<int, String>.from(plan.blocked);
  final allowed = <TallyStockAdjustment>[];
  for (final adjustment in plan.adjustments) {
    final unit = adjustment.source.unit.toUpperCase();
    if (adjustment.source.warehouse.trim().isNotEmpty &&
        adjustment.source.warehouse.trim().toLowerCase() != 'main') {
      blocked[adjustment.source.rowNumber] =
          'Only Main warehouse is supported for this import';
    } else if (!{'PCS', 'PC', 'PIECES', 'PIECE'}.contains(unit) &&
        links[adjustment.source.sourceKey]?.conversionConfirmed != true) {
      blocked[adjustment.source.rowNumber] =
          'Packet or other unit needs a verified conversion';
    } else if (unknownTime.contains(adjustment.targetKey)) {
      blocked[adjustment.source.rowNumber] =
          'A previous stock movement has no valid date';
    } else if (otherWarehouse.contains(adjustment.targetKey)) {
      blocked[adjustment.source.rowNumber] =
          'Warehouse stock needs separate reconciliation';
    } else if ((movementTimes[adjustment.targetKey] ?? [])
        .any((time) => time.isAfter(snapshotAt))) {
      blocked[adjustment.source.rowNumber] =
          'A stock movement is newer than the Tally snapshot';
    } else {
      allowed.add(adjustment);
    }
  }
  final changed = allowed
      .where((item) => item.difference != 0 || !seen.contains(item.targetKey))
      .toList();
  final newPayload = Map<String, Object?>.from(payload);
  if (changed.isNotEmpty) {
    final lines = changed.map((adjustment) {
      final candidate = byId[adjustment.targetKey]!;
      return StockVoucherItemDraft(
          stockItemId: candidate.stockItemId,
          productId: candidate.productId,
          productName: candidate.productName,
          stockSku: candidate.stockSku,
          brand: candidate.brand,
          size: candidate.size,
          finish: candidate.finish,
          godown: 'Main',
          quantity: adjustment.difference,
          notes: adjustment.source.itemName);
    }).toList();
    final voucher = StockVoucherDraft(
        type: StockVoucherType.adjustment,
        voucherNumber: 'TALLY-${now.toUtc().microsecondsSinceEpoch}',
        date: now.toIso8601String(),
        createdAt: now.toUtc().toIso8601String(),
        reference: 'TALLY-IMPORT:${now.toUtc().microsecondsSinceEpoch}',
        notes: 'Tally closing stock as of ${snapshotAt.toIso8601String()}',
        items: lines);
    final existing = payload['stockVouchers'];
    if (existing != null && existing is! List) {
      throw StateError('Stock voucher data is invalid.');
    }
    newPayload['stockVouchers'] = [
      ...(existing as List? ?? const []),
      voucher.toJson()
    ];
    newPayload['updatedAt'] = now.toUtc().toIso8601String();
  }
  return TallyApplyPreview(
      plan: TallyStockPlan(allowed, blocked),
      payload: newPayload,
      writtenCount: changed.length);
}
