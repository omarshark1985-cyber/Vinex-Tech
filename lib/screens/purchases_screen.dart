import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/purchase_model.dart';
import '../models/inventory_model.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import '../utils/currency_helper.dart';
import '../utils/responsive.dart';
import '../main.dart' show routeObserver;

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

// ── Sort options for Purchases ──────────────────────────────────────────────
enum _PurchaseSort { dateDesc, dateAsc, amountDesc, amountAsc, nameAZ, nameZA }

class _PurchasesScreenState extends State<PurchasesScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  List<Purchase> _purchases = [];
  List<Purchase> _filtered = [];
  final _searchCtrl = TextEditingController();
  late TabController _tabController;
  StreamSubscription<List<Purchase>>? _purchasesSub;
  _PurchaseSort _sort = _PurchaseSort.dateDesc;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _subscribeToPurchases();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPopNext() {
    DatabaseService.refreshData();
  }

  @override
  void didPush() {
    DatabaseService.refreshData();
  }

  void _subscribeToPurchases() {
    _purchasesSub = DatabaseService.purchasesStream.listen((purchases) {
      if (mounted) {
        setState(() {
          _purchases = purchases;
          _applyFilter();
        });
      }
    });
    DatabaseService.refreshData();
  }

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase();
    List<Purchase> list = q.isEmpty
        ? List.from(_purchases)
        : _purchases
            .where((p) =>
                p.itemName.toLowerCase().contains(q) ||
                p.supplierName.toLowerCase().contains(q))
            .toList();
    switch (_sort) {
      case _PurchaseSort.dateDesc:
        list.sort((a, b) => b.date.compareTo(a.date));
        break;
      case _PurchaseSort.dateAsc:
        list.sort((a, b) => a.date.compareTo(b.date));
        break;
      case _PurchaseSort.amountDesc:
        list.sort((a, b) => b.totalPrice.compareTo(a.totalPrice));
        break;
      case _PurchaseSort.amountAsc:
        list.sort((a, b) => a.totalPrice.compareTo(b.totalPrice));
        break;
      case _PurchaseSort.nameAZ:
        list.sort((a, b) => a.itemName.toLowerCase().compareTo(b.itemName.toLowerCase()));
        break;
      case _PurchaseSort.nameZA:
        list.sort((a, b) => b.itemName.toLowerCase().compareTo(a.itemName.toLowerCase()));
        break;
    }
    _filtered = list;
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _purchasesSub?.cancel();
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _search(String query) {
    setState(() => _applyFilter());
  }

  void _changeSort(_PurchaseSort sort) {
    setState(() {
      _sort = sort;
      _applyFilter();
    });
  }

  void _showEditDialog(Purchase purchase) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PurchaseDialog(
          existingPurchase: purchase,
          onSave: (updated) async {
            await DatabaseService.updatePurchaseWithStockAdjustment(purchase, updated);
            DatabaseService.refreshData();
          },
        ),
      ),
    );
  }

  void _showAddDialog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PurchaseDialog(
          onSave: (purchase) async {
            await DatabaseService.addPurchaseWithStockUpdate(purchase);
            DatabaseService.refreshData();
          },
        ),
      ),
    );
  }

  void _confirmDelete(Purchase purchase) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeletePurchaseDialog(
          purchase: purchase,
          onConfirmed: () async {
            await DatabaseService.deletePurchaseWithStockUpdate(purchase.id);
            DatabaseService.refreshData();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ تم حذف "${purchase.itemName}" وتعديل المخزن'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          },
        ),
    );
  }

  // Build grouped-by-supplier list
  List<_SupplierGroup> get _supplierGroups {
    final Map<String, List<Purchase>> grouped = {};
    for (final p in _purchases) {
      final key = p.supplierName.isNotEmpty ? p.supplierName : 'Unknown Supplier';
      grouped.putIfAbsent(key, () => []).add(p);
    }
    return grouped.entries.map((e) => _SupplierGroup(e.key, e.value)).toList()
      ..sort((a, b) => b.totalSpent.compareTo(a.totalSpent));
  }

  @override
  Widget build(BuildContext context) {
    final total = _purchases.fold<double>(0, (s, e) => s + e.totalPrice);
    final r = R.of(context);
    final groups = _supplierGroups;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.purchasesColor,
        title: const Text('Purchases'),
        actions: [
          // ── Sort button ──────────────────────────────────────────────
          PopupMenuButton<_PurchaseSort>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort',
            initialValue: _sort,
            onSelected: _changeSort,
            itemBuilder: (_) => [
              _sortMenuItem(_PurchaseSort.dateDesc,   Icons.arrow_downward_rounded, 'Date: Newest First',  _sort),
              _sortMenuItem(_PurchaseSort.dateAsc,    Icons.arrow_upward_rounded,   'Date: Oldest First',  _sort),
              _sortMenuItem(_PurchaseSort.amountDesc, Icons.trending_down_rounded,  'Amount: High → Low',  _sort),
              _sortMenuItem(_PurchaseSort.amountAsc,  Icons.trending_up_rounded,    'Amount: Low → High',  _sort),
              _sortMenuItem(_PurchaseSort.nameAZ,     Icons.sort_by_alpha_rounded,  'Name: A → Z',         _sort),
              _sortMenuItem(_PurchaseSort.nameZA,     Icons.sort_by_alpha_rounded,  'Name: Z → A',         _sort),
            ],
          ),
          IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => DatabaseService.refreshData()),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            const Tab(text: 'All Purchases', icon: Icon(Icons.list_rounded)),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.store_rounded, size: 16),
                  const SizedBox(width: 4),
                  Text('By Supplier (${groups.length})'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Stats Banner ─────────────────────────────────────────────────
          Container(
            color: AppTheme.purchasesColor,
            padding: EdgeInsets.fromLTRB(r.hPad, 0, r.hPad, 16),
            child: Row(
              children: [
                _StatBox(
                    label: 'Total Orders',
                    value: '${_purchases.length}',
                    icon: Icons.shopping_cart_rounded),
                SizedBox(width: r.gap),
                _StatBox(
                    label: 'Total Spent',
                    value: CurrencyHelper.format(total),
                    icon: Icons.payments_rounded),
              ],
            ),
          ),
          // ── Search Field ─────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.all(r.hPad),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _search,
              style: TextStyle(fontSize: r.fs15),
              decoration: InputDecoration(
                hintText: 'Search by item or supplier...',
                hintStyle: TextStyle(fontSize: r.fs14),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppTheme.purchasesColor),
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
          // ── Tab Views ────────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1 – All Purchases Table
                _filtered.isEmpty
                    ? _EmptyState(
                        icon: Icons.shopping_cart_rounded,
                        message: 'No purchase records found',
                        onAdd: _showAddDialog,
                      )
                    : _PurchaseTable(
                        purchases: _filtered,
                        onEdit: _showEditDialog,
                        onDelete: _confirmDelete,
                      ),
                // Tab 2 – By Supplier
                groups.isEmpty
                    ? _EmptyState(
                        icon: Icons.store_rounded,
                        message: 'No purchase records found',
                        onAdd: _showAddDialog,
                      )
                    : _SupplierTable(
                        groups: groups,
                        onTapGroup: (group) {
                          // Switch to All tab and filter by supplier
                          _searchCtrl.text = group.supplierName;
                          _search(group.supplierName);
                          _tabController.animateTo(0);
                        },
                      ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: AppTheme.purchasesColor,
        icon: const Icon(Icons.add_rounded),
        label: Text('New Purchase', style: TextStyle(fontSize: r.fs15)),
      ),
    );
  }
}

