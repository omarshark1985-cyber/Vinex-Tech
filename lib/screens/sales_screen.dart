import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:uuid/uuid.dart';
import '../models/invoice_model.dart';
import '../models/invoice_item_model.dart';
import '../models/inventory_model.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import 'invoice_detail_screen.dart';
import '../utils/currency_helper.dart';
import '../utils/responsive.dart';
import '../main.dart' show routeObserver;

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

// ── Sort options for Sales ────────────────────────────────────────────────
enum _SalesSort { dateDesc, dateAsc, amountDesc, amountAsc, nameAZ, nameZA, invDesc, invAsc }

class _SalesScreenState extends State<SalesScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  List<Invoice> _invoices = [];
  List<Invoice> _filtered = [];
  final _searchCtrl = TextEditingController();
  double _totalRevenue = 0;
  StreamSubscription<List<Invoice>>? _invoicesSub;
  late TabController _tabController;
  _SalesSort _sort = _SalesSort.dateDesc;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _subscribeToInvoices();
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

  void _subscribeToInvoices() {
    _invoicesSub = DatabaseService.invoicesStream.listen((invoices) {
      if (mounted) {
        setState(() {
          _invoices = invoices;
          _totalRevenue = invoices.fold(0.0, (sum, inv) => sum + inv.totalAmount);
          _applyFilter();
        });
      }
    });
    // Trigger immediate fresh fetch from Firebase (emits back via stream)
    DatabaseService.refreshData();
  }

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase();
    List<Invoice> list = q.isEmpty
        ? List.from(_invoices)
        : _invoices
            .where((inv) =>
                inv.customerName.toLowerCase().contains(q) ||
                inv.invoiceNumber.toString().contains(q))
            .toList();
    switch (_sort) {
      case _SalesSort.dateDesc:
        list.sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate));
        break;
      case _SalesSort.dateAsc:
        list.sort((a, b) => a.invoiceDate.compareTo(b.invoiceDate));
        break;
      case _SalesSort.amountDesc:
        list.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
        break;
      case _SalesSort.amountAsc:
        list.sort((a, b) => a.totalAmount.compareTo(b.totalAmount));
        break;
      case _SalesSort.nameAZ:
        list.sort((a, b) => a.customerName.toLowerCase().compareTo(b.customerName.toLowerCase()));
        break;
      case _SalesSort.nameZA:
        list.sort((a, b) => b.customerName.toLowerCase().compareTo(a.customerName.toLowerCase()));
        break;
      case _SalesSort.invDesc:
        list.sort((a, b) => b.invoiceNumber.compareTo(a.invoiceNumber));
        break;
      case _SalesSort.invAsc:
        list.sort((a, b) => a.invoiceNumber.compareTo(b.invoiceNumber));
        break;
    }
    _filtered = list;
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _invoicesSub?.cancel();
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // Build grouped-by-customer list
  List<_CustomerGroup> get _customerGroups {
    final Map<String, List<Invoice>> grouped = {};
    for (final inv in _invoices) {
      final key = inv.customerName.isNotEmpty ? inv.customerName : 'Unknown Customer';
      grouped.putIfAbsent(key, () => []).add(inv);
    }
    return grouped.entries
        .map((e) => _CustomerGroup(e.key, e.value))
        .toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
  }

  void _search(String q) {
    setState(() => _applyFilter());
  }

  void _changeSort(_SalesSort sort) {
    setState(() {
      _sort = sort;
      _applyFilter();
    });
  }

  void _openNewInvoice() async {
    await showInvoiceFormSheet(context);
    DatabaseService.refreshData();
  }

  void _openDetail(Invoice invoice) async {
    await showInvoiceFormSheet(context, editInvoice: invoice);
    DatabaseService.refreshData();
  }

  void _confirmDelete(Invoice invoice) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            // ── Title ──────────────────────────────────────────────────────
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delete_forever_rounded,
                      color: AppTheme.errorColor, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'حذف الفاتورة',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.errorColor),
                  ),
                ),
              ],
            ),
            // ── Content ────────────────────────────────────────────────────
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Divider(height: 20),
                  // Warning message
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'هل أنت متأكد من حذف الفاتورة رقم #${invoice.invoiceNumber}؟',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Invoice info
                  _DialogInfoRow(
                    icon: Icons.person_outline_rounded,
                    label: 'العميل',
                    value: invoice.customerName,
                  ),
                  _DialogInfoRow(
                    icon: Icons.calendar_today_rounded,
                    label: 'التاريخ',
                    value: DateFormat('dd/MM/yyyy').format(invoice.invoiceDate),
                  ),
                  _DialogInfoRow(
                    icon: Icons.attach_money_rounded,
                    label: 'الإجمالي',
                    value: CurrencyHelper.format(invoice.totalAmount),
                    valueColor: AppTheme.salesColor,
                  ),
                  const SizedBox(height: 10),
                  // Items to restore
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                color: AppTheme.primaryBlue, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'المواد التي ستُعاد للمخزن:',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: AppTheme.primaryBlue),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...invoice.items.map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  const Icon(
                                      Icons.add_circle_outline_rounded,
                                      color: Colors.green,
                                      size: 14),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      item.itemName,
                                      style:
                                          const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  Text(
                                    '+${item.quantity.toStringAsFixed(item.quantity == item.quantity.roundToDouble() ? 0 : 1)}',
                                    style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'لا يمكن التراجع عن هذا الإجراء.',
                    style: TextStyle(color: AppTheme.textGrey, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  // ── Buttons inside content (avoids Expanded-in-actions crash) ──
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('لا، تراجع',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            foregroundColor: AppTheme.textGrey,
                            side: const BorderSide(color: AppTheme.textGrey),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            Navigator.of(dialogCtx).pop();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Row(children: [
                                    SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white)),
                                    SizedBox(width: 12),
                                    Text('جاري حذف الفاتورة وإعادة المواد للمخزن...'),
                                  ]),
                                  duration: Duration(seconds: 4),
                                  backgroundColor: AppTheme.errorColor,
                                ),
                              );
                            }
                            await DatabaseService.deleteInvoice(invoice.id);
                            await DatabaseService.refreshData();
                            if (mounted) {
                              ScaffoldMessenger.of(context).hideCurrentSnackBar();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '✅ تم حذف الفاتورة #${invoice.invoiceNumber} وإعادة المواد للمخزن'),
                                  backgroundColor: Colors.green,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.delete_forever_rounded, size: 18),
                          label: const Text('نعم، احذف',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            backgroundColor: AppTheme.errorColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalRevenue = _totalRevenue;
    final r = R.of(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.salesColor,
        title: const Text('Sales Invoices'),
        actions: [
          // ── Sort button ──────────────────────────────────────────────
          PopupMenuButton<_SalesSort>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort',
            initialValue: _sort,
            onSelected: _changeSort,
            itemBuilder: (_) => [
              _salesSortItem(_SalesSort.dateDesc,   Icons.arrow_downward_rounded,  'Date: Newest First',    _sort),
              _salesSortItem(_SalesSort.dateAsc,    Icons.arrow_upward_rounded,    'Date: Oldest First',    _sort),
              _salesSortItem(_SalesSort.amountDesc, Icons.trending_down_rounded,   'Amount: High → Low',   _sort),
              _salesSortItem(_SalesSort.amountAsc,  Icons.trending_up_rounded,     'Amount: Low → High',   _sort),
              _salesSortItem(_SalesSort.nameAZ,     Icons.sort_by_alpha_rounded,   'Customer: A → Z',      _sort),
              _salesSortItem(_SalesSort.nameZA,     Icons.sort_by_alpha_rounded,   'Customer: Z → A',      _sort),
              _salesSortItem(_SalesSort.invDesc,    Icons.format_list_numbered_rtl_rounded, 'Invoice #: High → Low', _sort),
              _salesSortItem(_SalesSort.invAsc,     Icons.format_list_numbered_rounded,     'Invoice #: Low → High', _sort),
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
            const Tab(text: 'كل الفواتير', icon: Icon(Icons.receipt_long_rounded)),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_rounded, size: 16),
                  const SizedBox(width: 4),
                  Text('حسب الزبون (${_customerGroups.length})'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Stats banner ────────────────────────────────────────────────
          Container(
            color: AppTheme.salesColor,
            padding: EdgeInsets.fromLTRB(r.hPad, 0, r.hPad, 16),
            child: Row(
              children: [
                _StatChip(
                  icon: Icons.receipt_long_rounded,
                  label: 'Invoices',
                  value: '${_invoices.length}',
                ),
                SizedBox(width: r.gap),
                _StatChip(
                  icon: Icons.attach_money_rounded,
                  label: 'Total Revenue',
                  value: CurrencyHelper.format(totalRevenue),
                ),
              ],
            ),
          ),

          // ── Search ──────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.all(r.hPad),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _search,
              style: TextStyle(fontSize: r.fs15),
              decoration: InputDecoration(
                hintText: 'Search by customer name or invoice #...',
                hintStyle: TextStyle(fontSize: r.fs14),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppTheme.salesColor),
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
                // Tab 1 – All Invoices Table
                _filtered.isEmpty
                    ? _EmptyState(onAdd: _openNewInvoice)
                    : _InvoiceTable(
                        invoices: _filtered,
                        onTap: _openDetail,
                        onDelete: _confirmDelete,
                      ),
                // Tab 2 – By Customer
                _customerGroups.isEmpty
                    ? _EmptyState(onAdd: _openNewInvoice)
                    : _CustomerTable(
                        groups: _customerGroups,
                        onTapGroup: (group) {
                          _searchCtrl.text = group.customerName;
                          _search(group.customerName);
                          _tabController.animateTo(0);
                        },
                      ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewInvoice,
        backgroundColor: AppTheme.salesColor,
        icon: const Icon(Icons.add_rounded),
        label: Text('New Invoice', style: TextStyle(fontSize: r.fs15)),
      ),
    );
  }
}

// ── Sort Menu Item Helper (Sales) ─────────────────────────────────────────────
PopupMenuItem<_SalesSort> _salesSortItem(_SalesSort value, IconData icon, String label, _SalesSort current) {
  final bool selected = value == current;
  return PopupMenuItem<_SalesSort>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 18,
            color: selected ? AppTheme.salesColor : AppTheme.textGrey),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? AppTheme.salesColor : AppTheme.textDark,
            )),
        if (selected) ...[
          const Spacer(),
          Icon(Icons.check_rounded, size: 16, color: AppTheme.salesColor),
        ],
      ],
    ),
  );
}

