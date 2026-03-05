import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/inventory_model.dart';

/// خدمة التصدير والاستيراد من/إلى Excel
class ExcelService {
  static const List<String> _headers = [
    'اسم المادة',
    'الفئة',
    'الكمية',
    'الوحدة',
    'سعر الوحدة (IQD)',
    'الحد الأدنى',
    'القيمة الإجمالية (IQD)',
    'الوصف',
    'آخر تحديث',
  ];

  // ─── تصدير ───────────────────────────────────────────────────────────────

  static Uint8List exportInventoryToExcel(List<InventoryItem> items) {
    final excel = Excel.createExcel();
    const sheetName = 'المخزون';
    final sheet = excel[sheetName];
    excel.delete('Sheet1');

    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    final now = DateFormat('yyyy/MM/dd – HH:mm').format(DateTime.now());

    // صف العنوان
    _set(sheet, 0, 0, 'تقرير المخزون – Vinex Technology');
    _set(sheet, 0, 1, 'عدد المواد: ${items.length}');
    _set(sheet, 0, 5, 'تاريخ التصدير: $now');

    // صف الرؤوس
    for (int c = 0; c < _headers.length; c++) {
      _set(sheet, 1, c, _headers[c]);
    }

    // البيانات
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final r = i + 2;
      _set(sheet, r, 0, item.itemName);
      _set(sheet, r, 1, item.category);
      _set(sheet, r, 2, item.quantity);
      _set(sheet, r, 3, item.unit);
      _set(sheet, r, 4, item.unitPrice);
      _set(sheet, r, 5, item.minStock);
      _set(sheet, r, 6, item.totalValue);
      _set(sheet, r, 7, item.description);
      _set(sheet, r, 8, dateFormat.format(item.lastUpdated));
    }

    // صف الإجمالي
    final sumRow = items.length + 2;
    final totalValue = items.fold<double>(0, (s, i) => s + i.totalValue);
    final totalQty = items.fold<double>(0, (s, i) => s + i.quantity);
    final lowCount = items.where((i) => i.isLowStock).length;
    _set(sheet, sumRow, 0, '── الإجمالي ──');
    _set(sheet, sumRow, 2, totalQty);
    _set(sheet, sumRow, 6, totalValue);
    _set(sheet, sumRow, 7, 'مواد منخفضة: $lowCount');

    // عرض الأعمدة
    final widths = [22.0, 15.0, 10.0, 10.0, 20.0, 15.0, 22.0, 25.0, 20.0];
    for (int c = 0; c < widths.length; c++) {
      sheet.setColumnWidth(c, widths[c]);
    }

    final encoded = excel.encode();
    if (encoded == null) throw Exception('فشل إنشاء ملف Excel');
    return Uint8List.fromList(encoded);
  }

  static void _set(Sheet sheet, int row, int col, dynamic value) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    if (value is double) {
      cell.value = DoubleCellValue(value);
    } else if (value is int) {
      cell.value = IntCellValue(value);
    } else {
      cell.value = TextCellValue(value.toString());
    }
  }

  // ─── استيراد ─────────────────────────────────────────────────────────────

  static ExcelImportResult importInventoryFromExcel(Uint8List fileBytes) {
    final errors = <String>[];
    final items = <InventoryItem>[];

    try {
      final excel = Excel.decodeBytes(fileBytes);
      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];
      if (sheet == null) {
        return ExcelImportResult(items: [], errors: ['لا توجد ورقة عمل']);
      }

      final rows = sheet.rows;
      if (rows.length < 3) {
        return ExcelImportResult(items: [], errors: ['الملف فارغ أو لا يحتوي بيانات']);
      }

      // البيانات تبدأ من الصف الثالث (index 2)
      for (int ri = 2; ri < rows.length; ri++) {
        final row = rows[ri];
        final name = _str(row, 0).trim();
        if (name.isEmpty || name.startsWith('──')) continue;

        try {
          items.add(_parseRow(row, ri + 1));
        } catch (e) {
          errors.add('صف ${ri + 1}: $e');
        }
      }
    } catch (e) {
      return ExcelImportResult(items: [], errors: ['خطأ في قراءة الملف: $e']);
    }

    return ExcelImportResult(items: items, errors: errors);
  }

  static InventoryItem _parseRow(List<Data?> row, int displayRow) {
    final name = _str(row, 0).trim();
    if (name.isEmpty) throw 'اسم المادة فارغ';

    return InventoryItem(
      id: 'IMP-${DateTime.now().millisecondsSinceEpoch}',
      itemName: name,
      category: _str(row, 1).trim().isEmpty ? 'عام' : _str(row, 1).trim(),
      quantity: _dbl(row, 2, displayRow, 'الكمية'),
      unit: _str(row, 3).trim().isEmpty ? 'قطعة' : _str(row, 3).trim(),
      unitPrice: _dbl(row, 4, displayRow, 'سعر الوحدة'),
      minStock: _dbl(row, 5, displayRow, 'الحد الأدنى', def: 0),
      description: _str(row, 7).trim(),
      lastUpdated: DateTime.now(),
    );
  }

  static String _str(List<Data?> row, int col) {
    if (col >= row.length || row[col] == null) return '';
    return row[col]!.value?.toString() ?? '';
  }

  static double _dbl(
    List<Data?> row,
    int col,
    int displayRow,
    String field, {
    double? def,
  }) {
    final s = _str(row, col).trim().replaceAll(',', '');
    if (s.isEmpty) return def ?? (throw '$field مفقود في الصف $displayRow');
    return double.tryParse(s) ?? (def ?? (throw '$field غير صالح ($s) في الصف $displayRow'));
  }

  // ─── تحميل على الويب ──────────────────────────────────────────────────────

  /// يُعيد base64 للملف لاستخدامه في رابط تحميل داخل JavaScript
  static String bytesToBase64(Uint8List bytes) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final result = StringBuffer();
    for (int i = 0; i < bytes.length; i += 3) {
      final b0 = bytes[i];
      final b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
      final b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
      result.write(chars[(b0 >> 2) & 0x3F]);
      result.write(chars[((b0 << 4) | (b1 >> 4)) & 0x3F]);
      result.write(i + 1 < bytes.length ? chars[((b1 << 2) | (b2 >> 6)) & 0x3F] : '=');
      result.write(i + 2 < bytes.length ? chars[b2 & 0x3F] : '=');
    }
    return result.toString();
  }
}

// ─── نتيجة الاستيراد ──────────────────────────────────────────────────────────

class ExcelImportResult {
  final List<InventoryItem> items;
  final List<String> errors;

  const ExcelImportResult({required this.items, required this.errors});

  bool get hasErrors => errors.isNotEmpty;
  int get successCount => items.length;
}