// ── Supplier Group Data Class ─────────────────────────────────────────────────
class _SupplierGroup {
  final String supplierName;
  final List<Purchase> purchases;

  _SupplierGroup(this.supplierName, this.purchases);

  double get totalSpent =>
      purchases.fold(0, (sum, p) => sum + p.totalPrice);

  int get orderCount => purchases.length;
}

// ── Purchases Table (header + rows) ──────────────────────────────────────────
class _PurchaseTable extends StatelessWidget {
  final List<Purchase> purchases;
  final void Function(Purchase) onEdit;
  final void Function(Purchase) onDelete;

  const _PurchaseTable({
    required this.purchases,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final r = R.of(context);
    // On mobile: show cards; on tablet/desktop: show table
    if (r.isMobile) {
      return _MobileCardList(
          purchases: purchases, onEdit: onEdit, onDelete: onDelete);
    }
    return _DesktopTable(
        purchases: purchases, onEdit: onEdit, onDelete: onDelete);
  }
}

// ── Mobile Card View ──────────────────────────────────────────────────────────
class _MobileCardList extends StatelessWidget {
  final List<Purchase> purchases;
  final void Function(Purchase) onEdit;
  final void Function(Purchase) onDelete;

  const _MobileCardList(
      {required this.purchases,
      required this.onEdit,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final r = R.of(context);
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(r.hPad, 8, r.hPad, 80),
      itemCount: purchases.length,
      itemBuilder: (ctx, i) {
        final p = purchases[i];
        return _PurchaseCard(
            purchase: p, onEdit: onEdit, onDelete: onDelete, r: r);
      },
    );
  }
}

// ── Single Purchase Card (mobile) ─────────────────────────────────────────────
class _PurchaseCard extends StatelessWidget {
  final Purchase purchase;
  final void Function(Purchase) onEdit;
  final void Function(Purchase) onDelete;
  final R r;