// ── Customer Group Data Class ─────────────────────────────────────────────────
class _CustomerGroup {
  final String customerName;
  final List<Invoice> invoices;

  _CustomerGroup(this.customerName, this.invoices);

  double get totalAmount =>
      invoices.fold(0, (sum, inv) => sum + inv.totalAmount);

  int get invoiceCount => invoices.length;
}

// ── Invoice List — بطاقة لكل فاتورة تعرض تفاصيل المواد ────────────────────────
class _InvoiceTable extends StatelessWidget {
  final List<Invoice> invoices;
  final void Function(Invoice) onTap;
  final void Function(Invoice) onDelete;

  const _InvoiceTable({
    required this.invoices,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final r = R.of(context);
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(r.hPad, 8, r.hPad, 90),
      itemCount: invoices.length,
      itemBuilder: (ctx, i) => _InvoiceCard(
        invoice: invoices[i],
        r: r,
        onEdit: onTap,
        onDelete: onDelete,
      ),
    );
  }
}

// ── بطاقة فاتورة مبسّطة: رقم | زبون | تاريخ | مبلغ كلي | زرّا تعديل/حذف ──────
class _InvoiceCard extends StatelessWidget {
  final Invoice invoice;
  final R r;
  final void Function(Invoice) onEdit;
  final void Function(Invoice) onDelete;

