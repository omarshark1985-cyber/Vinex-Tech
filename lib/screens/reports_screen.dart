import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import '../utils/currency_helper.dart';
import '../utils/responsive.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  double _totalSales = 0;
  double _totalPurchases = 0;
  double _inventoryValue = 0;
  // ignore: unused_field
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadStats();
  }

  Future<void> _loadStats() async {
    final s = await DatabaseService.getTotalSalesAsync();
    final p = await DatabaseService.getTotalPurchasesAsync();
    final iv = await DatabaseService.getTotalInventoryValueAsync();
    if (mounted) {
      setState(() {
        _totalSales = s;
        _totalPurchases = p;
        _inventoryValue = iv;
        _loaded = true;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalSales = _totalSales;
    final totalPurchases = _totalPurchases;
    final inventoryValue = _inventoryValue;
    final profit = totalSales - totalPurchases;
    final profitMargin =
        totalSales > 0 ? (profit / totalSales * 100) : 0.0;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.reportsColor,
        title: const Text('Reports & Analytics'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.dashboard_rounded)),
            Tab(text: 'Sales', icon: Icon(Icons.trending_up_rounded)),
            Tab(text: 'Purchases', icon: Icon(Icons.shopping_cart_rounded)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ─── Overview Tab ──────────────────────────────────────────────
          _OverviewTab(
            totalSales: totalSales,
            totalPurchases: totalPurchases,
            inventoryValue: inventoryValue,
            profit: profit,
            profitMargin: profitMargin.toDouble(),
          ),
          // ─── Sales Tab ─────────────────────────────────────────────────
          _SalesReportTab(),
          // ─── Purchases Tab ─────────────────────────────────────────────
          _PurchasesReportTab(),
        ],
      ),
    );
  }
}

// ─── Overview Tab ─────────────────────────────────────────────────────────────
class _OverviewTab extends StatelessWidget {
  final double totalSales;
  final double totalPurchases;
  final double inventoryValue;
  final double profit;
  final double profitMargin;

  const _OverviewTab({
    required this.totalSales,
    required this.totalPurchases,
    required this.inventoryValue,
    required this.profit,
    required this.profitMargin,
  });

  @override
  Widget build(BuildContext context) {
    final r = R.of(context);
    return FutureBuilder<Map<String, int>>(
      future: _loadCounts(),
      builder: (context, snapshot) {
        final salesCount = snapshot.data?['sales'] ?? 0;
        final purchasesCount = snapshot.data?['purchases'] ?? 0;
        final inventoryCount = snapshot.data?['inventory'] ?? 0;
        final lowStockCount = snapshot.data?['lowStock'] ?? 0;
    return SingleChildScrollView(
      padding: EdgeInsets.all(r.hPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Financial Summary',
              style: TextStyle(
                  fontSize: r.fs18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark)),
          SizedBox(height: r.gap),

          // KPI Cards Row 1
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'Total Revenue',
                  value: CurrencyHelper.format(totalSales),
                  icon: Icons.trending_up_rounded,
                  color: AppTheme.salesColor,
                  subtitle: '$salesCount transactions',
                ),
              ),
              SizedBox(width: r.gap),
              Expanded(
                child: _KpiCard(
                  title: 'Total Expenses',
                  value: CurrencyHelper.format(totalPurchases),
                  icon: Icons.trending_down_rounded,
                  color: AppTheme.purchasesColor,
                  subtitle: '$purchasesCount orders',
                ),
              ),
            ],
          ),
          SizedBox(height: r.gap),