  const _PurchaseCard(
      {required this.purchase,
      required this.onEdit,
      required this.onDelete,
      required this.r});

  @override
  Widget build(BuildContext context) {
    final p = purchase;
    return Card(
      margin: EdgeInsets.only(bottom: r.gap),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(r.cardPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Row 1: أيقونة + (اسم المادة | اسم المجهز) + أزرار ──────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // أيقونة المادة
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.purchasesColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.inventory_2_outlined,
                      color: AppTheme.purchasesColor, size: r.iconMd),
                ),
                SizedBox(width: r.gapS),

                // اسم المادة | اسم المجهز — في نفس السطر الأفقي
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // اسم المادة
                      Flexible(
                        flex: 1,
                        child: Text(
                          p.itemName,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: r.fs15,
                              color: AppTheme.textDark),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // فاصل + اسم المجهز بجانب المادة مباشرة
                      if (p.supplierName.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text('|',
                              style: TextStyle(
                                  color: AppTheme.divider,
                                  fontSize: r.fs14,
                                  fontWeight: FontWeight.w300)),
                        ),
                        Flexible(
                          flex: 1,
                          child: Text(
                            p.supplierName,
                            style: TextStyle(
                                color: AppTheme.purchasesColor,
                                fontSize: r.fs13,
                                fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ── فاصل مرئي قبل الأزرار ──────────────────────────────
                Container(
                  width: 1,
                  height: 36,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  color: AppTheme.divider,
                ),

                // ── أزرار التعديل والحذف (مستقلة تماماً) ───────────────
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionBtn(
                      icon: Icons.edit_outlined,
                      color: AppTheme.primaryBlue,
                      onTap: () => onEdit(p),
                    ),
                    const SizedBox(width: 6),
                    _ActionBtn(
                      icon: Icons.delete_outline_rounded,
                      color: AppTheme.errorColor,
                      onTap: () => onDelete(p),
                    ),
                  ],
                ),
              ],
            ),

            Divider(height: r.gap * 2, color: AppTheme.divider),

            // ── Row 2: الكمية | سعر القطعة ───────────────────────────
            Row(
              children: [
                Expanded(
                  child: _InfoRow(
                    icon: Icons.format_list_numbered_rounded,
                    label: 'الكمية',
                    value: p.quantity % 1 == 0
                        ? p.quantity.toInt().toString()
                        : p.quantity.toStringAsFixed(2),
                    valueColor: AppTheme.purchasesColor,
                    r: r,
                  ),
                ),
                // فاصل عمودي بين الحقلين
                Container(
                  width: 1,
                  height: 32,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: AppTheme.divider,
                ),
                Expanded(
                  child: _InfoRow(
                    icon: Icons.attach_money_rounded,
                    label: 'سعر القطعة',
                    value: CurrencyHelper.format(p.unitPrice),
                    r: r,
                  ),
                ),
              ],
            ),
            SizedBox(height: r.gapS),

            // ── Row 3: المبلغ الإجمالي ────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppTheme.purchasesColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppTheme.purchasesColor.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calculate_outlined,
                          color: AppTheme.purchasesColor,
                          size: r.iconSm + 2),
                      const SizedBox(width: 6),
                      Text('المبلغ الإجمالي',
                          style: TextStyle(
                              fontSize: r.fs13,
                              color: AppTheme.textGrey,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                  Text(
                    CurrencyHelper.format(p.totalPrice),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: r.fs15,
                        color: AppTheme.purchasesColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Info Row helper for cards ─────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final R r;

  const _InfoRow(
      {required this.icon,
      required this.label,
      required this.value,
      required this.r,
      this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: r.iconSm, color: AppTheme.textGrey),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      TextStyle(fontSize: r.fs11, color: AppTheme.textGrey)),
              Text(value,
                  style: TextStyle(
                      fontSize: r.fs13,
                      fontWeight: FontWeight.w600,
                      color: valueColor ?? AppTheme.textDark),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Action Button helper ──────────────────────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

// ── Desktop Table view ────────────────────────────────────────────────────────
class _DesktopTable extends StatelessWidget {
  final List<Purchase> purchases;
  final void Function(Purchase) onEdit;
  final void Function(Purchase) onDelete;

  const _DesktopTable(
      {required this.purchases,
      required this.onEdit,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final r = R.of(context);
    return Column(
      children: [
        // ── Table Header ─────────────────────────────────────────────────
        Container(
          margin: EdgeInsets.fromLTRB(r.hPad, 0, r.hPad, 0),
          padding: EdgeInsets.symmetric(
              horizontal: r.gapS + 4, vertical: r.isMobile ? 9 : 11),
          decoration: BoxDecoration(
            color: AppTheme.purchasesColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              // Item / Supplier
              Expanded(
                flex: 5,
                child: Text('المادة / المجهز',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: r.fs13)),
              ),
              // Qty
              SizedBox(
                width: 60,
                child: Text('الكمية',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: r.fs13)),
              ),
              // Unit Price
              SizedBox(
                width: 110,
                child: Text('سعر القطعة',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: r.fs13)),
              ),
              // Total
              SizedBox(
                width: 110,
                child: Text('المبلغ الإجمالي',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: r.fs13)),
              ),
              // Actions
              SizedBox(width: 72),
            ],
          ),
        ),
        // ── Table Rows ───────────────────────────────────────────────────
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(r.hPad, 6, r.hPad, 80),
            itemCount: purchases.length,
            itemBuilder: (ctx, i) {
              final p = purchases[i];
              final isEven = i % 2 == 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 1),
                decoration: BoxDecoration(
                  color: isEven ? Colors.white : AppTheme.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: r.gapS + 4, vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ── Item Name + Supplier + Date ───────────────────
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.itemName,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: r.fs14,
                                  color: AppTheme.textDark),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (p.supplierName.isNotEmpty)
                              Text(
                                p.supplierName,
                                style: TextStyle(
                                    color: AppTheme.textGrey,
                                    fontSize: r.fs12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            Text(
                              DateFormat('dd/MM/yyyy').format(p.date),
                              style: TextStyle(
                                  color: AppTheme.textGrey
                                      .withValues(alpha: 0.7),
                                  fontSize: r.fs11),
                            ),
                          ],
                        ),
                      ),
                      // ── Quantity ─────────────────────────────────────
                      SizedBox(
                        width: 60,
                        child: Text(
                          p.quantity % 1 == 0
                              ? p.quantity.toInt().toString()
                              : p.quantity.toStringAsFixed(1),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: r.fs14,
                              color: AppTheme.purchasesColor),
                        ),
                      ),
                      // ── Unit Price ────────────────────────────────────
                      SizedBox(
                        width: 110,
                        child: Text(
                          CurrencyHelper.format(p.unitPrice),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: r.fs13,
                              color: AppTheme.textGrey),
                        ),
                      ),
                      // ── Total ─────────────────────────────────────────
                      SizedBox(
                        width: 110,
                        child: Text(
                          CurrencyHelper.format(p.totalPrice),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: r.fs13,
                              color: AppTheme.purchasesColor),
                        ),
                      ),
                      // ── Actions ───────────────────────────────────────
                      SizedBox(
                        width: 72,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _ActionBtn(
                              icon: Icons.edit_outlined,
                              color: AppTheme.primaryBlue,
                              onTap: () => onEdit(p),
                            ),
                            const SizedBox(width: 4),
                            _ActionBtn(
                              icon: Icons.delete_outline_rounded,
                              color: AppTheme.errorColor,
                              onTap: () => onDelete(p),
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

// ── Sort Menu Item Helper ─────────────────────────────────────────────────────
PopupMenuItem<T> _sortMenuItem<T>(T value, IconData icon, String label, T current) {
  final bool selected = value == current;
  return PopupMenuItem<T>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 18,
            color: selected ? AppTheme.purchasesColor : AppTheme.textGrey),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? AppTheme.purchasesColor : AppTheme.textDark,
            )),
        if (selected) ...[
          const Spacer(),
          Icon(Icons.check_rounded, size: 16, color: AppTheme.purchasesColor),
        ],
      ],
    ),
  );
}