  const _InvoiceCard({
    required this.invoice,
    required this.r,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final inv = invoice;
    return Card(
      margin: EdgeInsets.only(bottom: r.gap),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: r.cardPad, vertical: r.gapS + 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── رقم الفاتورة ──────────────────────────────────────────
              Container(
                width: r.isMobile ? 52 : 60,
                height: r.isMobile ? 52 : 60,
                decoration: BoxDecoration(
                  color: AppTheme.salesColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_rounded,
                          color: AppTheme.salesColor,
                          size: r.isMobile ? 18 : 20),
                      const SizedBox(height: 2),
                      Text(
                        '#${inv.invoiceNumber.toString().padLeft(4, '0')}',
                        style: TextStyle(
                          color: AppTheme.salesColor,
                          fontWeight: FontWeight.bold,
                          fontSize: r.fs11,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: r.gap),

              // ── اسم الزبون + التاريخ ──────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inv.customerName.isNotEmpty
                          ? inv.customerName
                          : 'زبون غير محدد',
                      style: TextStyle(
                        color: AppTheme.textDark,
                        fontWeight: FontWeight.bold,
                        fontSize: r.fs15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_rounded,
                            size: 12, color: AppTheme.textGrey),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('dd/MM/yyyy').format(inv.invoiceDate),
                          style: TextStyle(
                              color: AppTheme.textGrey, fontSize: r.fs12),
                        ),
                        if (inv.items.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Icon(Icons.inventory_2_outlined,
                              size: 12, color: AppTheme.textGrey),
                          const SizedBox(width: 3),
                          Text(
                            '${inv.items.length} ${inv.items.length == 1 ? 'مادة' : 'مواد'}',
                            style: TextStyle(
                                color: AppTheme.textGrey, fontSize: r.fs12),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: r.gapS),

              // ── المبلغ الكلي ──────────────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyHelper.format(inv.totalAmount),
                    style: TextStyle(
                      color: AppTheme.salesColor,
                      fontWeight: FontWeight.bold,
                      fontSize: r.isMobile ? r.fs14 : r.fs15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'المبلغ الكلي',
                    style: TextStyle(
                        color: AppTheme.textGrey, fontSize: r.fs11),
                  ),
                ],
              ),
              SizedBox(width: r.gapS),

              // ── فاصل عمودي ───────────────────────────────────────────
              Container(
                width: 1,
                height: 42,
                margin: EdgeInsets.symmetric(horizontal: r.gapS),
                color: AppTheme.divider,
              ),

              // ── زر تعديل ─────────────────────────────────────────────
              _ActionBtn(
                icon: Icons.edit_outlined,
                color: AppTheme.primaryBlue,
                bgColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
                tooltip: 'تعديل',
                onTap: () => onEdit(inv),
              ),
              SizedBox(width: r.gapS),

              // ── زر حذف ───────────────────────────────────────────────
              _ActionBtn(
                icon: Icons.delete_outline_rounded,
                color: AppTheme.errorColor,
                bgColor: AppTheme.errorColor.withValues(alpha: 0.1),
                tooltip: 'حذف',
                onTap: () => onDelete(inv),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── زر إجراء داخل البطاقة ────────────────────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

// _HeaderBtn removed – replaced by _ActionBtn

// ── Customer Summary Table ────────────────────────────────────────────────────
class _CustomerTable extends StatelessWidget {
  final List<_CustomerGroup> groups;
  final void Function(_CustomerGroup) onTapGroup;

  const _CustomerTable({
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
            color: AppTheme.salesColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Text('اسم الزبون',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: r.fs13)),
              ),
              SizedBox(
                width: r.isMobile ? 58 : 72,
                child: Text('الفواتير',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: r.fs13)),
              ),
              SizedBox(
                width: r.isMobile ? 90 : 110,
                child: Text('الإجمالي',
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
        // ── Customer Rows ─────────────────────────────────────────────────
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
                        // ── Customer icon + Name ──────────────────────
                        Expanded(
                          flex: 5,
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppTheme.salesColor
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.person_rounded,
                                    color: AppTheme.salesColor,
                                    size: r.iconSm + 2),
                              ),
                              SizedBox(width: r.gapS),
                              Expanded(
                                child: Text(
                                  group.customerName,
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
                        // ── Invoice Count ─────────────────────────────
                        SizedBox(
                          width: r.isMobile ? 58 : 72,
                          child: Text(
                            '${group.invoiceCount}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: r.fs14,
                                color: AppTheme.salesColor),
                          ),
                        ),
                        // ── Total Amount ──────────────────────────────
                        SizedBox(
                          width: r.isMobile ? 90 : 110,
                          child: Text(
                            CurrencyHelper.format(group.totalAmount),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: r.fs13,
                                color: AppTheme.salesColor),
                          ),
                        ),
                        // ── Arrow ─────────────────────────────────────
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

// ─── Empty State ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_rounded,
              size: 72, color: AppTheme.textGrey.withValues(alpha: 0.35)),
          const SizedBox(height: 16),
          const Text('No invoices yet',
              style: TextStyle(
                  color: AppTheme.textGrey,
                  fontSize: 17,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          const Text('Tap the button below to create your first invoice',
              style: TextStyle(color: AppTheme.textGrey, fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onAdd,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.salesColor),
            icon: const Icon(Icons.add_rounded),
            label: const Text('New Invoice'),
          ),
        ],
      ),
    );
  }
}

// ─── Stat Chip ────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatChip(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final r = R.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
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

// ══════════════════════════════════════════════════════════════════════════════
// INVOICE FORM SCREEN  (Create new invoice)
// ══════════════════════════════════════════════════════════════════════════════

// ─── Dialog Info Row helper ───────────────────────────────────────────────────
class _DialogInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _DialogInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textGrey),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(
                  color: AppTheme.textGrey, fontSize: 13)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: valueColor ?? AppTheme.textDark,
              ),
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }
}

