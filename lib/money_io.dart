import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'store.dart';

/// Export and import of transactions as CSV or Excel (.xlsx).
class MoneyIO {
  static const header = ['Date', 'Time', 'Type', 'Amount', 'Category', 'Account', 'To Account', 'Note', 'Description', 'Tags'];

  static List<List<Object?>> _rows(Iterable<Rec> txs) => [
        for (final t in txs)
          [
            dayKey(fromMs(t['ts'] as int)),
            clock(t['ts'] as int),
            t['type'],
            t['amount'],
            t['cat'],
            t['account'],
            t['toAccount'],
            t['note'],
            t['desc'],
            ((t['tags'] as List?) ?? []).join(', '),
          ],
      ];

  static String _csvCell(Object? v) {
    final s = v?.toString() ?? '';
    return s.contains(RegExp(r'[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  static Uint8List toCsv(Iterable<Rec> txs) {
    final lines = [header, ..._rows(txs)].map((r) => r.map(_csvCell).join(','));
    // The BOM makes Excel open the file as UTF-8, so ৳ and Bangla text show correctly.
    return Uint8List.fromList(utf8.encode('﻿${lines.join('\r\n')}\r\n'));
  }

  static Uint8List toXlsx(Iterable<Rec> txs) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    final sheet = excel['Transactions'];
    if (defaultSheet != null && defaultSheet != 'Transactions') excel.delete(defaultSheet);
    sheet.appendRow([for (final h in header) TextCellValue(h)]);
    for (final r in _rows(txs)) {
      sheet.appendRow([
        for (final v in r)
          v == null ? null : (v is num ? DoubleCellValue(v.toDouble()) : TextCellValue(v.toString())),
      ]);
    }
    return Uint8List.fromList(excel.encode()!);
  }

  /// Asks where to save, and saves. Returns false if cancelled.
  static Future<bool> export(Store s, Iterable<Rec> txs, {required bool xlsx, required String name}) async {
    final bytes = xlsx ? toXlsx(txs) : toCsv(txs);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save transactions',
      fileName: '$name.${xlsx ? 'xlsx' : 'csv'}',
      bytes: bytes,
    );
    // On the web the file downloads straight away and no path comes back.
    return kIsWeb || path != null;
  }

  // ---------- import ----------

