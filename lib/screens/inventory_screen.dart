import 'dart:async';
import 'dart:typed_data';
import 'dart:convert' show base64Decode;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:uuid/uuid.dart';
import '../models/inventory_model.dart';
import '../services/database_service.dart';
import '../services/excel_service.dart';
import '../theme/app_theme.dart';
import '../utils/currency_helper.dart';
import '../utils/js_helper.dart';
import '../utils/responsive.dart';
import '../main.dart' show routeObserver;

// ── Sort options for Inventory ──────────────────────────────────────────
enum _InvSort { nameAZ, nameZA, qtyDesc, qtyAsc, valueDesc, valueAsc, categoryAZ }
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  List<InventoryItem> _items = [];
  List<InventoryItem> _filtered = [];
  final _searchCtrl = TextEditingController();
  late TabController _tabController;
  bool _isExporting = false;
  bool _isImporting = false;
  StreamSubscription<List<InventoryItem>>? _inventorySub;
  _InvSort _sort = _InvSort.nameAZ;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _subscribeToInventory();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  /// Called when this screen is popped back to (e.g., returning from add/edit)
  @override
  void didPopNext() {
    // Refresh data when returning to inventory screen
    DatabaseService.refreshData();
  }

  /// Called when this screen is pushed onto stack (fresh entry)
  @override
  void didPush() {
    DatabaseService.refreshData();
  }

  void _subscribeToInventory() {
    _inventorySub = DatabaseService.inventoryStream.listen((items) {
      if (mounted) {
        setState(() {
          _items = items;
          _applyFilter();
        });
      }
    });
    // Trigger immediate fresh fetch from Firebase (emits back via stream)
    DatabaseService.refreshData();
  }

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase();
    List<InventoryItem> list = q.isEmpty
        ? List.from(_items)
        : _items
            .where((i) =>
                i.itemName.toLowerCase().contains(q) ||
                i.category.toLowerCase().contains(q))
            .toList();
    switch (_sort) {
      case _InvSort.nameAZ:
        list.sort((a, b) => a.itemName.toLowerCase().compareTo(b.itemName.toLowerCase()));
        break;
      case _InvSort.nameZA:
        list.sort((a, b) => b.itemName.toLowerCase().compareTo(a.itemName.toLowerCase()));
        break;
      case _InvSort.qtyDesc:
        list.sort((a, b) => b.quantity.compareTo(a.quantity));
        break;
      case _InvSort.qtyAsc:
        list.sort((a, b) => a.quantity.compareTo(b.quantity));
        break;
      case _InvSort.valueDesc:
        list.sort((a, b) => b.totalValue.compareTo(a.totalValue));
        break;
      case _InvSort.valueAsc:
        list.sort((a, b) => a.totalValue.compareTo(b.totalValue));
        break;
      case _InvSort.categoryAZ:
        list.sort((a, b) => a.category.toLowerCase().compareTo(b.category.toLowerCase()));
        break;
    }
    _filtered = list;
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _inventorySub?.cancel();
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _load() async {
    final items = await DatabaseService.getAllInventoryItemsAsync();
    if (mounted) {
      setState(() {
        _items = items;
        _applyFilter();
      });
    }
  }

  void _search(String query) {
    setState(() => _applyFilter());
  }

  void _changeSort(_InvSort sort) {
    setState(() {
      _sort = sort;
      _applyFilter();
    });
  }

  void _showAddDialog([InventoryItem? existing]) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InventoryDialog(
        existing: existing,
        onSave: (item) async {
          if (existing != null) {
            await DatabaseService.updateInventoryItem(existing.id, item);
          } else {
            await DatabaseService.addInventoryItem(item);
          }
          // Stream will auto-update; fallback load for offline mode
          DatabaseService.refreshData();
        },
      ),
    );
  }

  void _confirmDelete(InventoryItem item) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Item'),
        content: const Text('Delete this inventory item?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await DatabaseService.deleteInventoryItem(item.id);
              DatabaseService.refreshData();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ── EXPORT TO EXCEL (.xlsx) ──────────────────────────────────────────────
  Future<void> _exportToExcel() async {
    if (_items.isEmpty) {
      _showSnack('لا توجد مواد للتصدير', isError: true);
      return;
    }
    setState(() => _isExporting = true);
    try {
      final bytes = ExcelService.exportInventoryToExcel(_items);
      final b64 = ExcelService.bytesToBase64(bytes);
      final filename =
          'inventory_${DateTime.now().toString().substring(0, 10)}.xlsx';

      if (kIsWeb) {
        _downloadExcelWeb(b64, filename);
      }
      _showSnack('✅ تم تصدير ${_items.length} مادة إلى $filename');
    } catch (e) {
      _showSnack('فشل التصدير: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _downloadExcelWeb(String b64, String filename) {
    evalJs('''
      (function(){
        try {
          var bin = atob("$b64");
          var bytes = new Uint8Array(bin.length);
          for(var i=0;i<bin.length;i++) bytes[i]=bin.charCodeAt(i);
          var blob = new Blob([bytes],{type:"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"});
          var a = document.createElement("a");
          a.href = URL.createObjectURL(blob);
          a.download = "$filename";
          document.body.appendChild(a);
          a.click();
          setTimeout(function(){ document.body.removeChild(a); URL.revokeObjectURL(a.href); }, 100);
        } catch(err) { console.error('Download error:', err); }
      })();
    ''');
  }

  // ── IMPORT FROM EXCEL (.xlsx) ────────────────────────────────────────────
  Future<void> _importFromExcel() async {
    setState(() => _isImporting = true);
    try {
      if (kIsWeb) {
        _pickXlsxFileWeb();
      }
    } catch (e) {
      setState(() => _isImporting = false);
      _showSnack('فشل الاستيراد: $e', isError: true);
    }
  }

  void _pickXlsxFileWeb() {
    // فتح نافذة اختيار الملف (.xlsx أو .xls)
    evalJs('''
      (function(){
        var input = document.createElement("input");
        input.type = "file";
        input.accept = ".xlsx,.xls,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
        input.style.display = "none";
        document.body.appendChild(input);
        input.onchange = function(e){
          var file = e.target.files[0];
          if(!file){ document.body.removeChild(input); return; }
          var reader = new FileReader();
          reader.onload = function(evt){
            var arr = new Uint8Array(evt.target.result);
            var chars = [];
            for(var i=0;i<arr.length;i++) chars.push(String.fromCharCode(arr[i]));
            window._xlsxImportData = btoa(chars.join(""));
            window._xlsxImportReady = true;
          };
          reader.readAsArrayBuffer(file);
          document.body.removeChild(input);
        };
        input.click();
      })();
    ''');
    _pollForXlsxData();
  }

  void _pollForXlsxData() {
    Future.delayed(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      final ready = evalJsBool('window._xlsxImportReady === true');
      if (ready) {
        final b64 = evalJsString('window._xlsxImportData || ""');
        evalJs('window._xlsxImportReady = false; window._xlsxImportData = "";');
        if (b64.isNotEmpty) {
          await _processXlsxData(b64);
        } else {
          if (mounted) setState(() => _isImporting = false);
        }
      } else {
        _pollForXlsxData();
      }
    });
  }

  Future<void> _processXlsxData(String b64) async {
    try {
      // فك تشفير Base64 إلى Uint8List
      final decoded = _base64Decode(b64);
      final result = ExcelService.importInventoryFromExcel(decoded);

      if (result.items.isEmpty) {
        _showSnack(
          result.hasErrors
              ? 'فشل الاستيراد: ${result.errors.first}'
              : 'الملف فارغ أو لا يحتوي بيانات',
          isError: true,
        );
        return;
      }

      // حفظ المواد في قاعدة البيانات
      int imported = 0;
      final saveErrors = <String>[];
      for (final item in result.items) {
        try {
          await DatabaseService.addInventoryItem(item);
          imported++;
        } catch (e) {
          saveErrors.add('${item.itemName}: $e');
        }
      }

      DatabaseService.refreshData();

      if (mounted) {
        final allErrors = [...result.errors, ...saveErrors];
        _showSnack(
          allErrors.isEmpty
              ? '✅ تم استيراد $imported مادة بنجاح'
              : '✅ استيراد $imported مادة (${allErrors.length} تحذير)',
          isError: allErrors.isNotEmpty,
        );
        if (allErrors.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 400));
          if (mounted) _showImportErrors(allErrors);
        }
      }
    } catch (e) {
      _showSnack('خطأ في معالجة الملف: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  /// فك تشفير Base64 يدوياً
  static Uint8List _base64Decode(String b64) {
    return base64Decode(b64);
  }

  void _showImportErrors(List<String> errors) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.warningColor),
            SizedBox(width: 8),
            Text('تحذيرات الاستيراد'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: ListView(
            shrinkWrap: true,
            children: errors
                .map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text('• $e',
                          style: const TextStyle(fontSize: 12)),
                    ))
                .toList(),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.inventoryColor),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  // ── SHOW TEMPLATE DIALOG ──────────────────────────────────────────────────
  void _showImportHelp() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.help_outline_rounded, color: AppTheme.inventoryColor),
            SizedBox(width: 8),
            Text('دليل الاستيراد'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('تنسيق ملف Excel (.xlsx):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              SizedBox(height: 8),
              Text(
                'الصف الأول: عنوان التقرير (تلقائي)\nالصف الثاني: رؤوس الأعمدة\nالصف الثالث فصاعداً: البيانات',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 10),
              _ColRow(num: '1', name: 'اسم المادة', required: true),
              _ColRow(num: '2', name: 'الفئة', required: false),
              _ColRow(num: '3', name: 'الكمية', required: true),
              _ColRow(num: '4', name: 'الوحدة (قطعة/كغ/...)', required: false),
              _ColRow(num: '5', name: 'سعر الوحدة (IQD)', required: true),
              _ColRow(num: '6', name: 'الحد الأدنى للمخزون', required: false),
              _ColRow(num: '7', name: 'القيمة الإجمالية', required: false),
              _ColRow(num: '8', name: 'الوصف', required: false),
              SizedBox(height: 14),
              Text('💡 نصيحة: صدّر الملف أولاً للحصول على التنسيق الصحيح،\nثم عدّله وأعد استيراده.',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textGrey,
                      fontStyle: FontStyle.italic)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق')),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _exportToExcel();
            },
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('تصدير قالب'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.inventoryColor),
          ),
        ],
      ),
    );
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────
  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? AppTheme.errorColor : AppTheme.salesColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalValue = _items.fold<double>(0, (s, i) => s + i.totalValue);
    final lowStock = _items.where((i) => i.isLowStock).toList();
    final r = R.of(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.inventoryColor,
        title: const Text('Storage'),
        actions: [
          // ── Import Button ─────────────────────────────────────────────
          _isImporting
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.upload_file_rounded),
                  tooltip: 'استيراد من Excel',
                  onPressed: () => _showImportMenu(),
                ),
          // ── Export Button ─────────────────────────────────────────────
          _isExporting
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.download_rounded),
                  tooltip: 'تصدير إلى Excel',
                  onPressed: _exportToExcel,
                ),
          IconButton(
              icon: const Icon(Icons.refresh_rounded), onPressed: () => DatabaseService.refreshData()),
          // ── Sort button ──────────────────────────────────────────────────
          PopupMenuButton<_InvSort>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort',
            initialValue: _sort,
            onSelected: _changeSort,
            itemBuilder: (_) => [
              _invSortItem(_InvSort.nameAZ,     Icons.sort_by_alpha_rounded,  'Name: A → Z',           _sort),
              _invSortItem(_InvSort.nameZA,     Icons.sort_by_alpha_rounded,  'Name: Z → A',           _sort),
              _invSortItem(_InvSort.qtyDesc,    Icons.arrow_downward_rounded, 'Quantity: High → Low',  _sort),
              _invSortItem(_InvSort.qtyAsc,     Icons.arrow_upward_rounded,   'Quantity: Low → High',  _sort),
              _invSortItem(_InvSort.valueDesc,  Icons.trending_down_rounded,  'Value: High → Low',     _sort),
              _invSortItem(_InvSort.valueAsc,   Icons.trending_up_rounded,    'Value: Low → High',     _sort),
              _invSortItem(_InvSort.categoryAZ, Icons.category_rounded,       'Category: A → Z',       _sort),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            const Tab(text: 'All Items', icon: Icon(Icons.list_rounded)),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 16),
                  const SizedBox(width: 4),
                  Text('Low Stock (${lowStock.length})'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Stats Banner
          Container(
            color: AppTheme.inventoryColor,
            padding: EdgeInsets.fromLTRB(r.hPad, 0, r.hPad, 16),
            child: Row(
              children: [
                _StatBox(
                    label: 'Total Items',
                    value: '${_items.length}',
                    icon: Icons.category_rounded),
                SizedBox(width: r.gap),
                _StatBox(
                    label: 'Stock Value',
                    value: CurrencyHelper.format(totalValue),
                    icon: Icons.account_balance_wallet_rounded),
              ],
            ),
          ),
          // Search
          Padding(
            padding: EdgeInsets.all(r.hPad),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _search,
              style: TextStyle(fontSize: r.fs15),
              decoration: InputDecoration(
                hintText: 'Search items or categories...',
                hintStyle: TextStyle(fontSize: r.fs14),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppTheme.inventoryColor),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          _search('');
                        })
                    : null,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _filtered.isEmpty
                    ? _EmptyState(
                        icon: Icons.inventory_2_rounded,
                        message: 'No inventory items found',
                        onAdd: () => _showAddDialog(),
                      )
                    : _InventoryTable(
                        items: _filtered,
                        onEdit: _showAddDialog,
                        onDelete: _confirmDelete,
                      ),
                lowStock.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_rounded,
                                size: 64, color: AppTheme.salesColor),
                            SizedBox(height: 16),
                            Text('All items are well stocked!',
                                style: TextStyle(
                                    color: AppTheme.salesColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      )
                    : _InventoryTable(
                        items: lowStock,
                        onEdit: _showAddDialog,
                        onDelete: _confirmDelete,
                        highlightLowStock: true,
                      ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(),
        backgroundColor: AppTheme.inventoryColor,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Item'),
      ),
    );
  }

  void _showImportMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            const Text('استيراد المخزون',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('اختر ملف Excel (.xlsx) مُصدَّر من التطبيق',
                style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
            const SizedBox(height: 24),
            // Import button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('اختر ملف Excel (.xlsx)',
                    style: TextStyle(fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.inventoryColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _importFromExcel();
                },
              ),
            ),
            const SizedBox(height: 12),
            // Help button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.help_outline_rounded,
                    color: AppTheme.inventoryColor),
                label: const Text('عرض دليل التنسيق',
                    style: TextStyle(color: AppTheme.inventoryColor)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppTheme.inventoryColor),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _showImportHelp();
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Column Row for import guide ───────────────────────────────────────────────
class _ColRow extends StatelessWidget {
  final String num;
  final String name;
  final bool required;
  const _ColRow(
      {required this.num, required this.name, required this.required});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.inventoryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(num,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.inventoryColor)),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Text(name,
                  style: const TextStyle(fontSize: 13))),
          if (required)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Required',
                  style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.errorColor,
                      fontWeight: FontWeight.w600)),
            )
          else
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.textGrey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Optional',
                  style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.textGrey)),
            ),
        ],
      ),
    );
  }
}