// ── دالة عرض قائمة الفاتورة المنبثقة ────────────────────────────────────────
Future<void> showInvoiceFormSheet(BuildContext context, {Invoice? editInvoice}) async {
  await showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) {
      final mq = MediaQuery.of(ctx);
      final w  = mq.size.width  * 0.96;
      final h  = mq.size.height * 0.94;
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: SizedBox(
          width:  w,
          height: h,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: _InvoiceFormSheet(editInvoice: editInvoice),
          ),
        ),
      );
    },
  );
}

class _InvoiceFormSheet extends StatefulWidget {
  final Invoice? editInvoice;
  const _InvoiceFormSheet({this.editInvoice});

  @override
  State<_InvoiceFormSheet> createState() => _InvoiceFormSheetState();
}

// keep InvoiceFormScreen as alias for backward compat
class InvoiceFormScreen extends StatefulWidget {
  const InvoiceFormScreen({super.key});
  @override
  State<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}
class _InvoiceFormScreenState extends State<InvoiceFormScreen> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _InvoiceFormSheetState extends State<_InvoiceFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _customerCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  DateTime _invoiceDate = DateTime.now();

  // Inventory items list (sorted alphabetically)
  List<InventoryItem> _inventoryItems = [];

  // Item rows
  final List<_ItemRowController> _rows = [];

  @override
  void initState() {
    super.initState();
    _loadInventory();
    if (widget.editInvoice != null) {
      _populateFromInvoice(widget.editInvoice!);
    } else {
      _addRow(); // بدء بصف فارغ للفاتورة الجديدة
    }
  }

  // ── تعبئة الحقول من فاتورة موجودة ────────────────────────────────────────
  void _populateFromInvoice(Invoice inv) {
    _customerCtrl.text = inv.customerName;
    _notesCtrl.text = inv.notes;
    _discountCtrl.text =
        inv.discount > 0 ? inv.discount.toStringAsFixed(0) : '';
    _invoiceDate = inv.invoiceDate;

    // إنشاء صفوف المواد من عناصر الفاتورة
    _rows.clear();
    for (int i = 0; i < inv.items.length; i++) {
      final item = inv.items[i];
      final rowCtrl = _ItemRowController(sequence: i + 1);
      rowCtrl.qtyCtrl.text = item.quantity % 1 == 0
          ? item.quantity.toInt().toString()
          : item.quantity.toStringAsFixed(2);
      rowCtrl.priceCtrl.text = item.unitPrice % 1 == 0
          ? item.unitPrice.toInt().toString()
          : item.unitPrice.toStringAsFixed(2);
      // سيتم ربط selectedItem بعد تحميل المخزن
      rowCtrl.pendingItemName = item.itemName;
      _rows.add(rowCtrl);
    }
    if (_rows.isEmpty) _addRow();
  }

  void _loadInventory() async {
    final items = await DatabaseService.getAllInventoryItemsAsync();
    if (mounted) {
      setState(() {
        _inventoryItems = items;
        // ربط المواد بالـ selectedItem عند التعديل
        for (final row in _rows) {
          if (row.pendingItemName != null && row.selectedItem == null) {
            row.selectedItem = items.firstWhere(
              (it) => it.itemName == row.pendingItemName,
              orElse: () => InventoryItem(
                id: '',
                itemName: row.pendingItemName!,
                category: '',
                quantity: 0,
                unit: '',
                unitPrice: row.unitPrice,
                minStock: 0,
                lastUpdated: DateTime.now(),
              ),
            );
            row.pendingItemName = null;
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _customerCtrl.dispose();
    _notesCtrl.dispose();
    _discountCtrl.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    setState(() {
      _rows.add(_ItemRowController(sequence: _rows.length + 1));
    });
  }

  void _removeRow(int index) {
    if (_rows.length == 1) return; // keep at least one row
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
      // Re-sequence
      for (int i = 0; i < _rows.length; i++) {
        _rows[i].sequence = i + 1;
      }
    });
  }

  double get _subtotal => _rows.fold(0.0, (sum, r) => sum + r.lineTotal);
  double get _discountValue => double.tryParse(_discountCtrl.text) ?? 0;
  double get _grandTotal => (_subtotal - _discountValue).clamp(0, double.infinity);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme:
              const ColorScheme.light(primary: AppTheme.salesColor),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _invoiceDate = picked);
  }

  Future<void> _saveInvoice() async {
    if (!_formKey.currentState!.validate()) return;

    // التحقق من صفوف المواد
    for (int i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      if (r.selectedItem == null) {
        _showError('السطر ${i + 1}: يرجى اختيار مادة من المخزن');
        return;
      }
      if (r.quantity <= 0) {
        _showError('السطر ${i + 1}: يجب أن تكون الكمية أكبر من 0');
        return;
      }
      if (r.unitPrice <= 0) {
        _showError('السطر ${i + 1}: يجب أن يكون السعر أكبر من 0');
        return;
      }
      // التحقق من المخزون المتاح (فقط عند الإضافة، أو عند زيادة الكمية)
      final isEdit = widget.editInvoice != null;
      if (!isEdit && r.quantity > r.selectedItem!.quantity) {
        _showError(
            'السطر ${i + 1}: الكمية المتاحة لـ "${r.selectedItem!.itemName}" غير كافية.\n'
            'المتاح: ${r.selectedItem!.quantity.toStringAsFixed(0)} ${r.selectedItem!.unit}');
        return;
      }
    }

    final invoiceItems = _rows
        .asMap()
        .entries
        .map((e) => InvoiceItem(
              sequence: e.key + 1,
              itemName: e.value.selectedItem!.itemName,
              quantity: e.value.quantity,
              unitPrice: e.value.unitPrice,
              totalPrice: e.value.lineTotal,
            ))
        .toList();

    final isEdit = widget.editInvoice != null;

    final invoice = Invoice(
      id: isEdit ? widget.editInvoice!.id : const Uuid().v4(),
      invoiceNumber: isEdit
          ? widget.editInvoice!.invoiceNumber
          : DatabaseService.nextInvoiceNumber,
      customerName: _customerCtrl.text.trim(),
      invoiceDate: _invoiceDate,
      items: invoiceItems,
      notes: _notesCtrl.text.trim(),
      discount: _discountValue,
      totalAmount: _grandTotal,
    );

    String? error;
    if (isEdit) {
      // تحديث الفاتورة الموجودة مع تعديل المخزون
      error = await DatabaseService.updateInvoiceWithStockAdjustment(
          widget.editInvoice!, invoice);
    } else {
      // إنشاء فاتورة جديدة مع خصم من المخزون
      error = await DatabaseService.addInvoiceWithStockDeduction(invoice);
    }

    if (error != null) {
      if (!mounted) return;
      _showError(error);
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);
    await Future.microtask(() {});
    if (!mounted) return;
    final ctx = context;
    await Navigator.push(
      ctx,
      MaterialPageRoute(
          builder: (_) => InvoiceDetailScreen(invoice: invoice)),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppTheme.errorColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF5F7FA),
        ),
        child: Column(
          children: [
            // ── مقبض السحب ──────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),

            // ── رأس الشيت ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 14),
              decoration: const BoxDecoration(
                color: Color(0xFFF5F7FA),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppTheme.salesColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.receipt_long_rounded,
                        color: AppTheme.salesColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.editInvoice != null
                            ? 'تعديل الفاتورة'
                            : 'فاتورة جديدة',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark)),
                      Text(
                        widget.editInvoice != null
                            ? 'رقم الفاتورة: #${widget.editInvoice!.invoiceNumber.toString().padLeft(4, '0')}'
                            : 'رقم الفاتورة: #${DatabaseService.nextInvoiceNumber.toString().padLeft(4, '0')}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textGrey),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // زر إغلاق
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 20, color: AppTheme.textGrey),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE8EAF0)),

            // ── المحتوى القابل للتمرير ───────────────────────────────────
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(8, 16, 8,
                      mq.viewInsets.bottom + 100),
                  children: [

                    // ┌─ قسم: معلومات الفاتورة ──────────────────────────┐
                    _SheetSection(
                      title: 'معلومات الفاتورة',
                      icon: Icons.info_outline_rounded,
                      child: Column(
                        children: [
                          // اسم الزبون
                          _SheetField(
                            child: TextFormField(
                              controller: _customerCtrl,
                              decoration: _inputDeco(
                                  'اسم الزبون *',
                                  Icons.person_outline_rounded),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'اسم الزبون مطلوب'
                                      : null,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // تاريخ الفاتورة
                          _SheetField(
                            child: GestureDetector(
                              onTap: _pickDate,
                              child: AbsorbPointer(
                                child: TextFormField(
                                  decoration: _inputDeco(
                                          'تاريخ الفاتورة *',
                                          Icons.calendar_today_rounded)
                                      .copyWith(
                                    suffixIcon: const Icon(
                                        Icons.arrow_drop_down_rounded,
                                        color: AppTheme.salesColor),
                                  ),
                                  controller: TextEditingController(
                                    text: DateFormat('dd/MM/yyyy')
                                        .format(_invoiceDate),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ┌─ تحذير المخزن الفارغ ────────────────────────────┐
                    if (_inventoryItems.isEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Colors.orange.shade700, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'لا توجد مواد في المخزن. أضف مواد عبر المشتريات أولاً.',
                                style: TextStyle(
                                    color: Colors.orange.shade800,
                                    fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // ┌─ قسم: المواد ────────────────────────────────────┐
                    _SheetSection(
                      title: 'المواد',
                      icon: Icons.inventory_2_outlined,
                      trailing: Text(
                        '${_rows.length} ${_rows.length == 1 ? 'مادة' : 'مواد'}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textGrey),
                      ),
                      child: Column(
                        children: [
                          // رأس الأعمدة
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.salesColor.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              children: [
                                SizedBox(
                                  width: 26,
                                  child: Text('#',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: AppTheme.salesColor)),
                                ),
                                Expanded(
                                  flex: 5,
                                  child: Text('المادة (من المخزن)',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: AppTheme.salesColor)),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text('الكمية',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: AppTheme.salesColor)),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text('السعر',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: AppTheme.salesColor)),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text('الإجمالي',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: AppTheme.salesColor)),
                                ),
                                SizedBox(width: 28),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),

                          // صفوف المواد
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) => const Divider(
                                height: 1,
                                indent: 12,
                                endIndent: 12,
                                color: Color(0xFFE8EAF0)),
                            itemBuilder: (_, i) => _ItemRowWidget(
                              rowCtrl: _rows[i],
                              inventoryItems: _inventoryItems,
                              canDelete: _rows.length > 1,
                              onDelete: () => _removeRow(i),
                              onChanged: () => setState(() {}),
                            ),
                          ),

                          // زر إضافة صف
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: _inventoryItems.isEmpty ? null : _addRow,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: _inventoryItems.isEmpty
                                    ? Colors.grey.shade100
                                    : AppTheme.salesColor
                                        .withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _inventoryItems.isEmpty
                                      ? Colors.grey.shade300
                                      : AppTheme.salesColor
                                          .withValues(alpha: 0.3),
                                  style: BorderStyle.solid,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_circle_outline_rounded,
                                      color: _inventoryItems.isEmpty
                                          ? Colors.grey
                                          : AppTheme.salesColor,
                                      size: 18),
                                  const SizedBox(width: 6),
                                  Text('إضافة مادة',
                                      style: TextStyle(
                                          color: _inventoryItems.isEmpty
                                              ? Colors.grey
                                              : AppTheme.salesColor,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ┌─ قسم: ملاحظات ───────────────────────────────────┐
                    _SheetSection(
                      title: 'ملاحظات',
                      icon: Icons.note_outlined,
                      child: _SheetField(
                        child: TextFormField(
                          controller: _notesCtrl,
                          minLines: 2,
                          maxLines: 4,
                          decoration: _inputDeco(
                              'ملاحظات إضافية (اختياري)',
                              Icons.edit_note_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ┌─ قسم: الملخص والإجمالي ─────────────────────────┐
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2))
                        ],
                      ),
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        children: [
                          // رأس القسم
                          Row(
                            children: [
                              const Icon(Icons.calculate_outlined,
                                  color: AppTheme.salesColor, size: 18),
                              const SizedBox(width: 8),
                              const Text('الملخص',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: AppTheme.salesColor)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 12),

                          // المجموع الفرعي
                          _SummaryRow(
                            label: 'المجموع الفرعي',
                            value: CurrencyHelper.format(_subtotal),
                          ),
                          const SizedBox(height: 10),

                          // الخصم
                          Row(
                            children: [
                              const Icon(Icons.discount_outlined,
                                  size: 16, color: AppTheme.purchasesColor),
                              const SizedBox(width: 6),
                              const Text('الخصم',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.purchasesColor)),
                              const Spacer(),
                              SizedBox(
                                width: 120,
                                child: TextField(
                                  controller: _discountCtrl,
                                  onChanged: (_) => setState(() {}),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.purchasesColor,
                                      fontWeight: FontWeight.bold),
                                  decoration: InputDecoration(
                                    hintText: '0',
                                    isDense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 8),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: AppTheme.purchasesColor
                                                .withValues(alpha: 0.4))),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: AppTheme.purchasesColor,
                                            width: 1.5)),
                                    enabledBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: AppTheme.purchasesColor
                                                .withValues(alpha: 0.4))),
                                    prefixText: '- ',
                                    prefixStyle: const TextStyle(
                                        color: AppTheme.purchasesColor,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Divider(height: 1),
                          const SizedBox(height: 14),

                          // الإجمالي الكلي
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppTheme.salesColor,
                                  Color(0xFF43A047)
                                ],
                                begin: Alignment.centerRight,
                                end: Alignment.centerLeft,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.salesColor
                                      .withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text('الإجمالي الكلي',
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500)),
                                    SizedBox(height: 2),
                                    Text('بعد الخصم',
                                        style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12)),
                                  ],
                                ),
                                Text(
                                  CurrencyHelper.format(_grandTotal),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // ── شريط الحفظ الثابت ────────────────────────────────────────
            Container(
              padding: EdgeInsets.fromLTRB(8, 12, 8,
                  mq.viewInsets.bottom + mq.padding.bottom + 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // زر إلغاء
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('إلغاء',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: AppTheme.textGrey,
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // زر حفظ
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      onPressed: _saveInvoice,
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: Text(
                        widget.editInvoice != null
                            ? 'حفظ التعديل'
                            : 'حفظ وعرض الفاتورة',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: AppTheme.salesColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      prefixIcon: Icon(icon, color: AppTheme.salesColor, size: 22),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDDE1EA))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDDE1EA))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppTheme.salesColor, width: 2)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    );
  }
}

// ── مساعد: قسم داخل الشيت ────────────────────────────────────────────────────
class _SheetSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  const _SheetSection(
      {required this.title,
      required this.icon,
      required this.child,
      this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // رأس القسم
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.salesColor.withValues(alpha: 0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppTheme.salesColor, size: 17),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: AppTheme.salesColor)),
                if (trailing != null) ...[
                  const Spacer(),
                  trailing!,
                ],
              ],
            ),
          ),
          // المحتوى
          Padding(
            padding: const EdgeInsets.all(8),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ── حقل داخل الشيت ───────────────────────────────────────────────────────────
class _SheetField extends StatelessWidget {
  final Widget child;
  const _SheetField({required this.child});

  @override
  Widget build(BuildContext context) => child;
}

// ── صف ملخص ──────────────────────────────────────────────────────────────────
class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textGrey)),
        Text(value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
      ],
    );
  }
}

