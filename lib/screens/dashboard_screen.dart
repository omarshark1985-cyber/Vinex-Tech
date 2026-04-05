import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../models/invoice_model.dart';
import '../models/purchase_model.dart';
import '../models/inventory_model.dart';
import '../models/user_model.dart';
import 'sales_screen.dart';
import 'purchases_screen.dart';
import 'inventory_screen.dart';
import 'reports_screen.dart';
import 'admin_screen.dart';
import 'login_screen.dart';
import '../utils/currency_helper.dart';
import '../utils/responsive.dart';
import '../main.dart' show routeObserver;

class DashboardScreen extends StatefulWidget {
  final AppUser currentUser;
  const DashboardScreen({super.key, required this.currentUser});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with RouteAware {
  double _totalSales = 0;
  double _totalPurchases = 0;
  double _inventoryValue = 0;
  int _lowStockCount = 0;
  bool _firebaseConnected = false;
  StreamSubscription<bool>? _connSub;
  Timer? _connTimer;
  StreamSubscription<List<Invoice>>? _invoicesSub;
  StreamSubscription<List<Purchase>>? _purchasesSub;
  StreamSubscription<List<InventoryItem>>? _inventorySub;

  @override
  void initState() {
    super.initState();
    _firebaseConnected = DatabaseService.isFirebaseConnected;

    // Always update when connection state changes (no guard condition)
    _connSub = DatabaseService.connectionStream.listen((connected) {
      if (mounted) setState(() => _firebaseConnected = connected);
    });

    // Polling every 1 second as an extra safety net
    _connTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = DatabaseService.isFirebaseConnected;
      if (mounted && current != _firebaseConnected) {
        setState(() => _firebaseConnected = current);
      }
    });

    _subscribeToStreams();
    _loadStats();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  /// Refresh stats when returning from sub-screens (Inventory, Sales, Purchases)
  @override
  void didPopNext() {
    _recalcFromCache();           // instant update from cache
    DatabaseService.refreshData(); // then pull fresh from Firebase → streams update UI again
  }

  void _subscribeToStreams() {
    // Invoices stream → recalculate total sales
    _invoicesSub = DatabaseService.invoicesStream.listen((invoices) {
      if (mounted) {
        setState(() {
          _totalSales = invoices.fold(0.0, (s, inv) => s + inv.totalAmount);
          _firebaseConnected = DatabaseService.isFirebaseConnected;
        });
      }
    });

    // Purchases stream → recalculate total purchases
    _purchasesSub = DatabaseService.purchasesStream.listen((purchases) {
      if (mounted) {
        setState(() {
          _totalPurchases = purchases.fold(0.0, (s, p) => s + p.totalPrice);
          _firebaseConnected = DatabaseService.isFirebaseConnected;
        });
      }
    });

    // Inventory stream → recalculate stock value and low stock count
    _inventorySub = DatabaseService.inventoryStream.listen((items) {
      if (mounted) {
        setState(() {
          _inventoryValue = items.fold(0.0, (s, i) => s + i.totalValue);
          _lowStockCount = items.where((i) => i.isLowStock).length;
          _firebaseConnected = DatabaseService.isFirebaseConnected;
        });
      }
    });
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _connSub?.cancel();
    _connTimer?.cancel();
    _invoicesSub?.cancel();
    _purchasesSub?.cancel();
    _inventorySub?.cancel();
    super.dispose();
  }

  Future<void> _loadStats() async {
    // Use cached stream data first for immediate display (no network wait)
    _recalcFromCache();
    // Then trigger a fresh Firebase pull (results come back via streams)
    await DatabaseService.refreshData();
  }

  /// Recalculate totals from the in-memory stream caches — instant, no I/O.
  void _recalcFromCache() {
    final invoices  = DatabaseService.lastInvoices;
    final purchases = DatabaseService.lastPurchases;
    final inventory = DatabaseService.lastInventory;
    if (mounted) {
      setState(() {
        _totalSales      = invoices.fold(0.0, (s, inv) => s + inv.totalAmount);
        _totalPurchases  = purchases.fold(0.0, (s, p)   => s + p.totalPrice);
        _inventoryValue  = inventory.fold(0.0, (s, i)   => s + i.totalValue);
        _lowStockCount   = inventory.where((i) => i.isLowStock).length;
        _firebaseConnected = DatabaseService.isFirebaseConnected;
      });
    }
  }