// ── Inventory Table (header + rows) ──────────────────────────────────────────
class _InventoryTable extends StatelessWidget {
  final List<InventoryItem> items;
  final void Function(InventoryItem) onEdit;
  final void Function(InventoryItem) onDelete;
  final bool highlightLowStock;

  const _InventoryTable({
    required this.items,
    required this.onEdit,
    required this.onDelete,
    this.highlightLowStock = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = R.of(context);
    return Column(
      children: [
        // ── Sticky Table Header ──────────────────────────────────────────
        Container(
          margin: EdgeInsets.fromLTRB(r.hPad, 0, r.hPad, 0),
          padding: EdgeInsets.symmetric(
              horizontal: r.gapS + 4, vertical: r.isMobile ? 9 : 11),
          decoration: BoxDecoration(
            color: AppTheme.inventoryColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              // Item name column (flexible)
              Expanded(
                flex: 5,
                child: Text('Item',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: r.fs13)),
              ),
              // Qty column
              SizedBox(
                width: r.isMobile ? 46 : 58,
                child: Text('Qty',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: r.fs13)),
              ),
              // Unit price column (hidden on very small mobile)
              if (!r.isMobile)
                SizedBox(
                  width: 100,
                  child: Text('Unit Price',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: r.fs13)),
                ),
              // Total column
              SizedBox(
                width: r.isMobile ? 82 : 100,
                child: Text('Total',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: r.fs13)),
              ),
              // Actions column
              SizedBox(
                width: r.isMobile ? 56 : 64,
                child: Text('',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: r.fs13)),
              ),
            ],
          ),
        ),
        // ── Table Rows ───────────────────────────────────────────────────
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(r.hPad, 6, r.hPad, 80),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final item = items[i];
              final isEven = i % 2 == 0;
              final stockColor =
                  item.isLowStock ? AppTheme.warningColor : AppTheme.salesColor;
              return Container(
                margin: const EdgeInsets.only(bottom: 1),
                decoration: BoxDecoration(
                  color: item.isLowStock
                      ? AppTheme.warningColor.withValues(alpha: 0.05)
                      : isEven
                          ? Colors.white
                          : AppTheme.background,
                  borderRadius: BorderRadius.circular(8),
                  border: item.isLowStock
                      ? Border.all(
                          color: AppTheme.warningColor.withValues(alpha: 0.3),
                          width: 1)
                      : null,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: r.gapS + 4,
                      vertical: r.isMobile ? 10 : 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ── Item Name + Category ─────────────────────────
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.itemName,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: r.fs14,
                                        color: AppTheme.textDark),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (item.isLowStock)
                                  Container(
                                    margin: const EdgeInsets.only(left: 4),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppTheme.warningColor
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text('Low',
                                        style: TextStyle(
                                            color: AppTheme.warningColor,
                                            fontSize: r.fs11,
                                            fontWeight: FontWeight.bold)),
                                  ),
                              ],
                            ),
                            if (item.category.isNotEmpty)
                              Text(
                                item.category,
                                style: TextStyle(
                                    color: AppTheme.textGrey,
                                    fontSize: r.fs12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      // ── Quantity ─────────────────────────────────────
                      SizedBox(
                        width: r.isMobile ? 46 : 58,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              item.quantity % 1 == 0
                                  ? item.quantity.toInt().toString()
                                  : item.quantity.toStringAsFixed(1),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: r.fs14,
                                  color: stockColor),
                            ),
                            Text(
                              item.unit,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: r.fs11,
                                  color: AppTheme.textGrey),
                            ),
                          ],
                        ),
                      ),
                      // ── Unit Price (desktop/tablet only) ─────────────
                      if (!r.isMobile)
                        SizedBox(
                          width: 100,
                          child: Text(
                            CurrencyHelper.format(item.unitPrice),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: r.fs13,
                                color: AppTheme.textGrey),
                          ),
                        ),
                      // ── Total Value ───────────────────────────────────
                      SizedBox(
                        width: r.isMobile ? 82 : 100,
                        child: Text(
                          CurrencyHelper.format(item.totalValue),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: r.fs13,
                              color: AppTheme.inventoryColor),
                        ),
                      ),
                      // ── Actions ───────────────────────────────────────
                      SizedBox(
                        width: r.isMobile ? 56 : 64,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            GestureDetector(
                              onTap: () => onEdit(item),
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryBlue
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(Icons.edit_outlined,
                                    color: AppTheme.primaryBlue,
                                    size: r.iconSm + 2),
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => onDelete(item),
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: AppTheme.errorColor
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(Icons.delete_outline_rounded,
                                    color: AppTheme.errorColor,
                                    size: r.iconSm + 2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Sort Menu Item Helper (Inventory) ─────────────────────────────────────────
PopupMenuItem<_InvSort> _invSortItem(_InvSort value, IconData icon, String label, _InvSort current) {
  final bool selected = value == current;
  return PopupMenuItem<_InvSort>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 18,
            color: selected ? AppTheme.inventoryColor : AppTheme.textGrey),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? AppTheme.inventoryColor : AppTheme.textDark,
            )),
        if (selected) ...[
          const Spacer(),
          Icon(Icons.check_rounded, size: 16, color: AppTheme.inventoryColor),
        ],
      ],
    ),
  );
}