// ─── Item Row Controller ──────────────────────────────────────────────────────
class _ItemRowController {
  int sequence;
  InventoryItem? selectedItem;
  String? pendingItemName; // يُستخدم عند التعديل لربط الاسم بعد تحميل المخزن
  final TextEditingController qtyCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();

  _ItemRowController({required this.sequence});

  double get quantity => double.tryParse(qtyCtrl.text) ?? 0;
  double get unitPrice => double.tryParse(priceCtrl.text) ?? 0;
  double get lineTotal => quantity * unitPrice;

  void dispose() {
    qtyCtrl.dispose();
    priceCtrl.dispose();
  }
}

// ─── Item Row Widget ──────────────────────────────────────────────────────────
class _ItemRowWidget extends StatefulWidget {
  final _ItemRowController rowCtrl;
  final List<InventoryItem> inventoryItems;
  final bool canDelete;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  const _ItemRowWidget({
    required this.rowCtrl,
    required this.inventoryItems,
    required this.canDelete,
    required this.onDelete,
    required this.onChanged,
  });

  @override
  State<_ItemRowWidget> createState() => _ItemRowWidgetState();
}

class _ItemRowWidgetState extends State<_ItemRowWidget> {
  @override
  Widget build(BuildContext context) {
    final selectedItem = widget.rowCtrl.selectedItem;
    final mq = MediaQuery.of(context).size;
    // حجم حقل الإدخال يتناسب مع عرض الشاشة
    final fieldH   = mq.width < 360 ? 36.0 : (mq.width < 480 ? 40.0 : 44.0);
    final fontSize = mq.width < 360 ? 11.0 : 12.0;
    final labelFS  = mq.width < 360 ? 10.0 : 11.0;

    // ألوان مؤشر المخزون
    Color stockBg    = Colors.grey.shade50;
    Color stockBdr   = Colors.grey.shade200;
    Color stockColor = AppTheme.textGrey;
    IconData stockIcon = Icons.inventory_2_outlined;
    String stockQty  = '—';
    String? stockLabel;
    if (selectedItem != null) {
      if (selectedItem.quantity <= 0) {
        stockBg = Colors.red.shade50; stockBdr = Colors.red.shade300;
        stockColor = Colors.red.shade700; stockIcon = Icons.warning_amber_rounded;
        stockQty = '${selectedItem.quantity.toStringAsFixed(0)} ${selectedItem.unit}';
        stockLabel = 'نفذ!';
      } else if (selectedItem.isLowStock) {
        stockBg = Colors.orange.shade50; stockBdr = Colors.orange.shade300;
        stockColor = Colors.orange.shade700; stockIcon = Icons.warning_amber_outlined;
        stockQty = '${selectedItem.quantity.toStringAsFixed(0)} ${selectedItem.unit}';
        stockLabel = 'منخفض';
      } else {
        stockBg = Colors.green.shade50; stockBdr = Colors.green.shade300;
        stockColor = Colors.green.shade700; stockIcon = Icons.check_circle_outline;
        stockQty = '${selectedItem.quantity.toStringAsFixed(0)} ${selectedItem.unit}';
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDDE1EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── السطر الأول: رقم التسلسل + قائمة المادة + زر حذف ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // رقم التسلسل
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: AppTheme.salesColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${widget.rowCtrl.sequence}',
                  style: TextStyle(
                    fontSize: labelFS,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.salesColor,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // قائمة اختيار المادة
              Expanded(
                child: SizedBox(
                  height: fieldH + 2,
                  child: widget.inventoryItems.isEmpty
                      ? Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'لا توجد مواد في المخزن',
                            style: TextStyle(fontSize: fontSize, color: AppTheme.textGrey),
                          ),
                        )
                      : DropdownButtonFormField<InventoryItem>(
                          value: selectedItem,
                          isExpanded: true,
                          menuMaxHeight: 240,
                          decoration: InputDecoration(
                            hintText: 'اختر المادة من القائمة',
                            hintStyle: TextStyle(
                              fontSize: fontSize,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textGrey,
                            ),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: (fieldH - 20) / 2,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: AppTheme.divider),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: AppTheme.divider),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: AppTheme.salesColor, width: 2),
                            ),
                          ),
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                          items: widget.inventoryItems
                              .map((item) => DropdownMenuItem<InventoryItem>(
                                    value: item,
                                    child: Text(
                                      item.itemName,
                                      style: TextStyle(
                                        fontSize: fontSize,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ))
                              .toList(),
                          onChanged: (item) {
                            setState(() {
                              widget.rowCtrl.selectedItem = item;
                              if (item != null) {
                                widget.rowCtrl.priceCtrl.text =
                                    item.unitPrice.toStringAsFixed(0);
                              }
                            });
                            widget.onChanged();
                          },
                        ),
                ),
              ),
              const SizedBox(width: 4),
              // زر الحذف
              widget.canDelete
                  ? IconButton(
                      icon: const Icon(
                        Icons.remove_circle_outline_rounded,
                        color: AppTheme.errorColor,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: widget.onDelete,
                    )
                  : const SizedBox(width: 28),
            ],
          ),

          const SizedBox(height: 6),

          // ── السطر الثاني: الكمية | سعر المفرد | المخزون (متساوية) ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // حقل الكمية
              Expanded(
                flex: 3,
                child: _labeledField(
                  label: 'الكمية',
                  labelFS: labelFS,
                  child: _compactField(
                    widget.rowCtrl.qtyCtrl,
                    '0',
                    widget.onChanged,
                    number: true,
                    fieldH: fieldH,
                    fontSize: fontSize,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // حقل سعر المفرد
              Expanded(
                flex: 4,
                child: _labeledField(
                  label: 'سعر المفرد',
                  labelFS: labelFS,
                  child: _compactField(
                    widget.rowCtrl.priceCtrl,
                    '0',
                    widget.onChanged,
                    number: true,
                    fieldH: fieldH,
                    fontSize: fontSize,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // مؤشر المخزون
              Expanded(
                flex: 4,
                child: _labeledField(
                  label: 'المخزون',
                  labelFS: labelFS,
                  child: Container(
                    height: fieldH,
                    width: double.infinity,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: stockBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: stockBdr),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(stockIcon, size: 11, color: stockColor),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                stockQty,
                                style: TextStyle(
                                  fontSize: labelFS,
                                  fontWeight: FontWeight.w700,
                                  color: stockColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                        if (stockLabel != null)
                          Text(
                            stockLabel,
                            style: TextStyle(
                              fontSize: labelFS - 1,
                              fontWeight: FontWeight.bold,
                              color: stockColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // ── السطر الثالث: الإجمالي ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.salesColor.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'الإجمالي:',
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textGrey,
                  ),
                ),
                Text(
                  CurrencyHelper.format(widget.rowCtrl.lineTotal),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: fontSize + 1,
                    color: AppTheme.salesColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// مساعد: عنوان + حقل بالاسفل
  Widget _labeledField({
    required String label,
    required double labelFS,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: labelFS,
            fontWeight: FontWeight.w600,
            color: AppTheme.textGrey,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 3),
        child,
      ],
    );
  }

  /// حقل إدخال مضغوط متجاوب مع حجم الشاشة
  Widget _compactField(
    TextEditingController ctrl,
    String hint,
    VoidCallback onChange, {
    bool number = false,
    required double fieldH,
    required double fontSize,
  }) {
    final vPad = ((fieldH - fontSize - 8) / 2).clamp(6.0, 14.0);
    return SizedBox(
      height: fieldH,
      child: TextField(
        controller: ctrl,
        onChanged: (_) => onChange(),
        keyboardType:
            number ? const TextInputType.numberWithOptions(decimal: true) : null,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            color: AppTheme.textGrey,
          ),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: vPad),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.salesColor, width: 2),
          ),
        ),
      ),
    );
  }
}