// ── Supplier Summary Table ────────────────────────────────────────────────────
class _SupplierTable extends StatelessWidget {
  final List<_SupplierGroup> groups;
  final void Function(_SupplierGroup) onTapGroup;

  const _SupplierTable({
    required this.groups,
    required this.onTapGroup,
  });

  @override
  Widget build(BuildContext context) {
    final r = R.of(context);
    return Column(
      children: [
        // ── Table Header ─────────────────────────────────────────────────
        Container(
          margin: EdgeInsets.fromLTRB(r.hPad, 0, r.hPad, 0),
          padding: EdgeInsets.symmetric(
              horizontal: r.gapS + 4, vertical: r.isMobile ? 9 : 11),
          decoration: BoxDecoration(
            color: AppTheme.purchasesColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Text('Supplier',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: r.fs13)),
              ),
              SizedBox(
                width: r.isMobile ? 50 : 70,
                child: Text('Orders',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: r.fs13)),
              ),
              SizedBox(
                width: r.isMobile ? 90 : 110,
                child: Text('Total Spent',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: r.fs13)),
              ),
              const SizedBox(width: 24),
            ],
          ),
        ),
        // ── Supplier Rows ─────────────────────────────────────────────────
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(r.hPad, 6, r.hPad, 80),
            itemCount: groups.length,
            itemBuilder: (ctx, i) {
              final group = groups[i];
              final isEven = i % 2 == 0;
              return GestureDetector(
                onTap: () => onTapGroup(group),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 1),
                  decoration: BoxDecoration(
                    color: isEven ? Colors.white : AppTheme.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: r.gapS + 4,
                        vertical: r.isMobile ? 12 : 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // ── Supplier Icon + Name ──────────────────────
                        Expanded(
                          flex: 5,
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppTheme.purchasesColor
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.store_rounded,
                                    color: AppTheme.purchasesColor,
                                    size: r.iconSm + 2),
                              ),
                              SizedBox(width: r.gapS),
                              Expanded(
                                child: Text(
                                  group.supplierName,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: r.fs14,
                                      color: AppTheme.textDark),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ── Order Count ───────────────────────────────
                        SizedBox(
                          width: r.isMobile ? 50 : 70,
                          child: Text(
                            '${group.orderCount}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: r.fs14,
                                color: AppTheme.purchasesColor),
                          ),
                        ),
                        // ── Total Spent ────────────────────────────────
                        SizedBox(
                          width: r.isMobile ? 90 : 110,
                          child: Text(
                            CurrencyHelper.format(group.totalSpent),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: r.fs13,
                                color: AppTheme.purchasesColor),
                          ),
                        ),
                        // ── Arrow ──────────────────────────────────────
                        const SizedBox(
                          width: 24,
                          child: Icon(Icons.chevron_right_rounded,
                              color: AppTheme.textGrey, size: 18),
                        ),
                      ],
                    ),
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

