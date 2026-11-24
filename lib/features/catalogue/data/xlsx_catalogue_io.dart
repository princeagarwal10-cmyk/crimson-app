import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../../core/rules/catalogue_rules.dart';
import '../domain/catalogue_models.dart';

class XlsxCatalogueIo {
  /// Returns raw worksheet rows for import previews without modifying data.
  List<List<String>> readFirstWorksheet(String path) {
    final archive = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
    final sheet = _fileText(archive, _firstWorksheetPath(archive));
    if (sheet == null) {
      throw const FormatException('No first worksheet found in the Excel file.');
    }
    return _readSheetRows(sheet, _readSharedStrings(archive));
  }

  String _firstWorksheetPath(Archive archive) {
    final workbook = _fileText(archive, 'xl/workbook.xml');
    if (workbook == null) return 'xl/worksheets/sheet1.xml';
    final document = XmlDocument.parse(workbook);
    final sheets = document.findAllElements('sheet').toList();
    if (sheets.isEmpty) throw const FormatException('No worksheets found.');
    final relationshipId = sheets.first.attributes
        .where((attribute) => attribute.name.local == 'id' && attribute.name.prefix == 'r')
        .map((attribute) => attribute.value).firstOrNull;
    final relationships = _fileText(archive, 'xl/_rels/workbook.xml.rels');
    if (relationshipId == null || relationships == null) {
      throw const FormatException('Could not locate the first worksheet.');
    }
    final matches = XmlDocument.parse(relationships).findAllElements('Relationship')
        .where((element) => element.getAttribute('Id') == relationshipId).toList();
    if (matches.length != 1 || matches.first.getAttribute('TargetMode') == 'External') {
      throw const FormatException('Invalid worksheet relationship.');
    }
    final target = matches.first.getAttribute('Target') ?? '';
    final resolved = Uri.parse('xl/workbook.xml').resolve(target).path.replaceFirst(RegExp(r'^/'), '');
    if (!resolved.startsWith('xl/worksheets/') || !resolved.endsWith('.xml')) {
      throw const FormatException('Invalid worksheet location.');
    }
    return resolved;
  }

  BulkPasteImportResult importProducts(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return BulkPasteImportResult(
        products: const [],
        categories: const [],
        errors: ['Excel file not found: $path'],
      );
    }

    final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
    final sharedStrings = _readSharedStrings(archive);
    final sheet = _fileText(archive, 'xl/worksheets/sheet1.xml');
    if (sheet == null) {
      return const BulkPasteImportResult(
        products: [],
        categories: [],
        errors: ['No first worksheet found in the Excel file.'],
      );
    }