  static List<List<String>> _parseCsv(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(c);
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == ',' || c == '\t') {
        row.add(cell.toString());
        cell.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString());
        cell.clear();
        if (row.any((e) => e.trim().isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        cell.write(c);
      }
    }
    row.add(cell.toString());
    if (row.any((e) => e.trim().isNotEmpty)) rows.add(row);
    return rows;
  }

  static String _cellText(Data? d) {
    final v = d?.value;
    if (v == null) return '';
    if (v is DateTimeCellValue) return v.asDateTimeLocal().toIso8601String();
    if (v is DateCellValue) return v.asDateTimeLocal().toIso8601String();
    if (v is TimeCellValue) return '${two(v.hour)}:${two(v.minute)}';
    if (v is DoubleCellValue) return '${v.value}';
    if (v is IntCellValue) return '${v.value}';
    return v.toString();
  }

  static List<List<String>> _parseXlsx(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    for (final name in excel.tables.keys) {
      final rows = excel.tables[name]!.rows.map((r) => r.map(_cellText).toList()).toList();
      if (rows.isNotEmpty) return rows;
    }
    return [];
  }

  /// Reads dates like 2026-11-04, 2026-11-04 20:47 or 04/11/2026 20:47. With slashes the day is assumed to come
  /// first (as in Bangladesh) unless the second number is above 12.
  static DateTime? _date(String s) {
    final t = s.trim();
    final iso = DateTime.tryParse(t.replaceFirst(' ', 'T'));
    if (iso != null) return iso;
    final m = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})(?:\D+(\d{1,2}):(\d{2}))?').firstMatch(t);
    if (m == null) return null;
    var a = int.parse(m[1]!);
    var b = int.parse(m[2]!);
    var y = int.parse(m[3]!);
    if (y < 100) y += 2000;
    if (b > 12 && a <= 12) {
      final x = a;
      a = b;
      b = x;
    }
    return DateTime(y, b, a, int.tryParse(m[4] ?? '') ?? 12, int.tryParse(m[5] ?? '') ?? 0);
  }

  static int _col(List<String> head, List<String> names) {
    for (final n in names) {
      final i = head.indexWhere((h) => h.trim().toLowerCase() == n);
      if (i >= 0) return i;
    }
    return -1;
  }

  /// Lets the person pick a CSV or XLSX file and adds its transactions.
  /// Understands Jarvis's own export and the usual columns of other money apps
  /// (Period/Date, Accounts, Category, Note, Amount or a currency column, Income/Expense, Description).
  /// Returns (added, skipped), or null if cancelled.
  static Future<(int, int)?> import(Store s) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null || file.bytes == null) return null;
    final rows = file.name.toLowerCase().endsWith('.xlsx')
        ? _parseXlsx(file.bytes!)
        : _parseCsv(utf8.decode(file.bytes!, allowMalformed: true).replaceFirst('﻿', ''));
    if (rows.length < 2) throw const FormatException('The file has no rows.');

    final head = rows.first;
    final cDate = _col(head, ['date', 'period', 'datetime', 'time and date']);
    final cTime = _col(head, ['time']);
    final cType = _col(head, ['type', 'income/expense', 'inc./exp.', 'income/expenses']);
    var cAmount = _col(head, ['amount', 'value', 'sum']);
    if (cAmount < 0) cAmount = head.indexWhere((h) => RegExp(r'^[A-Z]{3}$').hasMatch(h.trim()));
    final cCat = _col(head, ['category']);
    final cSub = _col(head, ['subcategory']);
    final cAcc = _col(head, ['account', 'accounts', 'from account']);
    final cTo = _col(head, ['to account']);
    final cNote = _col(head, ['note', 'notes', 'memo']);
    final cDesc = _col(head, ['description']);
    final cTags = _col(head, ['tags']);
    if (cDate < 0 || cAmount < 0) throw const FormatException('Could not find the Date and Amount columns.');

    String at(List<String> r, int c) => c >= 0 && c < r.length ? r[c].trim() : '';
    final existing = {
      for (final t in s.list('tx')) '${t['ts']}|${t['amount']}|${t['type']}|${t['cat']}',
    };
    final accounts = {for (final a in s.list('accounts')) (a['name'] as String).toLowerCase(): a['name'] as String};
    String account(String name) {
      final n = name.isEmpty ? 'Cash' : name;
      final known = accounts[n.toLowerCase()];
      if (known != null) return known;
      s.list('accounts').add({'id': s.nextId(), 'name': n, 'group': 'Imported', 'initial': 0});
      accounts[n.toLowerCase()] = n;
      return n;
    }

    final undo = <Rec>[];
    var added = 0;
    var skipped = 0;
    for (final r in rows.skip(1)) {
      var when = _date(at(r, cDate));
      final amountText = at(r, cAmount).replaceAll(RegExp(r'[^0-9.\-]'), '');
      final amount = num.tryParse(amountText);
      if (when == null || amount == null || amount == 0) {
        skipped++;
        continue;
      }
      final time = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(at(r, cTime));
      if (time != null) {
        when = DateTime(when.year, when.month, when.day, int.parse(time[1]!), int.parse(time[2]!));
      }
      final rawType = at(r, cType).toLowerCase();
      final type = rawType.startsWith('inc') ? 'income' : (rawType.startsWith('transfer') ? 'transfer' : 'expense');
      if (rawType == 'transfer-in') {
        // Other apps export a transfer as an Out row and an In row; the Out row is enough.
        skipped++;
        continue;
      }
      final cat = [at(r, cCat), at(r, cSub)].where((e) => e.isNotEmpty).join(' / ');
      final category = type == 'transfer' ? 'Transfer' : (cat.isEmpty ? 'Other' : cat);
      final key = '${when.millisecondsSinceEpoch}|${amount.abs()}|$type|$category';
      if (existing.contains(key)) {
        skipped++;
        continue;
      }
      existing.add(key);
      final note = at(r, cNote);
      final desc = at(r, cDesc);
      s.addTx(
        type: type,
        amount: amount.abs(),
        category: category,
        account: account(at(r, cAcc)),
        toAccount: type == 'transfer' && at(r, cTo).isNotEmpty ? account(at(r, cTo)) : null,
        note: note.isEmpty ? null : note,
        desc: desc.isEmpty ? null : desc,
        tags: at(r, cTags).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        ts: when.millisecondsSinceEpoch,
        undo: undo,
      );
      added++;
    }
    if (added > 0) s.logAction('Imported $added transactions from ${file.name}', undo);
    s.save();
    return (added, skipped);
  }
}