// ── Purchase Dialog ───────────────────────────────────────────────────────────
class _PurchaseDialog extends StatefulWidget {
  final Function(Purchase) onSave;
  final Purchase? existingPurchase;
  const _PurchaseDialog({required this.onSave, this.existingPurchase});

  @override
  State<_PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<_PurchaseDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _supplierCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _itemSearchCtrl;

  // Selected item from inventory
  InventoryItem? _selectedItem;
  String? _selectedItemName; // for edit mode when item might not be in inventory

  // Inventory items list
  List<InventoryItem> _inventoryItems = [];
  List<InventoryItem> _filteredItems = [];
  bool _loadingInventory = true;
  bool _showDropdown = false;

  bool get _isEditMode => widget.existingPurchase != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existingPurchase;

    _selectedItemName = p?.itemName ?? '';
    _itemSearchCtrl = TextEditingController(text: p?.itemName ?? '');

    _qtyCtrl = TextEditingController(
        text: p != null
            ? (p.quantity % 1 == 0
                ? p.quantity.toInt().toString()
                : p.quantity.toStringAsFixed(2))
            : '');
    _priceCtrl = TextEditingController(
        text: p != null
            ? (p.unitPrice % 1 == 0
                ? p.unitPrice.toInt().toString()
                : p.unitPrice.toStringAsFixed(2))
            : '');
    _supplierCtrl = TextEditingController(text: p?.supplierName ?? '');
    _notesCtrl = TextEditingController(text: p?.notes ?? '');