    final rows = _readSheetRows(sheet, sharedStrings);
    final text =
        rows.map((row) => row.map(_escapeTsvCell).join('\t')).join('\n');
    return parseBulkPasteProducts(text);
  }

  void exportProducts({
    required String path,
    required List<ProductDraft> products,
  }) {
    final rows = <List<String>>[
      [
        'INTERNAL PRODUCT ID',
        'GROUP NAME',
        'ITEM NAME',
        'CATEGORY',
        'SUBCATEGORY',
        'BRAND',
        'FINISH',
        'SIZE',
        'PRICE',
        'KEYWORDS'
      ],
      for (final product in products)
        for (final variation in product.variations)
          [
            product.internalProductCode,
            product.name,
            _sourceItemName(variation),
            product.category,
            product.subcategory,
            product.brand,
            variation.finish,
            variation.size,
            formatCompactPrice(variation.price),
            product.keywords.join(', '),
          ],
    ];

    _writeWorkbook(path: path, rows: rows);
  }

  void exportMissingImageReport({
    required String path,
    required List<ProductDraft> products,
  }) {
    final rows = <List<String>>[
      [
        'INTERNAL PRODUCT ID',
        'PRODUCT NAME',
        'SKU / CODE',
        'CATEGORY',
        'SUBCATEGORY',
        'BRAND',
        'PUBLISHED',
        'ARCHIVED',
        'VARIATIONS',
        'KEYWORDS',
        'NOTES',
      ],
      for (final product in products)
        [
          product.internalProductCode,
          product.name,
          product.sku,
          product.category,
          product.subcategory,
          product.brand,
          product.isPublished ? 'Published' : 'Not published',
          product.isArchived ? 'Archived' : 'Active',
          product.variations.length.toString(),
          product.keywords.join(', '),
          product.notes,
        ],
    ];
    _writeWorkbook(path: path, rows: rows);
  }

  void _writeWorkbook({
    required String path,
    required List<List<String>> rows,
  }) {
    final archive = Archive()
      ..addFile(ArchiveFile.string('[Content_Types].xml', _contentTypesXml))
      ..addFile(ArchiveFile.string('_rels/.rels', _rootRelsXml))
      ..addFile(ArchiveFile.string('docProps/app.xml', _appXml))
      ..addFile(ArchiveFile.string('docProps/core.xml', _coreXml))
      ..addFile(ArchiveFile.string('xl/workbook.xml', _workbookXml))
      ..addFile(
          ArchiveFile.string('xl/_rels/workbook.xml.rels', _workbookRelsXml))
      ..addFile(
          ArchiveFile.string('xl/worksheets/sheet1.xml', _sheetXml(rows)));

    final bytes = ZipEncoder().encode(archive);
    if (bytes == null) {
      throw const FileSystemException('Could not create Excel file.');
    }
    final outFile = File(path);
    outFile.parent.createSync(recursive: true);
    outFile.writeAsBytesSync(bytes);
  }

  List<String> _readSharedStrings(Archive archive) {
    final xmlText = _fileText(archive, 'xl/sharedStrings.xml');
    if (xmlText == null) return const [];
    final document = XmlDocument.parse(xmlText);
    return document.findAllElements('si').map((item) {
      return item.findAllElements('t').map((text) => text.innerText).join();
    }).toList();
  }

  List<List<String>> _readSheetRows(
      String sheetXml, List<String> sharedStrings) {
    final document = XmlDocument.parse(sheetXml);
    final rows = <List<String>>[];
    for (final rowElement in document.findAllElements('row')) {
      final row = <String>[];
      for (final cell in rowElement.findElements('c')) {
        final reference = cell.getAttribute('r') ?? '';
        final columnIndex = _columnIndex(reference);
        while (row.length <= columnIndex) {
          row.add('');
        }
        row[columnIndex] = _cellText(cell, sharedStrings);
      }
      rows.add(row);
    }
    return rows;
  }

  String _cellText(XmlElement cell, List<String> sharedStrings) {
    final type = cell.getAttribute('t');
    if (type == 'inlineStr') {
      return cell.findAllElements('t').map((text) => text.innerText).join();
    }
    final value = cell.findElements('v').isEmpty
        ? ''
        : cell.findElements('v').first.innerText;
    if (type == 's') {
      final index = int.tryParse(value) ?? -1;
      return index >= 0 && index < sharedStrings.length
          ? sharedStrings[index]
          : '';
    }
    return value;
  }

  int _columnIndex(String reference) {
    var column = 0;
    for (final codeUnit in reference.codeUnits) {
      final char = String.fromCharCode(codeUnit).toUpperCase();
      if (char.codeUnitAt(0) < 65 || char.codeUnitAt(0) > 90) break;
      column = column * 26 + (char.codeUnitAt(0) - 64);
    }
    return column == 0 ? 0 : column - 1;
  }

  String? _fileText(Archive archive, String name) {
    for (final file in archive.files) {
      if (file.name == name) {
        final content = file.content;
        if (content is List<int>) return utf8.decode(content);
        return utf8.decode(List<int>.from(content as Iterable));
      }
    }
    return null;
  }

  String _sourceItemName(VariationDraft variation) {
    final notes = variation.notes.trim();
    if (notes.toLowerCase().startsWith('source:')) {
      return notes.substring(7).trim();
    }
    return '';
  }

  String _sheetXml(List<List<String>> rows) {
    final rowXml = StringBuffer();
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final excelRow = rowIndex + 1;
      rowXml.write('<row r="$excelRow">');
      for (var columnIndex = 0;
          columnIndex < rows[rowIndex].length;
          columnIndex++) {
        final cellRef = '${_columnName(columnIndex)}$excelRow';
        rowXml.write(
          '<c r="$cellRef" t="inlineStr"><is><t>${_xmlEscape(rows[rowIndex][columnIndex])}</t></is></c>',
        );
      }
      rowXml.write('</row>');
    }
    return '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>$rowXml</sheetData>
</worksheet>
''';
  }

  String _columnName(int index) {
    var number = index + 1;
    final chars = <String>[];
    while (number > 0) {
      final remainder = (number - 1) % 26;
      chars.insert(0, String.fromCharCode(65 + remainder));
      number = (number - 1) ~/ 26;
    }
    return chars.join();
  }

  String _escapeTsvCell(String value) =>
      value.replaceAll('\t', ' ').replaceAll('\n', ' ');

  String _xmlEscape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

const _contentTypesXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>
''';

const _rootRelsXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>
''';

const _workbookXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="Products" sheetId="1" r:id="rId1"/></sheets>
</workbook>
''';

const _workbookRelsXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>
''';

const _appXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>Crimson Catalogue Studio</Application></Properties>
''';

const _coreXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:creator>Crimson Catalogue Studio</dc:creator></cp:coreProperties>
''';
