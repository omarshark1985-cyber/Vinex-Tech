import 'package:hive/hive.dart';

part 'user_model.g.dart';

@HiveType(typeId: 0)
class AppUser extends HiveObject {
  @HiveField(0)
  late String username;

  @HiveField(1)
  late String password;

  @HiveField(2)
  late String role; // 'admin' | 'user'

  // ── Screen Permissions ─────────────────────────────────────────────────────
  @HiveField(3)
  bool canViewSales;

  @HiveField(4)
  bool canViewPurchases;

  @HiveField(5)
  bool canViewInventory;

  @HiveField(6)
  bool canViewReports;

  // ── Action Permissions ─────────────────────────────────────────────────────
  @HiveField(7)
  bool canAddSales;

  @HiveField(8)
  bool canDeleteSales;

  @HiveField(9)
  bool canAddPurchases;

  @HiveField(10)
  bool canDeletePurchases;

  @HiveField(11)
  bool canAddInventory;

  @HiveField(12)
  bool canEditInventory;

  @HiveField(13)
  bool canDeleteInventory;

  @HiveField(14)
  bool canExportReports;

  // ── Display name (optional) ────────────────────────────────────────────────
  @HiveField(15)
  String displayName;

  AppUser({
    required this.username,
    required this.password,
    this.role = 'user',
    this.displayName = '',
    // Screen defaults — admin gets all, user gets all by default
    this.canViewSales = true,
    this.canViewPurchases = true,
    this.canViewInventory = true,
    this.canViewReports = true,
    // Action defaults
    this.canAddSales = true,
    this.canDeleteSales = false,
    this.canAddPurchases = true,
    this.canDeletePurchases = false,
    this.canAddInventory = true,
    this.canEditInventory = true,
    this.canDeleteInventory = false,
    this.canExportReports = true,
  });

  /// Convert to Map for Firestore/Hive storage
  Map<String, dynamic> toMap() => {
        'username': username,
        'password': password,
        'role': role,
        'displayName': displayName,
        'canViewSales': canViewSales,
        'canViewPurchases': canViewPurchases,
        'canViewInventory': canViewInventory,
        'canViewReports': canViewReports,
        'canAddSales': canAddSales,
        'canDeleteSales': canDeleteSales,
        'canAddPurchases': canAddPurchases,
        'canDeletePurchases': canDeletePurchases,
        'canAddInventory': canAddInventory,
        'canEditInventory': canEditInventory,
        'canDeleteInventory': canDeleteInventory,
        'canExportReports': canExportReports,
      };

  /// Create AppUser from Map (Firestore/Hive)
  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      username: map['username'] as String? ?? '',
      password: map['password'] as String? ?? '',
      role: map['role'] as String? ?? 'user',
      displayName: map['displayName'] as String? ?? '',
      canViewSales: map['canViewSales'] as bool? ?? true,
      canViewPurchases: map['canViewPurchases'] as bool? ?? true,
      canViewInventory: map['canViewInventory'] as bool? ?? true,
      canViewReports: map['canViewReports'] as bool? ?? true,
      canAddSales: map['canAddSales'] as bool? ?? true,
      canDeleteSales: map['canDeleteSales'] as bool? ?? false,
      canAddPurchases: map['canAddPurchases'] as bool? ?? true,
      canDeletePurchases: map['canDeletePurchases'] as bool? ?? false,
      canAddInventory: map['canAddInventory'] as bool? ?? true,
      canEditInventory: map['canEditInventory'] as bool? ?? true,
      canDeleteInventory: map['canDeleteInventory'] as bool? ?? false,
      canExportReports: map['canExportReports'] as bool? ?? true,
    );
  }

  bool get isAdmin => role == 'admin';
}
