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

  // ignore: unused_element
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
    _showTabularDialog(existingItem: existing);
  }

  void _showTabularDialog({InventoryItem? existingItem}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _TabularInventoryScreen(
          existingItem: existingItem,
          onSave: (item) async {
            if (existingItem != null) {
              await DatabaseService.updateInventoryItem(existingItem.id, item);
            } else {
              await DatabaseService.addInventoryItem(item);
            }
            DatabaseService.refreshData();
          },
          onSaveBatch: existingItem == null
              ? (items) async {
                  for (final item in items) {
                    await DatabaseService.addInventoryItem(item);
                  }
                  DatabaseService.refreshData();
                }
              : null,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _confirmDelete(InventoryItem item) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeleteInventoryDialog(
          item: item,
          onConfirmed: () async {
            await DatabaseService.deleteInventoryItem(item.id);
            DatabaseService.refreshData();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ تم حذف "${item.itemName}" من المخزن'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          },
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
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ImportErrorsScreen(errors: errors),
      ),
    );
  }

  // ── SHOW IMPORT HELP ──────────────────────────────────────────────────────
  void _showImportHelp() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ImportHelpScreen(
          onExport: () {
            Navigator.pop(context);
            _exportToExcel();
          },
        ),
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
        onPressed: () => _openTabularAdd(),
        backgroundColor: AppTheme.inventoryColor,
        icon: const Icon(Icons.table_rows_rounded),
        label: const Text('إضافة مواد'),
      ),
    );
  }

  void _openTabularAdd() {
    _showTabularDialog();
  }

  void _showImportMenu() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ImportMenuScreen(
          onImport: () {
            Navigator.pop(context);
            _importFromExcel();
          },
          onHelp: () {
            Navigator.pop(context);
            _showImportHelp();
          },
        ),
      ),
    );
  }
}