          // KPI Cards Row 2
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'Net Profit',
                  value: CurrencyHelper.format(profit),
                  icon: profit >= 0
                      ? Icons.account_balance_wallet_rounded
                      : Icons.money_off_rounded,
                  color: profit >= 0
                      ? AppTheme.salesColor
                      : AppTheme.errorColor,
                  subtitle:
                      '${profitMargin.toStringAsFixed(1)}% margin',
                ),
              ),
              SizedBox(width: r.gap),
              Expanded(
                child: _KpiCard(
                  title: 'Stock Value',
                  value: CurrencyHelper.format(inventoryValue),
                  icon: Icons.inventory_2_rounded,
                  color: AppTheme.inventoryColor,
                  subtitle: '$inventoryCount items',
                ),
              ),
            ],
          ),
          SizedBox(height: r.gapL),

          // Profit Breakdown
          Text('Profit Analysis',
              style: TextStyle(
                  fontSize: r.fs18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark)),
          SizedBox(height: r.gap),
          Container(
            padding: EdgeInsets.all(r.cardPad),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 2))
              ],
            ),
            child: Column(
              children: [
                _ProgressRow(
                  label: 'Revenue',
                  value: totalSales,
                  max: totalSales > 0 ? totalSales : 1,
                  color: AppTheme.salesColor,
                ),
                const SizedBox(height: 14),
                _ProgressRow(
                  label: 'Expenses',
                  value: totalPurchases,
                  max: totalSales > 0 ? totalSales : 1,
                  color: AppTheme.purchasesColor,
                ),
                const SizedBox(height: 14),
                _ProgressRow(
                  label: 'Profit',
                  value: profit.clamp(0, double.infinity),
                  max: totalSales > 0 ? totalSales : 1,
                  color:
                      profit >= 0 ? AppTheme.salesColor : AppTheme.errorColor,
                ),
                if (totalSales > 0) ...[
                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Profit Margin:',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: (profitMargin >= 0
                                  ? AppTheme.salesColor
                                  : AppTheme.errorColor)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${profitMargin.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: profitMargin >= 0
                                ? AppTheme.salesColor
                                : AppTheme.errorColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: r.gapL),

          // Stock Status
          Text('Storage Status',
              style: TextStyle(
                  fontSize: r.fs18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark)),
          SizedBox(height: r.gap),
          Row(
            children: [
              Expanded(
                child: _StatusCard(
                  label: 'Total Items',
                  value: '$inventoryCount',
                  icon: Icons.inventory_rounded,
                  color: AppTheme.inventoryColor,
                ),
              ),
              SizedBox(width: r.gap),
              Expanded(
                child: _StatusCard(
                  label: 'Low Stock',
                  value: '$lowStockCount',
                  icon: Icons.warning_amber_rounded,
                  color: lowStockCount > 0
                      ? AppTheme.warningColor
                      : AppTheme.salesColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
      },
    );
  }

  Future<Map<String, int>> _loadCounts() async {
    final inv = await DatabaseService.getAllInvoicesAsync();
    final pur = await DatabaseService.getAllPurchasesAsync();
    final items = await DatabaseService.getAllInventoryItemsAsync();
    final low = items.where((i) => i.isLowStock).length;
    return {
      'sales': inv.length,
      'purchases': pur.length,
      'inventory': items.length,
      'lowStock': low,
    };
  }
}

// ─── Sales Report Tab
class _SalesReportTab extends StatefulWidget {
  @override
  State<_SalesReportTab> createState() => _SalesReportTabState();
}

class _SalesReportTabState extends State<_SalesReportTab> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: DatabaseService.getAllInvoicesAsync(),
      builder: (context, snapshot) {
        final invoices = snapshot.data ?? [];
        if (invoices.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_rounded,
                size: 64, color: AppTheme.textGrey),
            SizedBox(height: 16),
            Text('No sales data available',
                style:
                    TextStyle(color: AppTheme.textGrey, fontSize: 16)),
          ],
        ),
      );
    }

    // Top items from invoice lines
    final Map<String, double> itemTotals = {};
    for (final inv in invoices) {
      for (final item in inv.items) {
        itemTotals[item.itemName] =
            (itemTotals[item.itemName] ?? 0) + item.totalPrice;
      }
    }
    final sortedItems = itemTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // ── حساب إجماليات الخصومات ───────────────────────────────
    final totalDiscount = invoices.fold<double>(0, (s, inv) => s + inv.discount);
    final totalSubtotal = invoices.fold<double>(0, (s, inv) => s + inv.subtotal);
    final totalNet      = invoices.fold<double>(0, (s, inv) => s + inv.totalAmount);
    final discountedCount = invoices.where((inv) => inv.discount > 0).length;

    final r = R.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(r.hPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── بطاقة ملخص الخصوم ──────────────────────────────────────
          if (totalDiscount > 0) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFCC02).withValues(alpha: 0.5)),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE65100).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.discount_outlined,
                            color: Color(0xFFE65100), size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Text('Discounts Summary',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFBF360C))),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _DiscountStatBox(
                          label: 'Total Subtotal',
                          value: CurrencyHelper.format(totalSubtotal),
                          icon: Icons.receipt_outlined,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DiscountStatBox(
                          label: 'Total Discounts',
                          value: '- ${CurrencyHelper.format(totalDiscount)}',
                          icon: Icons.remove_circle_outline_rounded,
                          color: const Color(0xFFE65100),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DiscountStatBox(
                          label: 'Net Revenue',
                          value: CurrencyHelper.format(totalNet),
                          icon: Icons.account_balance_wallet_outlined,
                          color: AppTheme.salesColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE65100).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 13, color: Color(0xFFE65100)),
                        const SizedBox(width: 6),
                        Text(
                          '$discountedCount invoice(s) had discounts applied',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFE65100),
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          Text('Top Selling Items',
              style: TextStyle(
                  fontSize: r.fs18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark)),
          SizedBox(height: r.gap),
          ...sortedItems.take(10).map((entry) {
            final maxVal = sortedItems.first.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 1))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(entry.key,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: r.fs16)),
                        ),
                        Text(
                          CurrencyHelper.format(entry.value),
                          style: TextStyle(
                              color: AppTheme.salesColor,
                              fontWeight: FontWeight.bold,
                              fontSize: r.fs16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: maxVal > 0 ? entry.value / maxVal : 0,
                        backgroundColor:
                            AppTheme.salesColor.withValues(alpha: 0.1),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            AppTheme.salesColor),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          SizedBox(height: r.gapL),
          Text('Recent Invoices',
              style: TextStyle(
                  fontSize: r.fs18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark)),
          SizedBox(height: r.gap),
          ...invoices.take(15).map((inv) => _InvoiceReportRow(invoice: inv)),
        ],
      ),
    );
      }, // end FutureBuilder
    );
  }
}

