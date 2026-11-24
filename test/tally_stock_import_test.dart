import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crimson_catalogue_studio/features/catalogue/data/xlsx_catalogue_io.dart';
import 'package:crimson_catalogue_studio/features/catalogue/domain/tally_stock_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('blocks a stale preview and movements after the Tally snapshot', () {
    final cutoff = DateTime.utc(2026, 11, 24, 10);
    expect(
        validateTallySnapshotFence(
            reviewedRevision: 'one',
            currentRevision: 'two',
            snapshotAt: cutoff,
            movementTimes: []),
        isNotNull);
    expect(
        validateTallySnapshotFence(
            reviewedRevision: 'one',
            currentRevision: 'one',
            snapshotAt: cutoff,
            movementTimes: [cutoff.add(const Duration(seconds: 1))]),
        isNotNull);
    expect(
        validateTallySnapshotFence(
            reviewedRevision: 'one',
            currentRevision: 'one',
            snapshotAt: cutoff,
            movementTimes: [cutoff]),
        isNull);
    expect(
        validateTallySnapshotFence(
            reviewedRevision: '',
            currentRevision: '',
            snapshotAt: cutoff,
            movementTimes: []),
        isNotNull);
  });
  test(
      'rejects malformed number grouping while accepting Indian and international grouping',
      () {
    expect(parseTallyQuantity('1,23,456 PCS').$1, 123456);
    expect(parseTallyQuantity('1,234,567 PCS').$1, 1234567);
    expect(parseTallyQuantity('1,2 PCS').$1, isNull);
  });
  test('reads a 5000 item worksheet with blank and shared-string cells',
      () async {
    final temp = await Directory.systemTemp.createTemp('tally_import_');
    addTearDown(() => temp.delete(recursive: true));
    final sheet = StringBuffer('<worksheet><sheetData>');
    for (var i = 1; i <= 5000; i++) {
      sheet.write('<row r="$i"><c r="A$i" t="s"><v>0</v></c>'
          '<c r="B$i"><v>$i</v></c></row>');
    }
    sheet.write(
        '<row r="5001"><c r="A5001" t="inlineStr"><is><t>Blank quantity</t></is></c></row></sheetData></worksheet>');
    final archive = Archive()
      ..addFile(ArchiveFile.string(
          'xl/sharedStrings.xml', '<sst><si><t>AKSH HAWX</t></si></sst>'))
      ..addFile(
          ArchiveFile.string('xl/worksheets/sheet1.xml', sheet.toString()));
    final file = File('${temp.path}${Platform.pathSeparator}stock.xlsx');
    await file.writeAsBytes(ZipEncoder().encode(archive)!);
    final cells = XlsxCatalogueIo().readFirstWorksheet(file.path);
    final parsed = parseTallyStockRows(cells, itemColumn: 0, quantityColumn: 1);
    expect(parsed.length, 5001);
    expect(parsed.first.itemName, 'AKSH HAWX');
    expect(parsed[4999].quantity, 5000);
    expect(parsed.last.quantity, isNull);
  });
  test('reads quantities and units without turning blanks into zero', () {
    final rows = parseTallyStockRows([
      ['Item', 'Closing Balance'],
      ['AKSH HANDLE HAWX 6" R/G', '24 PCS'],
      ['AKSH HANDLE HAWX 6" WINTAGE', ''],
      ['AKSH G-CUT FISH HOOK', '2 PKT'],
      ['5310 HANDLE GOLD 12"', '0 PCS'],
      ['Bracket', '1,250 PCS'],
      ['Mixed', '1 PCS + 2 PKT'],
    ], itemColumn: 0, quantityColumn: 1, firstDataRow: 1);
    expect(rows.map((r) => r.quantity).toList(), [24, null, 2, 0, 1250, null]);
    expect(rows[0].unit, 'PCS');
    expect(rows[2].unit, 'PKT');
    expect(rows[1].hasValidQuantity, false);
  });

  test('retains punctuation and detects duplicate identities per warehouse',
      () {
    final rows = parseTallyStockRows([
      [' R-HAWX 6" ', '1', 'Main'],
      ['r-hawx   6"', '2', 'main'],
      ['R HAWX 6"', '3', 'Main'],
      ['R-HAWX 6"', '4', 'Shop'],
    ], itemColumn: 0, quantityColumn: 1, warehouseColumn: 2);
    expect(duplicateTallyKeys(rows), {rows[0].sourceKey});
    expect(rows[0].sourceKey, isNot(rows[2].sourceKey));
    expect(rows[0].sourceKey, isNot(rows[3].sourceKey));
  });

  test('plans closing balances as differences and repeats without doubling',
      () {
    final rows = parseTallyStockRows([
      ['Handle black 10"', '25 PCS'],
      ['Handle gold 10"', '0 PCS'],
      ['Handle gold 12"', ''],
      ['Handle packets', '2 PKT'],
    ], itemColumn: 0, quantityColumn: 1);
    final links = {
      for (var i = 0; i < rows.length; i++)
        rows[i].sourceKey: TallyStockLink(
            sourceKey: rows[i].sourceKey, targetKey: 'v$i', unit: 'PCS'),
    };
    final plan = planTallyStockImport(
        rows, links, {'v0': 20, 'v1': 12}, {'v0', 'v1', 'v2', 'v3'});
    expect(plan.adjustments.map((a) => a.difference).toList(), [5, -12]);
    expect(plan.blocked.keys, containsAll([3, 4]));
    final repeat = planTallyStockImport(
        rows, links, {'v0': 25, 'v1': 0}, {'v0', 'v1', 'v2', 'v3'});
    expect(repeat.adjustments.map((a) => a.difference).toList(), [0, 0]);
  });

  test('does not apply ambiguous mappings or duplicate sources', () {
    final rows = parseTallyStockRows([
      ['Handle A', '2 PCS'],
      ['Handle A', '3 PCS'],
      ['Handle B', '4 PCS'],
      ['Handle C', '5 PCS'],
    ], itemColumn: 0, quantityColumn: 1);
    final links = {
      rows[0].sourceKey: TallyStockLink(
          sourceKey: rows[0].sourceKey, targetKey: 'a', unit: 'PCS'),
      rows[2].sourceKey: TallyStockLink(
          sourceKey: rows[2].sourceKey, targetKey: 'b', unit: 'PCS'),
      rows[3].sourceKey: TallyStockLink(
          sourceKey: rows[3].sourceKey, targetKey: 'b', unit: 'PCS'),
    };
    final plan = planTallyStockImport(rows, links, {}, {'a', 'b'});
    expect(plan.adjustments, isEmpty);
    expect(plan.blocked.length, 4);
  });

  test('suggestions rank likely variation without creating a mapping', () {
    final candidates = [
      TallyMatchCandidate(
          targetKey: 'other', label: 'AKSH HAWX HANDLE BLACK 8"'),
      TallyMatchCandidate(targetKey: 'match', label: 'AKSH HAWX HANDLE R/G 6"'),
    ];
    final result = suggestTallyMatches('AKSH HANDLE HAWX 6" R/G', candidates);
    expect(result.first.targetKey, 'match');
    expect(result.length, 2);
  });
}
