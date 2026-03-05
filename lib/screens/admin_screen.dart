import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Admin Management Screen — visible only when logged in as 'admin'
// ─────────────────────────────────────────────────────────────────────────────
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<AppUser> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    final users = await DatabaseService.getAllUsers();
    setState(() {
      _users = users;
      _loading = false;
    });
  }

  // ── Open add/edit dialog ──────────────────────────────────────────────────
  void _openUserDialog({AppUser? existing}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UserDialog(
        existing: existing,
        onSaved: (user) async {
          await DatabaseService.saveUser(user);
          await _loadUsers();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(existing == null
                  ? '✅ تم إنشاء المستخدم "${user.username}" بنجاح'
                  : '✅ تم تحديث المستخدم "${user.username}" بنجاح'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ));
          }
        },
        isNew: existing == null,
      ),
    );
  }

  // ── Confirm delete ────────────────────────────────────────────────────────
  void _confirmDelete(AppUser user) {
    if (user.username == 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('⛔ لا يمكن حذف حساب المدير الرئيسي'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.person_remove_rounded, color: Colors.red, size: 22),
              ),
              const SizedBox(width: 10),
              const Text('حذف المستخدم', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.red)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(),
              const SizedBox(height: 8),
              Text('هل أنت متأكد من حذف المستخدم؟', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _InfoChip(icon: Icons.person_outline, label: user.username),
              if (user.displayName.isNotEmpty)
                _InfoChip(icon: Icons.badge_outlined, label: user.displayName),
              const SizedBox(height: 12),
              const Text('لا يمكن التراجع عن هذا الإجراء.', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('لا، تراجع'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await DatabaseService.deleteUser(user.username);
                        await _loadUsers();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('🗑 تم حذف المستخدم "${user.username}"'),
                            backgroundColor: Colors.red,
                          ));
                        }
                      },
                      icon: const Icon(Icons.delete_forever_rounded, size: 18),
                      label: const Text('نعم، احذف'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: const Color(0xFF37474F),
          foregroundColor: Colors.white,
          title: const Row(
            children: [
              Icon(Icons.admin_panel_settings_rounded, size: 22),
              SizedBox(width: 10),
              Text('إدارة المستخدمين', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'تحديث',
              onPressed: _loadUsers,
            ),
            const SizedBox(width: 4),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openUserDialog(),
          backgroundColor: AppTheme.primaryBlue,
          icon: const Icon(Icons.person_add_rounded, color: Colors.white),
          label: const Text('مستخدم جديد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _users.isEmpty
                ? _buildEmpty()
                : _buildList(),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.group_off_rounded, size: 72, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('لا يوجد مستخدمون', style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('اضغط + لإضافة مستخدم جديد', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildList() {
    return Column(
      children: [
        // Header banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          color: const Color(0xFF37474F),
          child: Row(
            children: [
              const Icon(Icons.people_rounded, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Text(
                '${_users.length} مستخدم مسجل في النظام',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
        // Users list
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadUsers,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _users.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _UserCard(
                user: _users[i],
                onEdit: () => _openUserDialog(existing: _users[i]),
                onDelete: () => _confirmDelete(_users[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// User Card
// ─────────────────────────────────────────────────────────────────────────────
class _UserCard extends StatelessWidget {
  final AppUser user;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _UserCard({required this.user, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isAdmin = user.isAdmin;
    final screens = <String>[];
    if (user.canViewSales) screens.add('المبيعات');
    if (user.canViewPurchases) screens.add('المشتريات');
    if (user.canViewInventory) screens.add('المخزن');
    if (user.canViewReports) screens.add('التقارير');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isAdmin ? AppTheme.primaryBlue.withValues(alpha: 0.4) : Colors.grey.withValues(alpha: 0.15),
          width: isAdmin ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isAdmin
                  ? AppTheme.primaryBlue.withValues(alpha: 0.07)
                  : Colors.grey.withValues(alpha: 0.04),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 22,
                  backgroundColor: isAdmin ? AppTheme.primaryBlue : Colors.grey[400],
                  child: Text(
                    user.displayName.isNotEmpty
                        ? user.displayName[0].toUpperCase()
                        : user.username[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            user.displayName.isNotEmpty ? user.displayName : user.username,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isAdmin ? AppTheme.primaryBlue : Colors.grey[600],
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isAdmin ? 'مدير' : 'مستخدم',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@${user.username}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                // Actions
                if (!isAdmin || user.username != 'admin') ...[
                  IconButton(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded, size: 20),
                    color: AppTheme.primaryBlue,
                    tooltip: 'تعديل',
                  ),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    color: Colors.red,
                    tooltip: 'حذف',
                  ),
                ] else ...[
                  IconButton(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded, size: 20),
                    color: AppTheme.primaryBlue,
                    tooltip: 'تعديل كلمة المرور',
                  ),
                ],
              ],
            ),
          ),
          // ── Screens & Permissions summary ─────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Screens row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.visibility_rounded, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text('الشاشات: ', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                    Expanded(
                      child: isAdmin
                          ? const Text('جميع الشاشات', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600))
                          : screens.isEmpty
                              ? const Text('لا توجد شاشات', style: TextStyle(fontSize: 12, color: Colors.red))
                              : Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: screens
                                      .map((s) => Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(s, style: const TextStyle(fontSize: 11, color: AppTheme.primaryBlue)),
                                          ))
                                      .toList(),
                                ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Actions summary
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock_open_rounded, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text('الإجراءات: ', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                    Expanded(
                      child: isAdmin
                          ? const Text('صلاحيات كاملة', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600))
                          : _ActionsSummaryText(user: user),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Actions summary text widget
// ─────────────────────────────────────────────────────────────────────────────
class _ActionsSummaryText extends StatelessWidget {
  final AppUser user;
  const _ActionsSummaryText({required this.user});

  @override
  Widget build(BuildContext context) {
    final List<String> allowed = [];
    if (user.canAddSales) allowed.add('إضافة مبيعات');
    if (user.canDeleteSales) allowed.add('حذف مبيعات');
    if (user.canAddPurchases) allowed.add('إضافة مشتريات');
    if (user.canDeletePurchases) allowed.add('حذف مشتريات');
    if (user.canAddInventory) allowed.add('إضافة مخزن');
    if (user.canEditInventory) allowed.add('تعديل مخزن');
    if (user.canDeleteInventory) allowed.add('حذف مخزن');
    if (user.canExportReports) allowed.add('تصدير التقارير');
    if (allowed.isEmpty) return const Text('لا توجد صلاحيات', style: TextStyle(fontSize: 12, color: Colors.red));
    return Text(allowed.join(' · '), style: const TextStyle(fontSize: 11, color: Colors.black87));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Info Chip
// ─────────────────────────────────────────────────────────────────────────────
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add / Edit User Dialog
// ─────────────────────────────────────────────────────────────────────────────
class _UserDialog extends StatefulWidget {
  final AppUser? existing;
  final bool isNew;
  final Future<void> Function(AppUser) onSaved;

  const _UserDialog({this.existing, required this.isNew, required this.onSaved});

  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _usernameCtrl;
  late TextEditingController _displayNameCtrl;
  late TextEditingController _passwordCtrl;
  late TextEditingController _confirmPassCtrl;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _saving = false;

  // Screen permissions
  late bool _canViewSales;
  late bool _canViewPurchases;
  late bool _canViewInventory;
  late bool _canViewReports;

  // Action permissions
  late bool _canAddSales;
  late bool _canDeleteSales;
  late bool _canAddPurchases;
  late bool _canDeletePurchases;
  late bool _canAddInventory;
  late bool _canEditInventory;
  late bool _canDeleteInventory;
  late bool _canExportReports;

  @override
  void initState() {
    super.initState();
    final u = widget.existing;
    _usernameCtrl = TextEditingController(text: u?.username ?? '');
    _displayNameCtrl = TextEditingController(text: u?.displayName ?? '');
    _passwordCtrl = TextEditingController();
    _confirmPassCtrl = TextEditingController();

    _canViewSales = u?.canViewSales ?? true;
    _canViewPurchases = u?.canViewPurchases ?? true;
    _canViewInventory = u?.canViewInventory ?? true;
    _canViewReports = u?.canViewReports ?? true;

    _canAddSales = u?.canAddSales ?? true;
    _canDeleteSales = u?.canDeleteSales ?? false;
    _canAddPurchases = u?.canAddPurchases ?? true;
    _canDeletePurchases = u?.canDeletePurchases ?? false;
    _canAddInventory = u?.canAddInventory ?? true;
    _canEditInventory = u?.canEditInventory ?? true;
    _canDeleteInventory = u?.canDeleteInventory ?? false;
    _canExportReports = u?.canExportReports ?? true;
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Check username uniqueness for new users
    if (widget.isNew) {
      final exists = await DatabaseService.usernameExists(_usernameCtrl.text.trim());
      if (exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('⛔ اسم المستخدم موجود مسبقاً، اختر اسماً آخر'),
            backgroundColor: Colors.red,
          ));
        }
        return;
      }
    }

    setState(() => _saving = true);

    final password = _passwordCtrl.text.isNotEmpty
        ? _passwordCtrl.text
        : (widget.existing?.password ?? '');

    final user = AppUser(
      username: _usernameCtrl.text.trim(),
      password: password,
      role: 'user',
      displayName: _displayNameCtrl.text.trim(),
      canViewSales: _canViewSales,
      canViewPurchases: _canViewPurchases,
      canViewInventory: _canViewInventory,
      canViewReports: _canViewReports,
      canAddSales: _canAddSales,
      canDeleteSales: _canDeleteSales,
      canAddPurchases: _canAddPurchases,
      canDeletePurchases: _canDeletePurchases,
      canAddInventory: _canAddInventory,
      canEditInventory: _canEditInventory,
      canDeleteInventory: _canDeleteInventory,
      canExportReports: _canExportReports,
    );

    await widget.onSaved(user);
    setState(() => _saving = false);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isAdminEdit = widget.existing?.username == 'admin';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Dialog Title Bar ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.isNew ? Icons.person_add_rounded : Icons.edit_rounded,
                      color: Colors.white, size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.isNew ? 'إضافة مستخدم جديد' : 'تعديل المستخدم',
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                    ),
                  ],
                ),
              ),

              // ── Scrollable form body ──────────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Basic info section
                        _SectionHeader(icon: Icons.person_outline_rounded, title: 'معلومات المستخدم'),
                        const SizedBox(height: 12),

                        // Display Name
                        TextFormField(
                          controller: _displayNameCtrl,
                          decoration: _inputDec('الاسم الكامل', Icons.badge_outlined),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'الاسم الكامل مطلوب' : null,
                        ),
                        const SizedBox(height: 12),

                        // Username
                        TextFormField(
                          controller: _usernameCtrl,
                          enabled: widget.isNew,
                          decoration: _inputDec('اسم المستخدم', Icons.person_rounded),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'اسم المستخدم مطلوب';
                            if (v.trim().length < 3) return 'يجب أن يكون 3 أحرف على الأقل';
                            if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v.trim())) {
                              return 'أحرف إنجليزية وأرقام و _ فقط';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Password
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscurePass,
                          decoration: _inputDec(
                            widget.isNew ? 'كلمة المرور' : 'كلمة المرور الجديدة (اختياري)',
                            Icons.lock_outline_rounded,
                          ).copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                              onPressed: () => setState(() => _obscurePass = !_obscurePass),
                            ),
                          ),
                          validator: (v) {
                            if (widget.isNew && (v == null || v.isEmpty)) return 'كلمة المرور مطلوبة';
                            if (v != null && v.isNotEmpty && v.length < 4) return 'يجب أن تكون 4 أحرف على الأقل';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Confirm Password
                        TextFormField(
                          controller: _confirmPassCtrl,
                          obscureText: _obscureConfirm,
                          decoration: _inputDec('تأكيد كلمة المرور', Icons.lock_rounded).copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                            ),
                          ),
                          validator: (v) {
                            if (_passwordCtrl.text.isNotEmpty && v != _passwordCtrl.text) {
                              return 'كلمتا المرور غير متطابقتين';
                            }
                            return null;
                          },
                        ),

                        if (!isAdminEdit) ...[
                          const SizedBox(height: 24),

                          // ── Screen Permissions ─────────────────────────
                          _SectionHeader(icon: Icons.screen_share_rounded, title: 'الشاشات المسموح بها'),
                          const SizedBox(height: 4),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                _PermissionTile(
                                  label: 'شاشة المبيعات',
                                  icon: Icons.point_of_sale_rounded,
                                  iconColor: AppTheme.salesColor,
                                  value: _canViewSales,
                                  onChanged: (v) => setState(() {
                                    _canViewSales = v;
                                    if (!v) {
                                      _canAddSales = false;
                                      _canDeleteSales = false;
                                    }
                                  }),
                                ),
                                const Divider(height: 1),
                                _PermissionTile(
                                  label: 'شاشة المشتريات',
                                  icon: Icons.shopping_cart_rounded,
                                  iconColor: AppTheme.purchasesColor,
                                  value: _canViewPurchases,
                                  onChanged: (v) => setState(() {
                                    _canViewPurchases = v;
                                    if (!v) {
                                      _canAddPurchases = false;
                                      _canDeletePurchases = false;
                                    }
                                  }),
                                ),
                                const Divider(height: 1),
                                _PermissionTile(
                                  label: 'شاشة المخزن',
                                  icon: Icons.inventory_2_rounded,
                                  iconColor: AppTheme.inventoryColor,
                                  value: _canViewInventory,
                                  onChanged: (v) => setState(() {
                                    _canViewInventory = v;
                                    if (!v) {
                                      _canAddInventory = false;
                                      _canEditInventory = false;
                                      _canDeleteInventory = false;
                                    }
                                  }),
                                ),
                                const Divider(height: 1),
                                _PermissionTile(
                                  label: 'شاشة التقارير',
                                  icon: Icons.bar_chart_rounded,
                                  iconColor: AppTheme.reportsColor,
                                  value: _canViewReports,
                                  onChanged: (v) => setState(() {
                                    _canViewReports = v;
                                    if (!v) _canExportReports = false;
                                  }),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // ── Action Permissions ─────────────────────────
                          _SectionHeader(icon: Icons.tune_rounded, title: 'صلاحيات الإجراءات'),
                          const SizedBox(height: 4),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                // Sales actions
                                if (_canViewSales) ...[
                                  _PermissionTile(
                                    label: 'إضافة فواتير المبيعات',
                                    icon: Icons.add_shopping_cart_rounded,
                                    iconColor: AppTheme.salesColor,
                                    value: _canAddSales,
                                    onChanged: (v) => setState(() => _canAddSales = v),
                                    indent: true,
                                  ),
                                  const Divider(height: 1),
                                  _PermissionTile(
                                    label: 'حذف فواتير المبيعات',
                                    icon: Icons.remove_shopping_cart_rounded,
                                    iconColor: Colors.red,
                                    value: _canDeleteSales,
                                    onChanged: (v) => setState(() => _canDeleteSales = v),
                                    indent: true,
                                  ),
                                  const Divider(height: 1),
                                ],
                                // Purchases actions
                                if (_canViewPurchases) ...[
                                  _PermissionTile(
                                    label: 'إضافة المشتريات',
                                    icon: Icons.add_box_rounded,
                                    iconColor: AppTheme.purchasesColor,
                                    value: _canAddPurchases,
                                    onChanged: (v) => setState(() => _canAddPurchases = v),
                                    indent: true,
                                  ),
                                  const Divider(height: 1),
                                  _PermissionTile(
                                    label: 'حذف المشتريات',
                                    icon: Icons.delete_sweep_rounded,
                                    iconColor: Colors.red,
                                    value: _canDeletePurchases,
                                    onChanged: (v) => setState(() => _canDeletePurchases = v),
                                    indent: true,
                                  ),
                                  const Divider(height: 1),
                                ],
                                // Inventory actions
                                if (_canViewInventory) ...[
                                  _PermissionTile(
                                    label: 'إضافة عناصر المخزن',
                                    icon: Icons.add_circle_outline_rounded,
                                    iconColor: AppTheme.inventoryColor,
                                    value: _canAddInventory,
                                    onChanged: (v) => setState(() => _canAddInventory = v),
                                    indent: true,
                                  ),
                                  const Divider(height: 1),
                                  _PermissionTile(
                                    label: 'تعديل عناصر المخزن',
                                    icon: Icons.edit_rounded,
                                    iconColor: Colors.orange,
                                    value: _canEditInventory,
                                    onChanged: (v) => setState(() => _canEditInventory = v),
                                    indent: true,
                                  ),
                                  const Divider(height: 1),
                                  _PermissionTile(
                                    label: 'حذف عناصر المخزن',
                                    icon: Icons.delete_forever_rounded,
                                    iconColor: Colors.red,
                                    value: _canDeleteInventory,
                                    onChanged: (v) => setState(() => _canDeleteInventory = v),
                                    indent: true,
                                  ),
                                  const Divider(height: 1),
                                ],
                                // Reports actions
                                if (_canViewReports)
                                  _PermissionTile(
                                    label: 'تصدير التقارير (Excel)',
                                    icon: Icons.download_rounded,
                                    iconColor: AppTheme.reportsColor,
                                    value: _canExportReports,
                                    onChanged: (v) => setState(() => _canExportReports = v),
                                    indent: true,
                                  ),
                                if (!_canViewSales && !_canViewPurchases && !_canViewInventory && !_canViewReports)
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.info_outline_rounded, color: Colors.orange, size: 16),
                                        const SizedBox(width: 8),
                                        const Text('فعّل الشاشات أولاً لإظهار إجراءاتها', style: TextStyle(color: Colors.orange, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // ── Save Button ────────────────────────────────────
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.save_rounded, size: 20),
                            label: Text(
                              _saving ? 'جاري الحفظ...' : (widget.isNew ? 'إنشاء المستخدم' : 'حفظ التغييرات'),
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDec(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.primaryBlue),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Permission Tile (checkbox row)
// ─────────────────────────────────────────────────────────────────────────────
class _PermissionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool indent;

  const _PermissionTile({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.onChanged,
    this.indent = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: EdgeInsets.only(right: indent ? 16 : 0, left: 8, top: 4, bottom: 4),
        child: Row(
          children: [
            if (indent) const SizedBox(width: 8),
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: value ? Colors.black87 : Colors.grey,
                ),
              ),
            ),
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: AppTheme.primaryBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Header
// ─────────────────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.primaryBlue),
        const SizedBox(width: 6),
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
      ],
    );
  }
}
