import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/windows_file_dialogs.dart';
import '../data/xlsx_catalogue_io.dart';
import '../data/cloud_catalogue_repository.dart';
import '../domain/tally_stock_import.dart';
import '../domain/tally_stock_apply.dart';

/// Review saved mappings and apply confirmed closing stock adjustments.
class TallyStockReviewScreen extends StatefulWidget {
  const TallyStockReviewScreen(
      {super.key, required this.variations, this.repository, this.refresh, this.pickWorkbook});
  final List<TallyMatchCandidate> variations;
  final Future<CloudCatalogueRepository?> Function()? repository;
  final Future<void> Function()? refresh;
  final Future<String?> Function()? pickWorkbook;

  @override
  State<TallyStockReviewScreen> createState() => _TallyStockReviewScreenState();
}

class _TallyStockReviewScreenState extends State<TallyStockReviewScreen> {
  List<List<String>> _cells = [];
  List<TallyStockRow> _rows = [];
  final Map<int, TallyMatchCandidate> _links = {};
  Map<String, TallyStockLink> _savedLinks = {};
  int _nameColumn = 0;
  int _quantityColumn = 1;
  int? _unitColumn;
  int? _codeColumn;
  int? _warehouseColumn;
  int _firstDataRow = 0;
  String _fileName = '';
  String _error = '';
  VersionedCataloguePayload? _snapshot;
  DateTime? _asOf;
  bool _saving = false;
  bool _useSavedUnits = false;

  Future<void> _chooseWorkbook() async {
    try {
      final String? path;
      if (widget.pickWorkbook != null) {
        path = await widget.pickWorkbook!();
      } else if (Platform.isAndroid) {
        path =
            await const MethodChannel('com.mycrimson.cataloguestudio/storage')
                .invokeMethod<String>('pickStockWorkbook');
      } else if (Platform.isWindows) {
        path = await const WindowsFileDialogs().pickExcelFile();
      } else {
        throw UnsupportedError(
            'Excel import is available on Android and Windows.');
      }
      if (path == null || path.trim().isEmpty) return;
      final cells = XlsxCatalogueIo().readFirstWorksheet(path);
      final fileName = path.split(RegExp(r'[/\\]')).last;
      final repository = await widget.repository?.call();
      if (repository == null) {
        throw StateError(
            'Sign in as an admin and connect to the cloud to load saved mappings.');
      }
      final savedLinks = await repository.pullTallyLinks();
      final snapshot = await repository.pullVersionedForStock();
      if (!mounted) return;
      setState(() {
        _cells = cells;
        _nameColumn = 0;
        _quantityColumn = 1;
        _unitColumn = null;
        _codeColumn = null;
        _warehouseColumn = null;
        _firstDataRow = 0;
        _fileName = fileName;
        _savedLinks = savedLinks;
        _snapshot = snapshot;
        _asOf = null;
        _useSavedUnits = false;
        _links.clear();
        _error = '';
        _parse();
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Could not read workbook: $error');
    }
  }

  Future<void> _chooseAsOf() async {
    final now = DateTime.now();
    final date = await showDatePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: now,
        initialDate: now);
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(now));
    if (time == null || !mounted) return;
    setState(() {
      _asOf = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _error = '';
    });
  }

  TallyApplyPreview? _preview() {
    if (_snapshot == null || _asOf == null || _nameColumn == _quantityColumn) {
      return null;
    }
    final effectiveRows = _rows.map((row) {
      final savedUnit = _savedLinks[row.sourceKey]?.unit ?? '';
      if (!_useSavedUnits || row.unit.isNotEmpty || savedUnit.isEmpty) {
        return row;
      }
      return TallyStockRow(
          rowNumber: row.rowNumber,
          itemName: row.itemName,
          rawQuantity: row.rawQuantity,
          quantity: row.quantity,
          unit: savedUnit,
          itemCode: row.itemCode,
          warehouse: row.warehouse);
    }).toList();
    return prepareTallyStockApply(
        payload: _snapshot!.payload,
        rows: effectiveRows,
        links: _savedLinks,
        candidates: widget.variations,
        snapshotAt: _asOf!,
        now: DateTime.now());
  }