    _loadInventory();
  }

  Future<void> _loadInventory() async {
    try {
      final items = await DatabaseService.getAllInventoryItemsAsync();
      if (mounted) {
        setState(() {
          _inventoryItems = items..sort(
              (a, b) => a.itemName.compareTo(b.itemName));
          _filteredItems = List.from(_inventoryItems);
          _loadingInventory = false;

          // In edit mode: try to match existing item
          if (_isEditMode && _selectedItemName != null && _selectedItemName!.isNotEmpty) {
            _selectedItem = _inventoryItems
                .cast<InventoryItem?>()
                .firstWhere(
                  (item) => item?.itemName == _selectedItemName,
                  orElse: () => null,
                );
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingInventory = false);
    }
  }

  void _filterItems(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filteredItems = q.isEmpty
          ? List.from(_inventoryItems)
          : _inventoryItems
              .where((item) =>
                  item.itemName.toLowerCase().contains(q) ||
                  item.category.toLowerCase().contains(q))
              .toList();
      _showDropdown = true;
    });
  }

  void _selectItem(InventoryItem item) {
    setState(() {
      _selectedItem    = item;
      _selectedItemName = item.itemName;
      _itemSearchCtrl.text = item.itemName;
      _showDropdown    = false;

      // ── عرض بيانات المخزن: اسم المجهّز (category) ────────────────
      // يُعرض دائماً — المستخدم يمكنه تعديله قبل الحفظ
      _supplierCtrl.text = (item.category.isNotEmpty && item.category != 'عام')
          ? item.category
          : '';

      // ── عرض بيانات المخزن: سعر القطعة ────────────────────────────
      // يُعرض دائماً من المخزن — لن يُحدَّث المخزن بهذه القيمة عند الحفظ
      _priceCtrl.text = item.unitPrice % 1 == 0
          ? item.unitPrice.toInt().toString()
          : item.unitPrice.toStringAsFixed(2);

      // ── عرض بيانات المخزن: الملاحظات (description) ───────────────
      _notesCtrl.text = item.description;
    });
  }

  @override
  void dispose() {
    _itemSearchCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _supplierCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _total {
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    final price = double.tryParse(_priceCtrl.text) ?? 0;
    return qty * price;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.purchasesColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Icon(_isEditMode ? Icons.edit_rounded : Icons.add_shopping_cart_rounded, size: 20),
            const SizedBox(width: 8),
            Text(_isEditMode ? 'تعديل مشتريات' : 'مشتريات جديدة',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, mq.viewInsets.bottom + 100),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

                  // ── 1. Item Name – Dropdown from inventory ────────────
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Search / Selected field
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _showDropdown = !_showDropdown;
                            if (_showDropdown) {
                              _filteredItems = List.from(_inventoryItems);
                            }
                          });
                        },
                        child: AbsorbPointer(
                          absorbing: false,
                          child: TextFormField(
                            controller: _itemSearchCtrl,
                            readOnly: false,
                            onTap: () {
                              setState(() {
                                _showDropdown = true;
                                _filteredItems = List.from(_inventoryItems);
                              });
                            },
                            onChanged: _filterItems,
                            decoration: InputDecoration(
                              labelText: 'اسم المادة',
                              hintText: 'اختر من المخزن أو اكتب للبحث...',
                              prefixIcon: const Icon(
                                Icons.inventory_2_outlined,
                                color: AppTheme.purchasesColor,
                                size: 20,
                              ),
                              suffixIcon: _loadingInventory
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppTheme.purchasesColor,
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      _showDropdown
                                          ? Icons.arrow_drop_up_rounded
                                          : Icons.arrow_drop_down_rounded,
                                      color: AppTheme.purchasesColor,
                                    ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: _selectedItem != null
                                      ? AppTheme.purchasesColor
                                      : const Color(0xFFDDE1E7),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: AppTheme.purchasesColor, width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 14),
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'اسم المادة مطلوب'
                                    : null,
                          ),
                        ),
                      ),

                      // Dropdown list
                      if (_showDropdown)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppTheme.purchasesColor.withValues(alpha: 0.4)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: _loadingInventory
                              ? const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                      child: CircularProgressIndicator()),
                                )
                              : _filteredItems.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Text(
                                        'لا توجد مواد مطابقة في المخزن',
                                        style: TextStyle(
                                          color: AppTheme.textGrey,
                                          fontSize: 12,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    )
                                  : ListView.builder(
                                      shrinkWrap: true,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      itemCount: _filteredItems.length,
                                      itemBuilder: (ctx, idx) {
                                        final item = _filteredItems[idx];
                                        final isSelected =
                                            _selectedItem?.id == item.id;
                                        return InkWell(
                                          onTap: () => _selectItem(item),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14, vertical: 10),
                                            color: isSelected
                                                ? AppTheme.purchasesColor
                                                    .withValues(alpha: 0.08)
                                                : Colors.transparent,
                                            child: Row(
                                              children: [
                                                // Category icon
                                                Container(
                                                  width: 32,
                                                  height: 32,
                                                  decoration: BoxDecoration(
                                                    color: AppTheme
                                                        .purchasesColor
                                                        .withValues(alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                  ),
                                                  child: const Icon(
                                                    Icons.inventory_2_outlined,
                                                    size: 16,
                                                    color:
                                                        AppTheme.purchasesColor,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        item.itemName,
                                                        style: TextStyle(
                                                          fontWeight:
                                                              isSelected
                                                                  ? FontWeight
                                                                      .bold
                                                                  : FontWeight
                                                                      .w500,
                                                          fontSize: 12,
                                                          color:
                                                              AppTheme.textDark,
                                                        ),
                                                      ),
                                                      Row(
                                                        children: [
                                                          Text(
                                                            item.category,
                                                            style:
                                                                const TextStyle(
                                                              fontSize: 12,
                                                              color: AppTheme
                                                                  .textGrey,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              width: 8),
                                                          Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        6,
                                                                    vertical:
                                                                        1),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: item
                                                                      .isLowStock
                                                                  ? AppTheme
                                                                      .warningColor
                                                                      .withValues(
                                                                          alpha:
                                                                              0.15)
                                                                  : AppTheme
                                                                      .salesColor
                                                                      .withValues(
                                                                          alpha:
                                                                              0.1),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          4),
                                                            ),
                                                            child: Text(
                                                              'مخزون: ${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity.toStringAsFixed(1)} ${item.unit}',
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: item
                                                                        .isLowStock
                                                                    ? AppTheme
                                                                        .warningColor
                                                                    : AppTheme
                                                                        .salesColor,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                // Unit price hint
                                                Text(
                                                  CurrencyHelper.format(
                                                      item.unitPrice),
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: AppTheme.textGrey,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                if (isSelected)
                                                  const Padding(
                                                    padding: EdgeInsets.only(
                                                        left: 6),
                                                    child: Icon(
                                                        Icons.check_circle_rounded,
                                                        color: AppTheme
                                                            .purchasesColor,
                                                        size: 18),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                        ),

                      // Selected item info chip
                      if (_selectedItem != null && !_showDropdown)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.purchasesColor.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.purchasesColor.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle_rounded,
                                    size: 14, color: AppTheme.salesColor),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'تم ملء البيانات من المخزن  |  المخزون الحالي: ${_selectedItem!.quantity % 1 == 0 ? _selectedItem!.quantity.toInt() : _selectedItem!.quantity.toStringAsFixed(1)} ${_selectedItem!.unit}',
                                    style: const TextStyle(
                                        fontSize: 12, color: AppTheme.textGrey),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // ── 2. Supplier Name ─────────────────────────────────
                  _buildField(
                      _supplierCtrl, 'اسم المجهز', Icons.store_outlined,
                      required: true),
                  const SizedBox(height: 12),

                  // ── 3. Quantity & Unit Price ─────────────────────────
                  Row(
                    children: [
                      Expanded(
                          child: _buildField(
                              _qtyCtrl, 'الكمية', Icons.numbers_rounded,
                              isNumber: true,
                              required: true,
                              onChanged: (_) => setState(() {}))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _buildField(
                              _priceCtrl, 'سعر القطعة', Icons.attach_money_rounded,
                              isNumber: true,
                              required: true,
                              onChanged: (_) => setState(() {}))),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── 4. Total Amount Display ─────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.purchasesColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppTheme.purchasesColor.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.calculate_outlined,
                                color: AppTheme.purchasesColor, size: 20),
                            const SizedBox(width: 8),
                            const Text('المبلغ الإجمالي:',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                        Text(
                          CurrencyHelper.format(_total),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: AppTheme.purchasesColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── 5. Notes ─────────────────────────────────────────
                  _buildField(
                      _notesCtrl, 'ملاحظات (اختياري)', Icons.note_outlined,
                      maxLines: 2),
                  const SizedBox(height: 20),

                  // ── Action Buttons ───────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                          child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('إلغاء'))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.purchasesColor,
                              padding: const EdgeInsets.symmetric(vertical: 13)),
                          onPressed: () {
                            if (!_formKey.currentState!.validate()) return;
                            final qty = double.tryParse(_qtyCtrl.text) ?? 0;
                            final price = double.tryParse(_priceCtrl.text) ?? 0;
                            final itemName = _itemSearchCtrl.text.trim();
                            widget.onSave(Purchase(
                              id: widget.existingPurchase?.id ??
                                  const Uuid().v4(),
                              itemName: itemName,
                              quantity: qty,
                              unitPrice: price,
                              totalPrice: qty * price,
                              supplierName: _supplierCtrl.text.trim(),
                              date: widget.existingPurchase?.date ??
                                  DateTime.now(),
                              notes: _notesCtrl.text.trim(),
                            ));
                            Navigator.pop(context);
                          },
                          child: Text(
                              _isEditMode ? 'حفظ التعديلات' : 'حفظ المشتريات',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
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
    int maxLines = 1,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        prefixIcon: Padding(
          padding: EdgeInsets.only(bottom: maxLines > 1 ? 24 : 0),
          child: Icon(icon, color: AppTheme.purchasesColor, size: 22),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDDE1EA))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.purchasesColor, width: 2)),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      ),
      validator: required
          ? (v) => (v == null || v.isEmpty) ? '$label مطلوب' : null
          : null,
    );
  }
}

// ── شاشة تأكيد حذف المشتريات الأصيلة ────────────────────────────────────────
class _DeletePurchaseDialog extends StatelessWidget {
  final Purchase purchase;
  final Future<void> Function() onConfirmed;
  const _DeletePurchaseDialog({required this.purchase, required this.onConfirmed});

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
            Text('حذف مشتريات', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
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
                const Expanded(
                  child: Text(
                    'سيتم عكس الكمية في المخزن تلقائياً.',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _PurchaseInfoTile(icon: Icons.inventory_2_outlined, label: 'الصنف', value: purchase.itemName),
          _PurchaseInfoTile(icon: Icons.store_outlined, label: 'المورد', value: purchase.supplierName.isEmpty ? '—' : purchase.supplierName),
          _PurchaseInfoTile(icon: Icons.numbers_rounded, label: 'الكمية', value: purchase.quantity % 1 == 0 ? purchase.quantity.toInt().toString() : purchase.quantity.toStringAsFixed(2)),
          _PurchaseInfoTile(icon: Icons.attach_money_rounded, label: 'الإجمالي', value: CurrencyHelper.format(purchase.totalPrice)),
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

class _PurchaseInfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _PurchaseInfoTile({required this.icon, required this.label, required this.value});
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

// ── Stat Box ──────────────────────────────────────────────────────────────────
class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _StatBox(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final r = R.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: r.iconMd),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: r.fs15)),
                  Text(label,
                      style: TextStyle(
                          color: Colors.white70, fontSize: r.fs12)),
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
      {required this.icon, required this.message, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 72,
              color: AppTheme.textGrey.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(message,
              style: const TextStyle(color: AppTheme.textGrey, fontSize: 12)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onAdd,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.purchasesColor),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add First Record'),
          ),
        ],
      ),
    );
  }
}