// ─── Purchases Report Tab ──────────────────────────────────────────────────────
class _PurchasesReportTab extends StatefulWidget {
  @override
  State<_PurchasesReportTab> createState() => _PurchasesReportTabState();
}

class _PurchasesReportTabState extends State<_PurchasesReportTab> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: DatabaseService.getAllPurchasesAsync(),
      builder: (context, snapshot) {
        final purchases = snapshot.data ?? [];
        if (purchases.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_rounded,
                size: 64, color: AppTheme.textGrey),
            SizedBox(height: 16),
            Text('No purchase data available',
                style:
                    TextStyle(color: AppTheme.textGrey, fontSize: 16)),
          ],
        ),
      );
    }

    final Map<String, double> itemTotals = {};
    for (final p in purchases) {
      itemTotals[p.itemName] =
          (itemTotals[p.itemName] ?? 0) + p.totalPrice;
    }
    final sortedItems = itemTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Supplier stats
    final Map<String, double> supplierTotals = {};
    for (final p in purchases) {
      supplierTotals[p.supplierName] =
          (supplierTotals[p.supplierName] ?? 0) + p.totalPrice;
    }
    final sortedSuppliers = supplierTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final r = R.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(r.hPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top Purchased Items',
              style: TextStyle(
                  fontSize: r.fs18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark)),
          SizedBox(height: r.gap),
          ...sortedItems.take(10).map((entry) {
            final maxVal = sortedItems.first.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 1))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(entry.key,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: r.fs16)),
                        ),
                        Text(CurrencyHelper.format(entry.value),
                            style: TextStyle(
                                color: AppTheme.purchasesColor,
                                fontWeight: FontWeight.bold,
                                fontSize: r.fs16)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: maxVal > 0 ? entry.value / maxVal : 0,
                        backgroundColor:
                            AppTheme.purchasesColor.withValues(alpha: 0.1),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            AppTheme.purchasesColor),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          SizedBox(height: r.gapL),
          Text('Top Suppliers',
              style: TextStyle(
                  fontSize: r.fs18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark)),
          SizedBox(height: r.gap),
          ...sortedSuppliers.take(5).map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black12,
                            blurRadius: 4,
                            offset: Offset(0, 1))
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.purchasesColor
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.store_rounded,
                              color: AppTheme.purchasesColor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(entry.key,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                        Text(CurrencyHelper.format(entry.value),
                            style: const TextStyle(
                                color: AppTheme.purchasesColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                      ],
                    ),
                  ),
                ),
              ),
          SizedBox(height: r.gapL),
          Text('Recent Purchases',
              style: TextStyle(
                  fontSize: r.fs18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark)),
          SizedBox(height: r.gap),
          ...purchases.take(15).map((p) => _TransactionRow(
                title: p.itemName,
                subtitle: 'Supplier: ${p.supplierName}',
                amount: CurrencyHelper.format(p.totalPrice),
                date: DateFormat('MMM dd, yyyy').format(p.date),
                color: AppTheme.purchasesColor,
                icon: Icons.shopping_cart_rounded,
              )),
        ],
      ),
    );
      }, // end FutureBuilder
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────
class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String subtitle;
  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final r = R.of(context);
    return Container(
      padding: EdgeInsets.all(r.cardPad),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: r.iconSm + 2),
              ),
              const Spacer(),
            ],
          ),
          SizedBox(height: r.gap),
          Text(value,
              style: TextStyle(
                  fontSize: r.fs18,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(height: 2),
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: r.fs13,
                  color: AppTheme.textDark)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: TextStyle(
                  color: AppTheme.textGrey, fontSize: r.fs12)),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatusCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final r = R.of(context);
    return Container(
      padding: EdgeInsets.all(r.cardPad),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: r.iconMd),
          ),
          SizedBox(width: r.gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        fontSize: r.fs20,
                        fontWeight: FontWeight.bold,
                        color: color)),
                Text(label,
                    style: TextStyle(
                        color: AppTheme.textGrey, fontSize: r.fs13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final Color color;
  const _ProgressRow(
      {required this.label,
      required this.value,
      required this.max,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 13)),
            Text(CurrencyHelper.format(value),
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: max > 0 ? (value / max).clamp(0.0, 1.0) : 0,
            backgroundColor: color.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}

// ── بطاقة فاتورة في التقرير (تعرض الخصم عند وجوده) ──────────────────────────
class _InvoiceReportRow extends StatelessWidget {
  final dynamic invoice;
  const _InvoiceReportRow({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final r = R.of(context);
    final hasDiscount = invoice.discount > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(r.cardPad - 4),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: hasDiscount
            ? Border.all(color: const Color(0xFFE65100).withValues(alpha: 0.25))
            : null,
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: r.isMobile ? 32 : 38,
            height: r.isMobile ? 32 : 38,
            decoration: BoxDecoration(
              color: AppTheme.salesColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.receipt_long_rounded,
                color: AppTheme.salesColor, size: r.iconSm + 2),
          ),
          SizedBox(width: r.gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Invoice #${invoice.invoiceNumber.toString().padLeft(4, '0')}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: r.fs16),
                ),
                const SizedBox(height: 2),
                Text(
                  'Customer: ${invoice.customerName}  •  ${invoice.items.length} items',
                  style: TextStyle(
                      color: AppTheme.textGrey, fontSize: r.fs14),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('MMM dd, yyyy').format(invoice.invoiceDate),
                  style: TextStyle(
                      color: AppTheme.textGrey, fontSize: r.fs13),
                ),
                // ── صف الخصم (يظهر فقط عند وجود خصم) ────────────────
                if (hasDiscount) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE65100).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.discount_outlined,
                                size: 11, color: Color(0xFFE65100)),
                            const SizedBox(width: 4),
                            Text(
                              'Discount: - ${CurrencyHelper.format(invoice.discount)}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFE65100),
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(Before: ${CurrencyHelper.format(invoice.subtotal)})',
                        style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textGrey,
                            decoration: TextDecoration.lineThrough),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // ── المبلغ النهائي ───────────────────────────────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                CurrencyHelper.format(invoice.totalAmount),
                style: TextStyle(
                    color: AppTheme.salesColor,
                    fontWeight: FontWeight.bold,
                    fontSize: r.fs16),
              ),
              if (hasDiscount)
                Text('after discount',
                    style: TextStyle(
                        fontSize: r.fs13, color: AppTheme.textGrey)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── صندوق إحصاء الخصم الصغير ─────────────────────────────────────────────────
class _DiscountStatBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _DiscountStatBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(height: 5),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppTheme.textGrey)),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String amount;
  final String date;
  final Color color;
  final IconData icon;
  const _TransactionRow({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.date,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final r = R.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(r.cardPad - 4),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: r.isMobile ? 32 : 36,
            height: r.isMobile ? 32 : 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: r.iconSm + 2),
          ),
          SizedBox(width: r.gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: r.fs16)),
                Text(subtitle,
                    style: TextStyle(
                        color: AppTheme.textGrey, fontSize: r.fs14)),
                Text(date,
                    style: TextStyle(
                        color: AppTheme.textGrey, fontSize: r.fs13)),
              ],
            ),
          ),
          Text(amount,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: r.fs16)),
        ],
      ),
    );
  }
}