  Future<void> _apply() async {
    if (_saving) return;
    try {
      final preview = _preview();
      if (preview == null || preview.writtenCount == 0) {
        throw StateError('No safe stock changes to apply.');
      }
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Apply Tally stock?'),
                content: Text(
                    'Update ${preview.writtenCount} linked variations? ${preview.plan.blocked.length} rows need review and will be left unchanged. Stock is adjusted to the physical closing balances shown in this preview.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Apply stock'))
                ],
              ));
      if (confirmed != true || !mounted) return;
      setState(() => _saving = true);
      final repository = await widget.repository?.call();
      if (repository == null) throw StateError('Cloud connection required.');
      final saved = await repository.writeStockPayloadIfUnchanged(
          revision: _snapshot!.revision, payload: preview.payload);
      if (!saved) {
        throw StateError(
            'Stock changed after this preview. Reopen the file and review again.');
      }
      await widget.refresh?.call();
      final updated = await repository.pullVersionedForStock();
      if (!mounted) return;
      setState(() {
        _snapshot = updated;
        _asOf = null;
        _error = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stock adjustments saved.')));
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Could not apply stock: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _parse() {
    _rows = parseTallyStockRows(_cells,
        itemColumn: _nameColumn,
        quantityColumn: _quantityColumn,
        unitColumn: _unitColumn,
        codeColumn: _codeColumn,
        warehouseColumn: _warehouseColumn,
        firstDataRow: _firstDataRow);
    _links.clear();
    final byId = {
      for (final variation in widget.variations) variation.targetKey: variation
    };
    for (final row in _rows) {
      final target = _savedLinks[row.sourceKey]?.targetKey;
      if (target != null && byId[target] != null) {
        _links[row.rowNumber] = byId[target]!;
      }
    }
  }

  Future<void> _chooseVariation(TallyStockRow row) async {
    final query = TextEditingController(text: row.itemName);
    try {
      final selected = await showDialog<TallyMatchCandidate>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, update) {
          final suggestions =
              suggestTallyMatches(query.text, widget.variations, limit: 30);
          return AlertDialog(
            title: const Text('Link existing variation'),
            content: SizedBox(
                width: 640,
                height: 500,
                child: Column(children: [
                  TextField(
                      controller: query,
                      onChanged: (_) => update(() {}),
                      decoration: const InputDecoration(
                          labelText: 'Search product, finish, size or brand')),
                  Expanded(
                      child: ListView.builder(
                          itemCount: suggestions.length,
                          itemBuilder: (context, index) => ListTile(
                                title: Text(suggestions[index].label),
                                onTap: () =>
                                    Navigator.pop(context, suggestions[index]),
                              ))),
                ])),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'))
            ],
          );
        }),
      );
      if (selected != null && mounted) {
        if (duplicateTallyKeys(_rows).contains(row.sourceKey)) {
          setState(() => _error =
              'This item appears more than once. Review duplicate rows before linking.');
          return;
        }
        var unit = row.unit;
        if (unit.isEmpty) {
          final controller = TextEditingController();
          try {
            unit = (await showDialog<String>(
                    context: context,
                    builder: (context) => AlertDialog(
                          title: const Text('Confirm Tally unit'),
                          content: TextField(
                              controller: controller,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                  labelText: 'Unit, for example PCS or PKT')),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel')),
                            FilledButton(
                                onPressed: () => Navigator.pop(context,
                                    controller.text.trim().toUpperCase()),
                                child: const Text('Confirm'))
                          ],
                        ))) ??
                '';
          } finally {
            controller.dispose();
          }
          if (unit.isEmpty || !mounted) return;
        }
        var multiplier = 1.0;
        var conversionConfirmed = false;
        if (!{'PCS', 'PC', 'PIECE', 'PIECES'}.contains(unit.toUpperCase())) {
          final controller = TextEditingController();
          try {
            final value = await showDialog<String>(
                context: context,
                builder: (context) => AlertDialog(
                        title: Text('Convert $unit to pieces'),
                        content: TextField(
                            controller: controller,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                                labelText: 'Pieces in 1 $unit')),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel')),
                          FilledButton(
                              onPressed: () => Navigator.pop(
                                  context, controller.text.trim()),
                              child: const Text('Confirm'))
                        ]));
            final parsed = double.tryParse(value ?? '');
            if (parsed == null ||
                !parsed.isFinite ||
                parsed <= 0 ||
                parsed > 1000000) {
              if (mounted) {
                setState(() => _error =
                    'Enter a valid conversion to pieces before saving this mapping.');
              }
              return;
            }
            multiplier = parsed;
            conversionConfirmed = true;
          } finally {
            controller.dispose();
          }
          if (!mounted) return;
        }
        final repository = await widget.repository?.call();
        if (repository == null) throw StateError('Cloud connection required.');
        final link = TallyStockLink(
            sourceKey: row.sourceKey,
            targetKey: selected.targetKey,
            unit: unit,
            multiplier: multiplier,
            conversionConfirmed: conversionConfirmed);
        await repository.saveTallyLink(row, link);
        if (!mounted) return;
        setState(() {
          _savedLinks[row.sourceKey] = link;
          _links[row.rowNumber] = selected;
          _error = '';
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Could not save mapping: $error');
    } finally {
      query.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final columnCount =
        _cells.fold<int>(0, (n, row) => row.length > n ? row.length : n);
    final duplicates = duplicateTallyKeys(_rows);
    TallyApplyPreview? preview;
    try {
      preview = _preview();
    } on Object {
      preview = null;
    }
    final changes = {
      for (final change
          in preview?.plan.adjustments ?? <TallyStockAdjustment>[])
        change.source.rowNumber: change
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Review Tally stock')),
      body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                        onPressed: _chooseWorkbook,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Choose Excel file')),
                    if (_fileName.isNotEmpty) Text(_fileName),
                  ]),
              if (_error.isNotEmpty)
                Text(_error, style: const TextStyle(color: Colors.red)),
              if (columnCount >= 2) ...[
                Wrap(spacing: 12, children: [
                  DropdownButton<int>(
                      value: _nameColumn,
                      items: [
                        for (var i = 0; i < columnCount; i++)
                          DropdownMenuItem(
                              value: i, child: Text('Item column ${i + 1}'))
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _nameColumn = v;
                            _parse();
                          });
                        }
                      }),
                  DropdownButton<int>(
                      value: _quantityColumn,
                      items: [
                        for (var i = 0; i < columnCount; i++)
                          DropdownMenuItem(
                              value: i, child: Text('Stock column ${i + 1}'))
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _quantityColumn = v;
                            _parse();
                          });
                        }
                      }),
                  DropdownButton<int>(
                      value: _unitColumn ?? -1,
                      items: [
                        const DropdownMenuItem(
                            value: -1, child: Text('Unit in quantity')),
                        for (var i = 0; i < columnCount; i++)
                          DropdownMenuItem(
                              value: i, child: Text('Unit column ${i + 1}')),
                      ],
                      onChanged: (v) => setState(() {
                            _unitColumn = v == -1 ? null : v;
                            _parse();
                          })),
                  DropdownButton<int>(
                      value: _codeColumn ?? -1,
                      items: [
                        const DropdownMenuItem(
                            value: -1, child: Text('No item code')),
                        for (var i = 0; i < columnCount; i++)
                          DropdownMenuItem(
                              value: i, child: Text('Code column ${i + 1}')),
                      ],
                      onChanged: (v) => setState(() {
                            _codeColumn = v == -1 ? null : v;
                            _parse();
                          })),
                  DropdownButton<int>(
                      value: _warehouseColumn ?? -1,
                      items: [
                        const DropdownMenuItem(
                            value: -1, child: Text('No warehouse column')),
                        for (var i = 0; i < columnCount; i++)
                          DropdownMenuItem(
                              value: i,
                              child: Text('Warehouse column ${i + 1}')),
                      ],
                      onChanged: (v) => setState(() {
                            _warehouseColumn = v == -1 ? null : v;
                            _parse();
                          })),
                  FilterChip(
                      label: const Text('First row is a header'),
                      selected: _firstDataRow == 1,
                      onSelected: (value) => setState(() {
                            _firstDataRow = value ? 1 : 0;
                            _parse();
                          })),
                  FilterChip(
                      label:
                          const Text('Use saved units for unitless quantities'),
                      selected: _useSavedUnits,
                      onSelected: (value) =>
                          setState(() => _useSavedUnits = value)),
                ]),
                Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                          onPressed: _chooseAsOf,
                          icon: const Icon(Icons.schedule),
                          label: Text(_asOf == null
                              ? 'Set Tally snapshot date and time'
                              : 'As of ${_asOf!.toString().substring(0, 16)}')),
                      FilledButton(
                          onPressed:
                              !_saving && (preview?.writtenCount ?? 0) > 0
                                  ? _apply
                                  : null,
                          child: Text(
                              _saving ? 'Saving...' : 'Apply reviewed stock')),
                    ]),
                Text(
                    '${_rows.length} rows · ${_links.length} saved links · ${preview?.writtenCount ?? 0} changes · ${preview?.plan.blocked.length ?? 0} need review'),
                const Text(
                    'Only linked, valid quantities are applied. Packets need a confirmed conversion to pieces; blank stock, duplicates and unmatched items remain unchanged.'),
                if (_nameColumn == _quantityColumn)
                  const Text(
                      'Choose different columns for item name and stock.'),
                Expanded(
                    child: ListView.builder(
                        itemCount: _rows.length,
                        itemBuilder: (context, index) {
                          final row = _rows[index];
                          final change = changes[row.rowNumber];
                          final issue = preview?.plan.blocked[row.rowNumber] ??
                              (duplicates.contains(row.sourceKey)
                                  ? 'Duplicate item'
                                  : !row.hasValidQuantity
                                      ? 'Quantity needs review'
                                      : row.rawQuantity);
                          return ListTile(
                              title: Text(row.itemName),
                              subtitle: Text(
                                  '$issue · ${_links[row.rowNumber]?.label ?? 'Not linked'}${change == null ? '' : ' · ${change.current} → ${change.closing}'}'),
                              trailing: TextButton(
                                  onPressed: () => _chooseVariation(row),
                                  child: const Text('Link')));
                        })),
              ] else if (_cells.isNotEmpty)
                const Text('Choose a worksheet with at least two columns.'),
            ],
          )),
    );
  }
}