// ── Inventory Dialog ──────────────────────────────────────────────────────────
class _InventoryDialog extends StatefulWidget {
  final InventoryItem? existing;
  final Function(InventoryItem) onSave;
  const _InventoryDialog({this.existing, required this.onSave});

  @override
  State<_InventoryDialog> createState() => _InventoryDialogState();
}

class _InventoryDialogState extends State<_InventoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _categoryCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _minStockCtrl;
  late TextEditingController _unitCtrl;
  late TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.itemName ?? '');
    _categoryCtrl = TextEditingController(text: e?.category ?? '');
    _qtyCtrl = TextEditingController(text: e?.quantity.toString() ?? '');
    _priceCtrl = TextEditingController(text: e?.unitPrice.toString() ?? '');
    _minStockCtrl =
        TextEditingController(text: e?.minStock.toString() ?? '5');
    _unitCtrl = TextEditingController(text: e?.unit ?? 'pcs');
    _descCtrl = TextEditingController(text: e?.description ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _minStockCtrl.dispose();
    _unitCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final mq      = MediaQuery.of(context);
    final dialogW = mq.size.width  * 0.96;
    final dialogH = mq.size.height * 0.94;
    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: EdgeInsets.zero,
      child: SizedBox(
        width:  dialogW,
        height: dialogH,
        child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.inventoryColor
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                          isEdit
                              ? Icons.edit_rounded
                              : Icons.add_box_rounded,
                          color: AppTheme.inventoryColor),
                    ),
                    const SizedBox(width: 12),
                    Text(isEdit ? 'تعديل مادة' : 'مادة جديدة',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 20),
                _buildField(_nameCtrl, 'اسم المادة',
                    Icons.inventory_2_outlined,
                    required: true),
                const SizedBox(height: 12),
                _buildField(
                    _categoryCtrl, 'التصنيف', Icons.category_outlined,
                    required: true),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: _buildField(
                            _qtyCtrl, 'الكمية', Icons.numbers_rounded,
                            isNumber: true, required: true)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _buildField(
                            _unitCtrl, 'الوحدة', Icons.straighten_rounded,
                            required: true)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: _buildField(_priceCtrl, 'سعر الوحدة',
                            Icons.attach_money_rounded,
                            isNumber: true, required: true)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _buildField(_minStockCtrl, 'الحد الأدنى للمخزون',
                            Icons.warning_amber_outlined,
                            isNumber: true, required: true)),
                  ],
                ),
                const SizedBox(height: 12),
                _buildField(_descCtrl,
                    'الوصف (اختياري)', Icons.description_outlined),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                        child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('إلغاء',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.inventoryColor),
                        onPressed: () {
                          if (!_formKey.currentState!.validate()) return;
                          widget.onSave(InventoryItem(
                            id: widget.existing?.id ??
                                const Uuid().v4(),
                            itemName: _nameCtrl.text.trim(),
                            category: _categoryCtrl.text.trim(),
                            quantity:
                                double.tryParse(_qtyCtrl.text) ?? 0,
                            unitPrice:
                                double.tryParse(_priceCtrl.text) ?? 0,
                            minStock:
                                double.tryParse(_minStockCtrl.text) ?? 5,
                            unit: _unitCtrl.text.trim(),
                            description: _descCtrl.text.trim(),
                            lastUpdated: DateTime.now(),
                          ));
                          Navigator.pop(context);
                        },
                        child: Text(
                            isEdit ? 'حفظ التعديل' : 'حفظ المادة',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool required = false,
    bool isNumber = false,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        prefixIcon: Icon(icon, color: AppTheme.inventoryColor, size: 22),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDDE1EA))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.inventoryColor, width: 2)),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      ),
      validator: required
          ? (v) =>
              (v == null || v.isEmpty) ? '$label is required' : null
          : null,
    );
  }
}

// ── Stat Box ──────────────────────────────────────────────────────────────────
class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _StatBox(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                  Text(label,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback onAdd;
  const _EmptyState(
      {required this.icon,
      required this.message,
      required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: AppTheme.textGrey),
          const SizedBox(height: 16),
          Text(message,
              style: const TextStyle(
                  color: AppTheme.textGrey, fontSize: 12)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add First Item'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.inventoryColor),
          ),
        ],
      ),
    );
  }
}
