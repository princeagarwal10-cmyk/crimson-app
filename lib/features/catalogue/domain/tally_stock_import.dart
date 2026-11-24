/// A Tally row before any catalogue or inventory data is modified.
class TallyStockRow {
  const TallyStockRow(
      {required this.rowNumber,
      required this.itemName,
      required this.rawQuantity,
      required this.quantity,
      required this.unit,
      this.itemCode = '',
      this.warehouse = ''});

  final int rowNumber;
  final String itemName, itemCode, warehouse, rawQuantity, unit;
  final double? quantity;

  /// Names are compared conservatively: spacing and case only. Punctuation,
  /// size and finish remain significant, so distinct items cannot merge.
  String get sourceKey => tallySourceKey(itemName, itemCode, warehouse);
  bool get hasValidQuantity => quantity != null && quantity!.isFinite;
}

String tallySourceKey(String name, String code, String warehouse) {
  String normalize(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  return '${code.trim().isEmpty ? 'NAME:${normalize(name)}' : 'CODE:${normalize(code)}'}|WAREHOUSE:${normalize(warehouse)}';
}

/// Parses a quantity and its unit. Blank, compound quantities and unknown
/// formats remain unresolved and must never be interpreted as zero.
(double?, String) parseTallyQuantity(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return (null, '');
  final match = RegExp(
          r'^([+-]?(?:\d+|\d{1,3}(?:,\d{3})+|\d{1,2}(?:,\d{2})+,\d{3})(?:\.\d+)?)\s*([a-zA-Z.]+)?$')
      .firstMatch(text);
  if (match == null) return (null, '');
  final value = double.tryParse(match.group(1)!.replaceAll(',', ''));
  if (value == null || !value.isFinite) return (null, '');
  return (value, (match.group(2) ?? '').toUpperCase());
}

/// Explicit column selection avoids mistaking opening stock, value or rates
/// for closing stock in differently shaped Tally exports.
List<TallyStockRow> parseTallyStockRows(
  List<List<String>> rows, {
  required int itemColumn,
  required int quantityColumn,
  int? codeColumn,
  int? unitColumn,
  int? warehouseColumn,
  int firstDataRow = 0,
}) {
  String cell(List<String> row, int? column) =>
      column == null || column < 0 || column >= row.length
          ? ''
          : row[column].trim();
  final result = <TallyStockRow>[];
  for (var i = firstDataRow; i < rows.length; i++) {
    final row = rows[i];
    final name = cell(row, itemColumn);
    if (name.isEmpty) continue;
    final raw = cell(row, quantityColumn);
    final parsed = parseTallyQuantity(raw);
    final separateUnit = cell(row, unitColumn).toUpperCase();
    result.add(TallyStockRow(
        rowNumber: i + 1,
        itemName: name,
        rawQuantity: raw,
        quantity: parsed.$1,
        unit: parsed.$2.isEmpty ? separateUnit : parsed.$2,
        itemCode: cell(row, codeColumn),
        warehouse: cell(row, warehouseColumn)));
  }
  return result;
}

/// Returns all colliding keys rather than arbitrarily selecting a row.
Set<String> duplicateTallyKeys(Iterable<TallyStockRow> rows) {
  final seen = <String>{};
  final duplicates = <String>{};
  for (final row in rows) {
    if (!seen.add(row.sourceKey)) duplicates.add(row.sourceKey);
  }
  return duplicates;
}

/// A confirmed link uses an exact, pre-existing stock variation identity.
class TallyStockLink {
  const TallyStockLink(
      {required this.sourceKey,
      required this.targetKey,
      required this.unit,
      this.multiplier = 1,
      this.conversionConfirmed = false});
  final String sourceKey, targetKey, unit;

  /// Units are never converted unless the administrator explicitly supplies it.
  final double multiplier;
  final bool conversionConfirmed;
}

/// A suggestion is never an approved mapping, even when it scores highly.
class TallyMatchCandidate {
  const TallyMatchCandidate(
      {required this.targetKey,
      required this.label,
      this.productId = '',
      this.productName = '',
      this.stockItemId = '',
      this.stockSku = '',
      this.brand = '',
      this.size = '',
      this.finish = ''});
  final String targetKey, label;
  final String productId,
      productName,
      stockItemId,
      stockSku,
      brand,
      size,
      finish;
}

List<TallyMatchCandidate> suggestTallyMatches(
    String name, Iterable<TallyMatchCandidate> candidates,
    {int limit = 8}) {
  Set<String> tokens(String value) => value
      .toUpperCase()
      .replaceAll('"', ' INCH ')
      .split(RegExp(r'[^A-Z0-9]+'))
      .where((token) => token.isNotEmpty)
      .toSet();
  final wanted = tokens(name);
  if (wanted.isEmpty || limit <= 0) return [];
  final ranked = <(TallyMatchCandidate, double)>[];
  for (final candidate in candidates) {
    final candidateTokens = tokens(candidate.label);
    if (candidateTokens.isEmpty) continue;
    final shared = wanted.intersection(candidateTokens).length;
    if (shared == 0) continue;
    final score = shared / wanted.union(candidateTokens).length;
    ranked.add((candidate, score));
  }
  ranked.sort((a, b) {
    final byScore = b.$2.compareTo(a.$2);
    return byScore != 0 ? byScore : a.$1.label.compareTo(b.$1.label);
  });
  return ranked.take(limit).map((entry) => entry.$1).toList();
}

class TallyStockAdjustment {
  const TallyStockAdjustment(
      {required this.source,
      required this.targetKey,
      required this.current,
      required this.closing,
      required this.difference});
  final TallyStockRow source;
  final String targetKey;
  final double current, closing, difference;
}

class TallyStockPlan {
  const TallyStockPlan(this.adjustments, this.blocked);
  final List<TallyStockAdjustment> adjustments;

  /// Row numbers and reasons that require human review.
  final Map<int, String> blocked;
}

/// The import can only be committed against the same cloud revision that was
/// reviewed. Historical snapshots need explicit handling of later movements.
String? validateTallySnapshotFence({
  required String reviewedRevision,
  required String currentRevision,
  required DateTime snapshotAt,
  required Iterable<DateTime> movementTimes,
}) {
  if (reviewedRevision.trim().isEmpty || currentRevision.trim().isEmpty) {
    return 'Cloud revision is unavailable; refresh before importing.';
  }
  if (reviewedRevision != currentRevision) {
    return 'Stock changed after the preview; refresh and review again.';
  }
  final cutoff = snapshotAt.toUtc();
  if (movementTimes.any((movement) => movement.toUtc().isAfter(cutoff))) {
    return 'Stock movements after the Tally snapshot need reconciliation.';
  }
  return null;
}

/// Prepares changes only; it never writes stock. The caller must recheck the
/// snapshot in the same transaction used to commit its adjustment vouchers.
TallyStockPlan planTallyStockImport(
    Iterable<TallyStockRow> sourceRows,
    Map<String, TallyStockLink> links,
    Map<String, double> currentBalances,
    Set<String> validTargets) {
  final rows = sourceRows.toList();
  final duplicateSources = duplicateTallyKeys(rows);
  final targetCounts = <String, int>{};
  for (final row in rows) {
    final link = links[row.sourceKey];
    if (link != null) {
      targetCounts[link.targetKey] = (targetCounts[link.targetKey] ?? 0) + 1;
    }
  }
  final blocked = <int, String>{};
  final adjustments = <TallyStockAdjustment>[];
  for (final row in rows) {
    final link = links[row.sourceKey];
    String? issue;
    if (duplicateSources.contains(row.sourceKey)) {
      issue = 'Duplicate Tally item';
    } else if (link == null || !validTargets.contains(link.targetKey)) {
      issue = 'Map to an existing variation';
    } else if ((targetCounts[link.targetKey] ?? 0) > 1) {
      issue = 'Multiple rows map to the same variation';
    } else if (!row.hasValidQuantity) {
      issue = 'Quantity is blank or invalid';
    } else if (row.unit.isEmpty || row.unit != link.unit.toUpperCase()) {
      issue = 'Confirm the unit';
    } else if (!link.multiplier.isFinite || link.multiplier <= 0) {
      issue = 'Invalid unit conversion';
    }
    if (issue != null) {
      blocked[row.rowNumber] = issue;
      continue;
    }
    final target = link!;
    final current = currentBalances[target.targetKey] ?? 0;
    final closing = row.quantity! * target.multiplier;
    if (!current.isFinite || !closing.isFinite) {
      blocked[row.rowNumber] = 'Quantity is outside the supported range';
      continue;
    }
    adjustments.add(TallyStockAdjustment(
        source: row,
        targetKey: target.targetKey,
        current: current,
        closing: closing,
        difference: closing - current));
  }
  return TallyStockPlan(adjustments, blocked);
}