  void _logout() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LogoutDialog(
          onConfirmed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalSales = _totalSales;
    final totalPurchases = _totalPurchases;
    final inventoryValue = _inventoryValue;
    final lowStockCount = _lowStockCount;

    final user = widget.currentUser;

    // Build menu items based on user permissions
    final menuItems = <_MenuItem>[
      if (user.isAdmin || user.canViewSales)
        _MenuItem(
          title: 'Sales',
          subtitle: 'Manage transactions',
          icon: Icons.point_of_sale_rounded,
          color: AppTheme.salesColor,
          gradient: const LinearGradient(
            colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          screen: const SalesScreen(),
          statLabel: 'Total Sales',
          statValue: CurrencyHelper.format(totalSales),
        ),
      if (user.isAdmin || user.canViewPurchases)
        _MenuItem(
          title: 'Purchases',
          subtitle: 'Track procurement',
          icon: Icons.shopping_cart_rounded,
          color: AppTheme.purchasesColor,
          gradient: const LinearGradient(
            colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          screen: const PurchasesScreen(),
          statLabel: 'Total Purchases',
          statValue: CurrencyHelper.format(totalPurchases),
        ),
      if (user.isAdmin || user.canViewInventory)
        _MenuItem(
          title: 'Storage',
          subtitle: 'Stock management',
          icon: Icons.inventory_2_rounded,
          color: AppTheme.inventoryColor,
          gradient: const LinearGradient(
            colors: [Color(0xFF0277BD), Color(0xFF0288D1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          screen: const InventoryScreen(),
          statLabel: 'Stock Value',
          statValue: CurrencyHelper.format(inventoryValue),
        ),
      if (user.isAdmin || user.canViewReports)
        _MenuItem(
          title: 'Reports',
          subtitle: 'Analytics & insights',
          icon: Icons.bar_chart_rounded,
          color: AppTheme.reportsColor,
          gradient: const LinearGradient(
            colors: [Color(0xFFE65100), Color(0xFFF57C00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          screen: const ReportsScreen(),
          statLabel: 'Net Profit',
          statValue: CurrencyHelper.format(totalSales - totalPurchases),
        ),
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/company_logo.png',
              width: 36,
              height: 36,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.inventory_2_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Vinex Technology'),
          ],
        ),
        actions: [
          // Admin panel button — visible only for admin role
          if (widget.currentUser.isAdmin)
            Tooltip(
              message: 'إدارة المستخدمين',
              child: IconButton(
                icon: const Icon(Icons.admin_panel_settings_rounded),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AdminScreen(currentUser: widget.currentUser)),
                ),
              ),
            ),
          // Firebase connection indicator
          Tooltip(
            message: _firebaseConnected
                ? 'Connected to cloud — data is synced'
                : 'Offline — local data only',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Icon(
                  key: ValueKey(_firebaseConnected),
                  _firebaseConnected
                      ? Icons.cloud_done_rounded
                      : Icons.cloud_off_rounded,
                  color: _firebaseConnected
                      ? const Color(0xFF00E676)
                      : Colors.white38,
                  size: 24,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final r = R.of(context);
          final gridColumns = r.gridCols;
          final gridAspect = r.cardAspect;
          final hPadding = r.hPad;

          return SingleChildScrollView(
            padding: EdgeInsets.all(hPadding),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ─── Welcome Banner ───────────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(r.cardPad),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            AppTheme.primaryBlue,
                            AppTheme.primaryBlueLight
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(r.isMobile ? 10 : 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.waving_hand_rounded,
                                color: Colors.white,
                                size: r.iconLg),
                          ),
                          SizedBox(width: r.gap),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Hello, ${widget.currentUser.displayName.isNotEmpty ? widget.currentUser.displayName : widget.currentUser.username}!',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: r.fs20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Welcome to your storage dashboard',
                                  style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: r.fs13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: r.gapL),

                    // ─── Low stock alert ──────────────────────────────────
                    if (lowStockCount > 0) ...[
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: r.hPad, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.warningColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppTheme.warningColor
                                  .withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: AppTheme.warningColor, size: r.iconMd),
                            SizedBox(width: r.gapS + 2),
                            Expanded(
                              child: Text(
                                '$lowStockCount item(s) are running low on stock!',
                                style: TextStyle(
                                  color: const Color(0xFF7B5800),
                                  fontWeight: FontWeight.w500,
                                  fontSize: r.fs14,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const InventoryScreen()),
                              ).then((_) => setState(() {})),
                              child: Text('View',
                                  style: TextStyle(
                                      color: AppTheme.warningColor,
                                      fontSize: r.fs14)),
                            )
                          ],
                        ),
                      ),
                      SizedBox(height: r.gap),
                    ],

                    Text(
                      'Main Menu',
                      style: TextStyle(
                        fontSize: r.fs18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    SizedBox(height: r.gap),

                    // ─── Menu Cards Grid ──────────────────────────────────
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: gridColumns,
                        crossAxisSpacing: r.gap,
                        mainAxisSpacing: r.gap,
                        childAspectRatio: gridAspect,
                      ),
                      itemCount: menuItems.length,
                      itemBuilder: (context, index) {
                        final item = menuItems[index];
                        return _MenuCard(
                          item: item,
                          r: r,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => item.screen),
                          ).then((_) => setState(() {})),
                        );
                      },
                    ),

                    SizedBox(height: r.gapL),

                    // ─── Quick Summary ────────────────────────────────────
                    Text(
                      'Quick Summary',
                      style: TextStyle(
                        fontSize: r.fs18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    SizedBox(height: r.gap),
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryTile(
                            label: 'Total Sales',
                            value: CurrencyHelper.format(totalSales),
                            icon: Icons.trending_up_rounded,
                            color: AppTheme.salesColor,
                            r: r,
                          ),
                        ),
                        SizedBox(width: r.gap),
                        Expanded(
                          child: _SummaryTile(
                            label: 'Net Profit',
                            value: CurrencyHelper.format(
                                totalSales - totalPurchases),
                            icon: Icons.account_balance_wallet_rounded,
                            color: totalSales >= totalPurchases
                                ? AppTheme.salesColor
                                : AppTheme.errorColor,
                            r: r,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: r.gapL),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Menu Item Data ──────────────────────────────────────────────────────────
class _MenuItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Gradient gradient;
  final Widget screen;
  final String statLabel;
  final String statValue;

  _MenuItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.gradient,
    required this.screen,
    required this.statLabel,
    required this.statValue,
  });
}

// ─── Menu Card Widget ────────────────────────────────────────────────────────
class _MenuCard extends StatelessWidget {
  final _MenuItem item;
  final VoidCallback onTap;
  final R r;
  const _MenuCard({required this.item, required this.onTap, required this.r});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: item.gradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: item.color.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(r.cardPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(item.icon, color: Colors.white, size: r.iconLg),
                ),
                const Spacer(),
                Text(
                  item.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: r.fs17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: r.gapS),
                Text(
                  item.subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: r.fs13,
                  ),
                ),
                SizedBox(height: r.gapS + 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    item.statValue,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: r.fs13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Summary Tile Widget ─────────────────────────────────────────────────────
class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final R r;
  const _SummaryTile(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color,
      required this.r});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(r.cardPad),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: r.iconMd + 2),
          SizedBox(height: r.gapS),
          Text(value,
              style: TextStyle(
                  fontSize: r.fs18,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: r.fs13, color: AppTheme.textGrey)),
        ],
      ),
    );
  }
}

// ── شاشة تأكيد تسجيل الخروج الأصيلة ─────────────────────────────────────────
class _LogoutDialog extends StatelessWidget {
  final VoidCallback onConfirmed;
  const _LogoutDialog({required this.onConfirmed});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: EdgeInsets.zero,
      title: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.errorColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('تسجيل الخروج', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
          ],
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.errorColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.25)),
        ),
        child: const Row(
          children: [
            Icon(Icons.logout_rounded, color: AppTheme.errorColor, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'هل أنت متأكد من تسجيل الخروج؟',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('إلغاء', style: TextStyle(fontWeight: FontWeight.bold)),
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
                onPressed: () {
                  Navigator.pop(context);
                  onConfirmed();
                },
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('تسجيل الخروج', style: TextStyle(fontWeight: FontWeight.bold)),
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