// ── شاشة تأكيد حذف عنصر المخزن الأصيلة ──────────────────────────────────────
class _DeleteInventoryDialog extends StatelessWidget {
  final InventoryItem item;
  final Future<void> Function() onConfirmed;
  const _DeleteInventoryDialog({required this.item, required this.onConfirmed});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: EdgeInsets.zero,
      title: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          color: AppTheme.errorColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('حذف الصنف', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
          ],
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'حذف "${item.itemName}" من المخزن؟',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _InventoryInfoTile(icon: Icons.category_outlined, label: 'الفئة', value: item.category.isEmpty ? '—' : item.category),
          _InventoryInfoTile(icon: Icons.numbers_rounded, label: 'الكمية', value: '${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity.toStringAsFixed(2)} ${item.unit}'),
          _InventoryInfoTile(icon: Icons.attach_money_rounded, label: 'سعر الوحدة', value: CurrencyHelper.format(item.unitPrice)),
          const SizedBox(height: 8),
          const Text('لا يمكن التراجع عن هذا الإجراء.', style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
          const SizedBox(height: 8),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('لا، تراجع', style: TextStyle(fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  foregroundColor: AppTheme.textGrey,
                  side: const BorderSide(color: AppTheme.textGrey),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await onConfirmed();
                },
                icon: const Icon(Icons.delete_forever_rounded, size: 18),
                label: const Text('نعم، احذف', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: AppTheme.errorColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InventoryInfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InventoryInfoTile({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textGrey),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: AppTheme.textGrey, fontSize: 13)),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }
}

// ── شاشة قائمة الاستيراد الأصيلة ─────────────────────────────────────────────
class _ImportMenuScreen extends StatelessWidget {
  final VoidCallback onImport;
  final VoidCallback onHelp;
  const _ImportMenuScreen({required this.onImport, required this.onHelp});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.inventoryColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          children: [
            Icon(Icons.upload_file_rounded, size: 20),
            SizedBox(width: 8),
            Text('استيراد المخزون', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('اختر ملف Excel (.xlsx) مُصدَّر من التطبيق',
                style: TextStyle(color: AppTheme.textGrey, fontSize: 14)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('اختر ملف Excel (.xlsx)', style: TextStyle(fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.inventoryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: onImport,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.help_outline_rounded, color: AppTheme.inventoryColor),
                label: const Text('عرض دليل التنسيق', style: TextStyle(color: AppTheme.inventoryColor)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: AppTheme.inventoryColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: onHelp,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── شاشة أخطاء الاستيراد الأصيلة ─────────────────────────────────────────────
class _ImportErrorsScreen extends StatelessWidget {
  final List<String> errors;
  const _ImportErrorsScreen({required this.errors});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.warningColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 20),
            SizedBox(width: 8),
            Text('تحذيرات الاستيراد', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: errors.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.warningColor.withValues(alpha: 0.3)),
            ),
            child: Text('• ${errors[i]}', style: const TextStyle(fontSize: 13)),
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.inventoryColor,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('حسناً', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      ),
    );
  }
}

// ── شاشة دليل الاستيراد الأصيلة ──────────────────────────────────────────────
class _ImportHelpScreen extends StatelessWidget {
  final VoidCallback onExport;
  const _ImportHelpScreen({required this.onExport});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.inventoryColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          children: [
            Icon(Icons.help_outline_rounded, size: 20),
            SizedBox(width: 8),
            Text('دليل الاستيراد', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('تنسيق ملف Excel (.xlsx):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            const Text(
              'الصف الأول: عنوان التقرير (تلقائي)\nالصف الثاني: رؤوس الأعمدة\nالصف الثالث فصاعداً: البيانات',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            const _ColRow(num: '1', name: 'اسم المادة', required: true),
            const _ColRow(num: '2', name: 'الفئة', required: false),
            const _ColRow(num: '3', name: 'الكمية', required: true),
            const _ColRow(num: '4', name: 'الوحدة (قطعة/كغ/...)', required: false),
            const _ColRow(num: '5', name: 'سعر الوحدة (IQD)', required: true),
            const _ColRow(num: '6', name: 'الحد الأدنى للمخزون', required: false),
            const _ColRow(num: '7', name: 'القيمة الإجمالية', required: false),
            const _ColRow(num: '8', name: 'الوصف', required: false),
            const SizedBox(height: 20),
            const Text(
              '💡 نصيحة: صدّر الملف أولاً للحصول على التنسيق الصحيح، ثم عدّله وأعد استيراده.',
              style: TextStyle(fontSize: 13, color: AppTheme.textGrey, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton.icon(
          onPressed: onExport,
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('تصدير قالب', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.inventoryColor,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
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

// ── Tabular Inventory Screen (Add/Edit) ──────────────────────────────────────
/// يمثّل صف واحد من البيانات أثناء التحرير
class _RowData {
  final TextEditingController name;      // اسم المادة
  final TextEditingController supplier;  // اسم المجهّز (يُحفظ في category)
  final TextEditingController unit;      // الوحدة
  final TextEditingController price;     // سعر المفرد
  final TextEditingController notes;     // الملاحظات
  final TextEditingController qty;       // الكمية (مخفية عند الإضافة، ظاهرة عند التعديل)
  final TextEditingController minStock;
  final String id;
  final bool isEdit;                     // هل هذا تعديل لمادة موجودة؟

  _RowData({
    String? existingId,
    String nameVal     = '',
    String supplierVal = '',
    String unitVal     = 'pcs',
    String priceVal    = '',
    String notesVal    = '',
    String qtyVal      = '0',
    String minStockVal = '5',
    this.isEdit        = false,
  })  : id       = existingId ?? const Uuid().v4(),
        name     = TextEditingController(text: nameVal),
        supplier = TextEditingController(text: supplierVal),
        unit     = TextEditingController(text: unitVal),
        price    = TextEditingController(text: priceVal),
        notes    = TextEditingController(text: notesVal),
        qty      = TextEditingController(text: qtyVal),
        minStock = TextEditingController(text: minStockVal);

  void dispose() {
    name.dispose();
    supplier.dispose();
    unit.dispose();
    price.dispose();
    notes.dispose();
    qty.dispose();
    minStock.dispose();
  }

  bool get isEmpty =>
      name.text.trim().isEmpty && price.text.trim().isEmpty;

  InventoryItem toItem() => InventoryItem(
        id:          id,
        itemName:    name.text.trim(),
        category:    supplier.text.trim(),
        // الكمية مخفية في شاشة إضافة المواد:
        // — إضافة جديدة: دائماً 0
        // — تعديل: تحافظ على القيمة الحالية المحفوظة (لا تُعدَّل من هنا)
        quantity:    isEdit
            ? (double.tryParse(qty.text.trim()) ?? 0)
            : 0,
        unitPrice:   double.tryParse(price.text.trim()) ?? 0,
        minStock:    double.tryParse(minStock.text.trim()) ?? 5,
        unit:        unit.text.trim().isEmpty ? 'pcs' : unit.text.trim(),
        description: notes.text.trim(),
        lastUpdated: DateTime.now(),
      );
}

class _TabularInventoryScreen extends StatefulWidget {
  final InventoryItem? existingItem;
  final Future<void> Function(InventoryItem) onSave;
  final Future<void> Function(List<InventoryItem>)? onSaveBatch;
  final VoidCallback onClose;

  const _TabularInventoryScreen({
    required this.existingItem,
    required this.onSave,
    required this.onClose,
    this.onSaveBatch,
  });

  @override
  State<_TabularInventoryScreen> createState() =>
      _TabularInventoryScreenState();
}

class _TabularInventoryScreenState extends State<_TabularInventoryScreen> {
  final List<_RowData> _rows = [];
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  final ScrollController _vScroll = ScrollController();

  // ارتفاع ثابت للأعمدة (محتفظ للاستخدام المستقبلي)
  // ignore: unused_field
  static const double _colName   = 180;
  // ignore: unused_field
  static const double _colCat    = 130;
  // ignore: unused_field
  static const double _colQty    = 80;
  // ignore: unused_field
  static const double _colUnit   = 80;
  // ignore: unused_field
  static const double _colPrice  = 110;
  // ignore: unused_field
  static const double _colMin    = 90;
  // ignore: unused_field
  static const double _colDesc   = 160;
  // ignore: unused_field
  static const double _colAct    = 48;
  // ignore: unused_field
  static const double _rowHeight = 52;

  @override
  void initState() {
    super.initState();
    if (widget.existingItem != null) {
      final e = widget.existingItem!;
      _rows.add(_RowData(
        existingId:   e.id,
        nameVal:      e.itemName,
        supplierVal:  e.category,
        unitVal:      e.unit,
        priceVal:     e.unitPrice % 1 == 0
            ? e.unitPrice.toInt().toString()
            : e.unitPrice.toString(),
        notesVal:     e.description,
        // الكمية الحالية تظهر عند التعديل
        qtyVal:       e.quantity % 1 == 0
            ? e.quantity.toInt().toString()
            : e.quantity.toString(),
        minStockVal:  e.minStock % 1 == 0
            ? e.minStock.toInt().toString()
            : e.minStock.toString(),
        isEdit:       true,          // ← هذا تعديل
      ));
    } else {
      _addEmptyRow();
    }
  }

  void _addEmptyRow() {
    setState(() => _rows.add(_RowData()));
    // انتقل لأسفل بعد إضافة صف
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_vScroll.hasClients) {
        _vScroll.animateTo(
          _vScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _removeRow(int index) {
    if (_rows.length == 1 && widget.existingItem == null) {
      setState(() {
        _rows[0].name.clear();
        _rows[0].supplier.clear();
        _rows[0].unit.text = 'pcs';
        _rows[0].price.clear();
        _rows[0].notes.clear();
      });
      return;
    }
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
    });
  }

  Future<void> _saveAll() async {
    if (!_formKey.currentState!.validate()) return;

    // تحقق من وجود صف واحد على الأقل له بيانات
    final validRows = _rows.where((r) => !r.isEmpty).toList();
    if (validRows.isEmpty) {
      _showSnack('يرجى إدخال بيانات مادة واحدة على الأقل', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      if (widget.existingItem != null) {
        await widget.onSave(_rows.first.toItem());
        if (mounted) {
          _showSnack('✅ تم حفظ التعديل بنجاح');
          widget.onClose();
        }
      } else if (widget.onSaveBatch != null && validRows.length > 1) {
        await widget.onSaveBatch!(validRows.map((r) => r.toItem()).toList());
        if (mounted) {
          _showSnack('✅ تم إضافة ${validRows.length} مواد بنجاح');
          widget.onClose();
        }
      } else {
        await widget.onSave(validRows.first.toItem());
        if (mounted) {
          _showSnack('✅ تم الإضافة بنجاح');
          widget.onClose();
        }
      }
    } catch (e) {
      if (mounted) _showSnack('خطأ في الحفظ: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppTheme.errorColor : AppTheme.salesColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _vScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingItem != null;

    return Material(
      color: AppTheme.background,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        children: [
          // ── Header bar ──────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              color: AppTheme.inventoryColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isEdit ? Icons.edit_rounded : Icons.table_rows_rounded,
                    color: Colors.white, size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isEdit ? 'تعديل المادة' : 'إضافة مواد للمخزن',
                        style: const TextStyle(
                          color: Colors.white, fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (!isEdit)
                        Text(
                          '${_rows.length} صف',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.80),
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ),
                ),
                // أيقونة إضافة صف
                if (!isEdit) ...[
                  _headerIcon(
                    icon: Icons.add_rounded,
                    tooltip: 'إضافة صف جديد',
                    onTap: _isSaving ? null : _addEmptyRow,
                  ),
                  const SizedBox(width: 6),
                ],
                // أيقونة حفظ
                _headerIcon(
                  icon: _isSaving
                      ? Icons.hourglass_top_rounded
                      : Icons.save_rounded,
                  tooltip: isEdit ? 'حفظ التعديل' : 'حفظ الكل',
                  onTap: _isSaving ? null : _saveAll,
                  isLoading: _isSaving,
                ),
                const SizedBox(width: 6),
                // أيقونة إغلاق
                _headerIcon(
                  icon: Icons.close_rounded,
                  tooltip: 'إغلاق',
                  onTap: widget.onClose,
                ),
              ],
            ),
          ),
          // ── Table ────────────────────────────────────────────────────
          Expanded(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: Scrollbar(
                      controller: _vScroll,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _vScroll,
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: _rows.length,
                        itemBuilder: (ctx, i) => _buildRow(i),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Bottom icon bar ─────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                if (!isEdit) ...[
                  _bottomIcon(
                    icon: Icons.add_circle_outline_rounded,
                    label: 'صف جديد',
                    color: AppTheme.inventoryColor,
                    onTap: _isSaving ? null : _addEmptyRow,
                  ),
                  const Spacer(),
                ],
                _bottomIcon(
                  icon: Icons.cancel_outlined,
                  label: 'إلغاء',
                  color: AppTheme.textGrey,
                  onTap: widget.onClose,
                ),
                const SizedBox(width: 16),
                _bottomIcon(
                  icon: _isSaving
                      ? Icons.hourglass_top_rounded
                      : Icons.save_alt_rounded,
                  label: isEdit ? 'حفظ' : 'حفظ الكل',
                  color: AppTheme.salesColor,
                  onTap: _isSaving ? null : _saveAll,
                  filled: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerIcon({
    required IconData icon,
    required String tooltip,
    VoidCallback? onTap,
    bool isLoading = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Icon(icon, color: Colors.white, size: 19),
        ),
      ),
    );
  }

  Widget _bottomIcon({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
    bool filled = false,
  }) {
    final effectiveColor =
        onTap == null ? color.withValues(alpha: 0.35) : color;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: filled ? color.withValues(alpha: 0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border:
                filled ? Border.all(color: color.withValues(alpha: 0.35)) : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: effectiveColor, size: 22),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: effectiveColor,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  // ── رأس الجدول (ويب فقط — سطرين كالبطاقة) ───────────────────────────────
  Widget _buildHeader() {
    // لا يوجد رأس على أي منصة — كل بطاقة تحمل عناوينها بداخلها
    return const SizedBox.shrink();
  }

  // ── صف بيانات ────────────────────────────────────────────────────────────
  Widget _buildRow(int index) {
    final row    = _rows[index];
    final isEdit = widget.existingItem != null;

    // ── موبايل: بطاقة عمودية ────────────────────────────────────────────────
    if (!kIsWeb) {
      return _buildMobileCard(index, row, isEdit);
    }

    // ── ويب/سطح المكتب: نفس تخطيط بطاقة الموبايل (3 سطور) ────────────────────
    final isEven = index % 2 == 0;
    final rowBg  = isEven ? Colors.white : const Color(0xFFF0F7FF);

    return Container(
      decoration: BoxDecoration(
        color: rowBg,
        border: Border(
          bottom: BorderSide(
              color: AppTheme.divider.withValues(alpha: 0.5), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── السطر 1: اسم المادة — عرض كامل + زر الحذف ──────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _labeledField(
                  label: 'اسم المادة *',
                  child: _field(
                    ctrl: row.name,
                    hint: 'اسم المادة',
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // زر الحذف
              Tooltip(
                message: 'حذف الصف',
                child: InkWell(
                  onTap: () => _removeRow(index),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 32,
                    height: 48,
                    margin: const EdgeInsets.only(top: 20),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: AppTheme.errorColor, size: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── السطر 2: الوحدة | سعر المفرد | المجهّز ─────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الوحدة — flex 2
              Expanded(
                flex: 2,
                child: _labeledField(
                  label: 'الوحدة',
                  child: _field(
                      ctrl: row.unit,
                      hint: 'pcs',
                      align: TextAlign.center),
                ),
              ),
              const SizedBox(width: 6),
              // سعر المفرد — flex 4
              Expanded(
                flex: 4,
                child: _labeledField(
                  label: 'سعر المفرد *',
                  child: _field(
                    ctrl: row.price,
                    hint: '0.00',
                    isNumber: true,
                    align: TextAlign.end,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'مطلوب';
                      if (double.tryParse(v.trim()) == null) return 'رقم';
                      return null;
                    },
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // المجهّز — flex 4
              Expanded(
                flex: 4,
                child: _labeledField(
                  label: 'المجهّز',
                  child: _field(ctrl: row.supplier, hint: 'اسم المجهّز'),
                ),
              ),
              const SizedBox(width: 38), // محاذاة مع زر الحذف في السطر الأول
            ],
          ),
          const SizedBox(height: 8),
          // ── السطر 3: الملاحظات — عرض كامل ──────────────────────────
          Row(
            children: [
              Expanded(
                child: _labeledField(
                  label: 'ملاحظات',
                  child: _field(
                    ctrl: row.notes,
                    hint: 'ملاحظات...',
                    fullWidth: true,
                  ),
                ),
              ),
              const SizedBox(width: 38), // محاذاة مع زر الحذف في السطر الأول
            ],
          ),
        ],
      ),
    );
  }

  // ── بطاقة الموبايل (تخطيط عمودي) ─────────────────────────────────────────
  Widget _buildMobileCard(int index, _RowData row, bool isEdit) {
    final isEven = index % 2 == 0;
    final cardBg = isEven ? Colors.white : const Color(0xFFF4F8FF);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppTheme.inventoryColor.withValues(alpha: 0.18), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── رقم البطاقة + زر الحذف (إضافة متعددة فقط) ──────────────
          if (!isEdit)
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.inventoryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'مادة ${index + 1}',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.inventoryColor),
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => _removeRow(index),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: AppTheme.errorColor, size: 16),
                  ),
                ),
              ],
            ),
          if (!isEdit) const SizedBox(height: 8),

          // ── السطر 1: اسم المادة — عرض كامل ──────────────────────────
          _labeledField(
            label: 'اسم المادة *',
            child: _field(
              ctrl: row.name,
              hint: 'اسم المادة',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
            ),
          ),
          const SizedBox(height: 8),

          // ── السطر 2: الوحدة | سعر المفرد | المجهّز ─────────────────
          // الكمية مخفية دائماً — تُحفظ تلقائياً
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الوحدة — flex 2
              Expanded(
                flex: 2,
                child: _labeledField(
                  label: 'الوحدة',
                  child: _field(
                      ctrl: row.unit,
                      hint: 'pcs',
                      align: TextAlign.center),
                ),
              ),
              const SizedBox(width: 6),
              // سعر المفرد — flex 4
              Expanded(
                flex: 4,
                child: _labeledField(
                  label: 'سعر المفرد *',
                  child: _field(
                    ctrl: row.price,
                    hint: '0.00',
                    isNumber: true,
                    align: TextAlign.end,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'مطلوب';
                      if (double.tryParse(v.trim()) == null) return 'رقم';
                      return null;
                    },
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // المجهّز — flex 4
              Expanded(
                flex: 4,
                child: _labeledField(
                  label: 'المجهّز',
                  child: _field(ctrl: row.supplier, hint: 'اسم المجهّز'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── السطر 3: الملاحظات — عرض كامل ──────────────────────────
          _labeledField(
            label: 'ملاحظات',
            child: _field(
              ctrl: row.notes,
              hint: 'ملاحظات...',
              fullWidth: true,
            ),
          ),
        ],
      ),
    );
  }

  // ── حقل مع تسمية فوقه ────────────────────────────────────────────────────
  Widget _labeledField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,                          // ← عنوان 16 عريض
            fontWeight: FontWeight.bold,
            color: AppTheme.inventoryColor.withValues(alpha: 0.90),
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  // ── حقل نص مشترك ─────────────────────────────────────────────────────────
  Widget _field({
    required TextEditingController ctrl,
    required String hint,
    bool isNumber = false,
    TextAlign align = TextAlign.start,
    String? Function(String?)? validator,
    bool fullWidth = false,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      textAlign: align,
      style: const TextStyle(
        fontSize: 14,                              // ← نص الحقل 14 عريض
        fontWeight: FontWeight.bold,
      ),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppTheme.textGrey,
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFDDE1EA)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFDDE1EA)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: AppTheme.inventoryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.errorColor),
        ),
        errorStyle: const TextStyle(fontSize: 11, height: 0.9),
      ),
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
