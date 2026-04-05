import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import '../models/sale_model.dart';
import '../models/purchase_model.dart';
import '../models/inventory_model.dart';
import '../models/invoice_item_model.dart';
import '../models/invoice_model.dart';
import 'package:uuid/uuid.dart';

class DatabaseService {
  // ─── Firebase ─────────────────────────────────────────────────────────────
  static FirebaseFirestore? _firestore;
  static bool _firebaseAvailable = false;
  static bool get isFirebaseConnected => _firebaseAvailable;

  /// BehaviorSubject-style controller — always replays the latest value to new subscribers.
  /// Uses a single broadcast StreamController; new subscribers call [connectionStream]
  /// which first returns the current value synchronously via [isFirebaseConnected],
  /// then listens for future changes on [_connectionController].
  static final _connectionController = StreamController<bool>.broadcast();

  /// Replay-capable connection stream.
  /// Every subscriber immediately receives the current connection state,
  /// then receives future state changes without any timing gaps.
  static Stream<bool> get connectionStream {
    // Return a stream that starts with a Future.value of current state
    // then merges with the broadcast controller — no async* generator gaps.
    late StreamController<bool> sc;
    sc = StreamController<bool>(
      onListen: () {
        // Immediately emit the current value
        sc.add(_firebaseAvailable);
        // Then pipe all future changes
        _connectionController.stream.listen(
          (v) { if (!sc.isClosed) sc.add(v); },
          onDone: () { if (!sc.isClosed) sc.close(); },
        );
      },
    );
    return sc.stream;
  }

  static void _setFirebaseAvailable(bool value) {
    _firebaseAvailable = value;
    _connectionController.add(value);
  }

  // ─── Real-time stream controllers ─────────────────────────────────────────
  static final _inventoryController =
      StreamController<List<InventoryItem>>.broadcast();
  static final _invoicesController =
      StreamController<List<Invoice>>.broadcast();
  static final _purchasesController =
      StreamController<List<Purchase>>.broadcast();
  static final _usersController =
      StreamController<List<AppUser>>.broadcast();

  // Cache last emitted values — new subscribers get current data immediately
  static List<InventoryItem> _lastInventory = [];
  static List<Invoice> _lastInvoices = [];
  static List<Purchase> _lastPurchases = [];
  static List<AppUser> _lastUsers = [];

  // Public read-only access to cached data (for instant UI computation)
  static List<InventoryItem> get lastInventory  => List.unmodifiable(_lastInventory);
  static List<Invoice>       get lastInvoices   => List.unmodifiable(_lastInvoices);
  static List<Purchase>      get lastPurchases  => List.unmodifiable(_lastPurchases);
  static List<AppUser>       get lastUsers      => List.unmodifiable(_lastUsers);

  static Stream<List<InventoryItem>> get inventoryStream {
    late StreamController<List<InventoryItem>> sc;
    sc = StreamController<List<InventoryItem>>(
      onListen: () {
        sc.add(List.from(_lastInventory));
        _inventoryController.stream.listen(
          (v) { if (!sc.isClosed) sc.add(v); },
          onDone: () { if (!sc.isClosed) sc.close(); },
        );
      },
    );
    return sc.stream;
  }

  static Stream<List<Invoice>> get invoicesStream {
    late StreamController<List<Invoice>> sc;
    sc = StreamController<List<Invoice>>(
      onListen: () {
        sc.add(List.from(_lastInvoices));
        _invoicesController.stream.listen(
          (v) { if (!sc.isClosed) sc.add(v); },
          onDone: () { if (!sc.isClosed) sc.close(); },
        );
      },
    );
    return sc.stream;
  }

  static Stream<List<Purchase>> get purchasesStream {
    late StreamController<List<Purchase>> sc;
    sc = StreamController<List<Purchase>>(
      onListen: () {
        sc.add(List.from(_lastPurchases));
        _purchasesController.stream.listen(
          (v) { if (!sc.isClosed) sc.add(v); },
          onDone: () { if (!sc.isClosed) sc.close(); },
        );
      },
    );
    return sc.stream;
  }

  static Stream<List<AppUser>> get usersStream {
    late StreamController<List<AppUser>> sc;
    sc = StreamController<List<AppUser>>(
      onListen: () {
        sc.add(List.from(_lastUsers));
        _usersController.stream.listen(
          (v) { if (!sc.isClosed) sc.add(v); },
          onDone: () { if (!sc.isClosed) sc.close(); },
        );
      },
    );
    return sc.stream;
  }

  static void _emitInventory(List<InventoryItem> items) {
    _lastInventory = items;
    _inventoryController.add(items);
  }

  static void _emitInvoices(List<Invoice> invoices) {
    _lastInvoices = invoices;
    _invoicesController.add(invoices);
  }

  static void _emitPurchases(List<Purchase> purchases) {
    _lastPurchases = purchases;
    _purchasesController.add(purchases);
  }

  static void _emitUsers(List<AppUser> users) {
    _lastUsers = users;
    _usersController.add(users);
  }

  // Firestore subscriptions
  static StreamSubscription? _invSub;
  static StreamSubscription? _invItemSub;
  static StreamSubscription? _purchSub;
  static StreamSubscription? _usersSub;

  static FirebaseFirestore get _db {
    if (_firestore == null) {
      _firestore = FirebaseFirestore.instance;
      // persistenceEnabled is NOT supported on Web — skip for web
      if (!kIsWeb) {
        try {
          _firestore!.settings = const Settings(
            persistenceEnabled: true,
            cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
          );
        } catch (e) {
          if (kDebugMode) debugPrint('Firestore settings warning: $e');
        }
      }
    }
    return _firestore!;
  }

  static const String _userCol      = 'users';
  static const String _salesCol     = 'sales';
  static const String _purchasesCol = 'purchases';
  static const String _inventoryCol = 'inventory';
  static const String _invoicesCol  = 'invoices';

  // ─── Hive boxes (offline fallback) ────────────────────────────────────────
  static late Box _usersBox;
  static late Box _inventoryBox;
  static late Box _purchasesBox;
  static late Box _salesBox;
  static late Box _invoicesBox;

  // ─── INITIALIZE ───────────────────────────────────────────────────────────
  static Future<void> initialize() async {
    // 1) Hive local storage
    await Hive.initFlutter();
    _usersBox     = await Hive.openBox('users_local');
    _inventoryBox = await Hive.openBox('inventory_local');
    _purchasesBox = await Hive.openBox('purchases_local');
    _salesBox     = await Hive.openBox('sales_local');
    _invoicesBox  = await Hive.openBox('invoices_local');

    _ensureLocalAdmin();

    // 2) Start Firebase connection attempt in background
    // On Web: connection may take 2-5 seconds after Firebase.initializeApp()
    // SplashGate polls isFirebaseConnected and waits up to 15s
    _connectFirebaseBackground();
    
    // 3) Start periodic refresh timer ALWAYS — handles reconnect if initial fails
    _startPeriodicRefresh();
  }

  /// Starts Firebase connection in background — does NOT block app startup.
  /// Uses snapshots() stream for connection which is more reliable on Web.
  static void _connectFirebaseBackground() {
    Future.microtask(() async {
      await _connectFirebase();
    });
  }

  static Future<void> _connectFirebase() async {
    // Small delay on web to allow Firebase JS SDK to fully initialize
    if (kIsWeb) await Future.delayed(const Duration(milliseconds: 800));

    // Push local cached data first so UI shows something immediately
    _pushLocalToStreams();

    // ── Step 1: Initial data load via REST (works on ALL platforms) ───────────
    _setFirebaseAvailable(true);   // optimistic — confirmed below
    try {
      final results = await Future.wait([
        _loadInventoryFromRest(),
        _loadInvoicesFromRest(),
        _loadPurchasesFromRest(),
        _loadUsersFromRest(),
      ]);
      final anyOk = results.any((ok) => ok == true);
      if (!anyOk) {
        debugPrint('❌ All REST loaders failed → offline mode');
        _setFirebaseAvailable(false);
        return;                    // no point starting listeners
      }
      _setFirebaseAvailable(true);
      await _ensureDefaultAdmin();
      debugPrint('✅ Firebase: initial data loaded via REST');
    } catch (e) {
      debugPrint('❌ _connectFirebase REST error: $e');
      _setFirebaseAvailable(false);
      return;
    }

    // ── Step 2: Real-time sync strategy per platform ──────────────────────────
    if (kIsWeb) {
      // Web: REST polling every 5 s (Firestore WebChannel/gRPC unreliable in browser)
      _startPeriodicRefresh();
      debugPrint('✅ Web: REST polling started (5 s interval)');
    } else {
      // Android/iOS: Firestore SDK real-time snapshot listeners
      // These push changes instantly whenever ANY client writes to Firebase
      _startRealtimeListeners();
      // Also keep a 30 s fallback poll in case snapshot misses something
      _startPeriodicRefresh();
      debugPrint('✅ Android: Firestore snapshot listeners + 30 s fallback started');
    }
  }

  // ─── REST CONSTANTS ───────────────────────────────────────────────────────
  static const _projectId = 'vinex-storage85';
  static const _apiKey    = 'AIzaSyCfQ9n3BZv0mniiWyZ9ELhAs7OqJB0a6UE';
  static const _restBase  =
      'https://firestore.googleapis.com/v1/projects/$_projectId'
      '/databases/(default)/documents';

  static Timer? _refreshTimer;

  /// Connectivity check — single fast REST call
  // ignore: unused_element
  static Future<bool> _checkFirestoreViaRest() async {
    final url = Uri.parse('$_restBase/inventory?pageSize=1&key=$_apiKey');
    for (int i = 1; i <= 2; i++) {
      try {
        final resp = await http.get(url).timeout(const Duration(seconds: 6));
        if (kDebugMode) debugPrint('🌐 REST check $i: HTTP ${resp.statusCode}');
        if (resp.statusCode == 200) return true;
      } catch (e) {
        if (kDebugMode) debugPrint('🌐 REST check $i failed: $e');
        if (i < 2) await Future.delayed(const Duration(milliseconds: 800));
      }
    }
    return false;
  }

  /// Fetch all documents from a Firestore collection via REST API.
  /// Returns list of {id, ...fields} maps, or null if request failed.
  static Future<List<Map<String, dynamic>>?> _fetchCollectionRest(
      String collection) async {
    final List<Map<String, dynamic>> results = [];
    String? pageToken;
    bool requestFailed = false;
    do {
      var urlStr = '$_restBase/$collection?pageSize=300&key=$_apiKey';
      if (pageToken != null) urlStr += '&pageToken=$pageToken';
      try {
        final resp = await http
            .get(Uri.parse(urlStr))
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode != 200) {
          debugPrint('REST fetch $collection HTTP ${resp.statusCode}');
          requestFailed = true;
          break;
        }
        final body = json.decode(resp.body) as Map<String, dynamic>;
        final docs = body['documents'] as List<dynamic>? ?? [];
        for (final doc in docs) {
          final m = doc as Map<String, dynamic>;
          final name = m['name'] as String;
          final id = name.split('/').last;
          final fields = m['fields'] as Map<String, dynamic>? ?? {};
          final flat = <String, dynamic>{'id': id};
          fields.forEach((k, v) {
            flat[k] = _parseFirestoreValue(v as Map<String, dynamic>);
          });
          results.add(flat);
        }
        pageToken = body['nextPageToken'] as String?;
      } catch (e) {
        debugPrint('REST fetch $collection error: $e');
        requestFailed = true;
        break;
      }
    } while (pageToken != null);
    // Return null if request failed, empty list if collection is empty
    return requestFailed ? null : results;
  }

  /// Parse a Firestore REST value like {"stringValue":"hello"} → "hello"
  static dynamic _parseFirestoreValue(Map<String, dynamic> v) {
    if (v.containsKey('stringValue'))    return v['stringValue'];
    if (v.containsKey('integerValue'))   return int.tryParse(v['integerValue'].toString()) ?? 0;
    if (v.containsKey('doubleValue'))    return (v['doubleValue'] as num).toDouble();
    if (v.containsKey('booleanValue'))   return v['booleanValue'] as bool;
    if (v.containsKey('timestampValue')) return v['timestampValue'] as String; // ISO string
    if (v.containsKey('nullValue'))      return null;
    if (v.containsKey('arrayValue')) {
      final vals = (v['arrayValue'] as Map)['values'] as List<dynamic>? ?? [];
      return vals.map((e) => _parseFirestoreValue(e as Map<String, dynamic>)).toList();
    }
    if (v.containsKey('mapValue')) {
      final fields = (v['mapValue'] as Map)['fields'] as Map<String, dynamic>? ?? {};
      return fields.map((k, fv) => MapEntry(k, _parseFirestoreValue(fv as Map<String, dynamic>)));
    }
    return null;
  }

  // ─── REST WRITE HELPERS ───────────────────────────────────────────────────

  /// PATCH a single document via Firestore REST API.
  /// [fields] is a plain Dart map (String, int, double, bool supported).
  static Future<bool> _patchDocumentRest(
      String collection, String docId, Map<String, dynamic> fields) async {
    try {
      final maskParams = fields.keys.map((k) => 'updateMask.fieldPaths=$k').join('&');
      final url = Uri.parse(
          '$_restBase/$collection/$docId?$maskParams&key=$_apiKey');
      final body = json.encode({
        'fields': fields.map((k, v) => MapEntry(k, _toFirestoreValue(v))),
      });
      final resp = await http
          .patch(url, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 10));
      if (kDebugMode) debugPrint('PATCH $collection/$docId → ${resp.statusCode}');
      return resp.statusCode == 200;
    } catch (e) {
      if (kDebugMode) debugPrint('_patchDocumentRest error: $e');
      return false;
    }
  }

  /// CREATE or OVERWRITE a document via Firestore REST API (HTTP PATCH with full fields).
  static Future<bool> _putDocumentRest(
      String collection, String docId, Map<String, dynamic> fields) async {
    try {
      final url = Uri.parse('$_restBase/$collection/$docId?key=$_apiKey');
      final body = json.encode({
        'fields': fields.map((k, v) => MapEntry(k, _toFirestoreValue(v))),
      });
      final resp = await http
          .patch(url, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 10));
      if (kDebugMode) debugPrint('PUT $collection/$docId → ${resp.statusCode}');
      return resp.statusCode == 200;
    } catch (e) {
      if (kDebugMode) debugPrint('_putDocumentRest error: $e');
      return false;
    }
  }

  /// Convert a Dart value to a Firestore REST value map.
  static Map<String, dynamic> _toFirestoreValue(dynamic v) {
    if (v == null)    return {'nullValue': null};
    if (v is bool)    return {'booleanValue': v};
    if (v is int)     return {'integerValue': '$v'};
    if (v is double)  return {'doubleValue': v};
    if (v is String)  return {'stringValue': v};
    if (v is DateTime) return {'timestampValue': v.toUtc().toIso8601String()};
    if (v is List)    return {'arrayValue': {'values': v.map(_toFirestoreValue).toList()}};
    if (v is Map)     return {'mapValue': {'fields': (v as Map<String, dynamic>).map((k, fv) => MapEntry(k, _toFirestoreValue(fv)))}};
    return {'stringValue': '$v'};
  }

  // ─── REST DATA LOADERS ────────────────────────────────────────────────────

  static Future<bool> _loadInventoryFromRest() async {
    try {
      final docs = await _fetchCollectionRest(_inventoryCol);
      if (docs == null) {
        if (kDebugMode) debugPrint('❌ Inventory REST returned null (request failed)');
        _emitInventory(_getAllLocalInventory());
        return false;
      }
      final items = docs.map((m) {
        return InventoryItem(
          id: m['id'] as String? ?? '',
          itemName: m['itemName'] as String? ?? m['name'] as String? ?? '',
          category: m['category'] as String? ?? 'عام',
          quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
          unitPrice: (m['unitPrice'] as num?)?.toDouble() ?? 0,
          minStock: (m['minStock'] as num?)?.toDouble() ?? 5,
          unit: m['unit'] as String? ?? 'قطعة',
          description: m['description'] as String? ?? '',
          lastUpdated: _parseTimestamp(m['createdAt']),
        );
      }).toList()..sort((a, b) => a.itemName.compareTo(b.itemName));

      // Cache to Hive
      for (final item in items) {
        _inventoryBox.put(item.id, _itemToMap(item));
      }
      _emitInventory(items);
      if (kDebugMode) debugPrint('✅ Inventory: ${items.length} items loaded');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ loadInventory error: $e');
      _emitInventory(_getAllLocalInventory());
      return false;
    }
  }

  static Future<bool> _loadInvoicesFromRest() async {
    try {
      final docs = await _fetchCollectionRest(_invoicesCol);
      if (docs == null) {
        if (kDebugMode) debugPrint('❌ Invoices REST returned null (request failed)');
        _emitInvoices(_getAllLocalInvoices());
        return false;
      }
      final invoices = docs.map((m) {
        final rawItems = m['items'] as List<dynamic>? ?? [];
        final items = rawItems.map((i) {
          final im = i as Map<String, dynamic>;
          return InvoiceItem(
            sequence: (im['sequence'] as num?)?.toInt() ?? 1,
            itemName: im['itemName'] as String? ?? '',
            quantity: (im['quantity'] as num?)?.toDouble() ?? 0,
            unitPrice: (im['unitPrice'] as num?)?.toDouble() ?? 0,
            totalPrice: (im['totalPrice'] as num?)?.toDouble() ?? 0,
          );
        }).toList();
        return Invoice(
          id: m['id'] as String? ?? '',
          invoiceNumber: (m['invoiceNumber'] as num?)?.toInt() ?? 0,
          customerName: m['customerName'] as String? ?? '',
          invoiceDate: _parseTimestamp(m['invoiceDate']),
          items: items,
          notes: m['notes'] as String? ?? '',
          totalAmount: (m['totalAmount'] as num?)?.toDouble() ?? 0,
          discount: (m['discount'] as num?)?.toDouble() ?? 0,
          invoiceType: m['invoiceType'] as String? ?? 'sale',
          downPayment: (m['downPayment'] as num?)?.toDouble() ?? 0,
        );
      }).toList()..sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate));

      for (final inv in invoices) {
        _invoicesBox.put(inv.id, _invoiceToMap(inv));
      }
      _emitInvoices(invoices);
      if (kDebugMode) debugPrint('✅ Invoices: ${invoices.length} loaded');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ loadInvoices error: $e');
      _emitInvoices(_getAllLocalInvoices());
      return false;
    }
  }

  static Future<bool> _loadPurchasesFromRest() async {
    try {
      final docs = await _fetchCollectionRest(_purchasesCol);
      if (docs == null) {
        if (kDebugMode) debugPrint('❌ Purchases REST returned null (request failed)');
        _emitPurchases(_getAllLocalPurchases());
        return false;
      }
      final purchases = docs.map((m) {
        return Purchase(
          id: m['id'] as String? ?? '',
          supplierName: m['supplierName'] as String? ?? '',
          itemName: m['itemName'] as String? ?? '',
          quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
          unitPrice: (m['unitPrice'] as num?)?.toDouble() ?? 0,
          totalPrice: (m['totalPrice'] as num?)?.toDouble() ?? 0,
          date: _parseTimestamp(m['purchaseDate']),
          notes: m['notes'] as String? ?? '',
        );
      }).toList()..sort((a, b) => b.date.compareTo(a.date));

      for (final p in purchases) {
        _purchasesBox.put(p.id, _purchaseToMap(p));
      }
      _emitPurchases(purchases);
      if (kDebugMode) debugPrint('✅ Purchases: ${purchases.length} loaded');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ loadPurchases error: $e');
      _emitPurchases(_getAllLocalPurchases());
      return false;
    }
  }

  static Future<bool> _loadUsersFromRest() async {
    try {
      final docs = await _fetchCollectionRest(_userCol);
      if (docs == null) {
        if (kDebugMode) debugPrint('❌ Users REST returned null');
        _emitUsers(_getAllLocalUsers());
        return false;
      }
      final users = docs.map((m) {
        return AppUser.fromMap(Map<String, dynamic>.from(m));
      }).toList();
      // Update local Hive cache
      for (final u in users) {
        _usersBox.put(u.username, u.toMap());
      }
      _emitUsers(users..sort((a, b) => a.username.compareTo(b.username)));
      if (kDebugMode) debugPrint('✅ Users: ${users.length} loaded from Firebase');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ _loadUsersFromRest error: $e');
      _emitUsers(_getAllLocalUsers());
      return false;
    }
  }

  static List<AppUser> _getAllLocalUsers() {
    final List<AppUser> result = [];
    for (final key in _usersBox.keys) {
      try {
        final u = Map<String, dynamic>.from(_usersBox.get(key) as Map);
        result.add(AppUser.fromMap(u));
      } catch (_) {}
    }
    return result;
  }

  static DateTime _parseTimestamp(dynamic raw) {
    if (raw == null) return DateTime.now();
    if (raw is String) {
      return DateTime.tryParse(raw) ?? DateTime.now();
    }
    if (raw is Timestamp) return raw.toDate();
    return DateTime.now();
  }

  /// Public method — call from any screen to force an immediate Firebase refresh.
  /// If currently offline, attempts to reconnect first.
  static Future<void> refreshData() async {
    if (!_firebaseAvailable) {
      // Try to reconnect when offline
      if (kDebugMode) debugPrint('🔄 Offline — attempting reconnect...');
      await _connectFirebase();
      return;
    }
    if (kDebugMode) debugPrint('🔄 Manual refresh triggered...');
    final results = await Future.wait([
      _loadInventoryFromRest(),
      _loadInvoicesFromRest(),
      _loadPurchasesFromRest(),
      _loadUsersFromRest(),
    ]);
    final anyFailed = results.any((ok) => ok == false);
    if (anyFailed) {
      // Some loaders failed — mark offline so next call triggers reconnect
      _setFirebaseAvailable(false);
      if (kDebugMode) debugPrint('⚠️ Some REST loaders failed — marked offline');
    } else {
      if (kDebugMode) debugPrint('✅ Manual refresh complete');
    }
  }

  /// Periodic refresh:
  /// - Web: every 5 s (primary sync mechanism, no real-time listeners)
  /// - Android: every 30 s (fallback; primary sync is Firestore snapshots)
  static void _startPeriodicRefresh() {
    final interval = kIsWeb
        ? const Duration(seconds: 5)
        : const Duration(seconds: 30);
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(interval, (_) async {
      if (!_firebaseAvailable) {
        // Auto-reconnect attempt during periodic refresh
        if (kDebugMode) debugPrint('🔄 Periodic: attempting reconnect...');
        await _connectFirebase();
        return;
      }
      if (kDebugMode) debugPrint('🔄 Periodic refresh from Firebase...');
      final results = await Future.wait([
        _loadInventoryFromRest(),
        _loadInvoicesFromRest(),
        _loadPurchasesFromRest(),
        _loadUsersFromRest(),
      ]);
      if (results.any((ok) => ok == false)) {
        _setFirebaseAvailable(false);
      }
    });
  }

  /// Also keep _startRealtimeListeners for non-web platforms (Dart SDK works fine)
  static void _startRealtimeListeners() {
    if (kIsWeb) {
      // Web: use REST polling instead (snapshots/WebChannel unreliable on web)
      _startPeriodicRefresh();
      return;
    }
    // Non-web: use Firestore SDK snapshots (reliable on mobile/desktop)
    _invItemSub?.cancel();
    _invItemSub = _db.collection(_inventoryCol).snapshots().listen(
      (snap) {
        final items = snap.docs.map(_inventoryItemFromDoc).toList()
          ..sort((a, b) => a.itemName.compareTo(b.itemName));
        for (final item in items) {
          _inventoryBox.put(item.id, _itemToMap(item));
        }
        _emitInventory(items);
      },
      onError: (e) {
        if (kDebugMode) debugPrint('Inventory listener error: $e');
        _emitInventory(_getAllLocalInventory());
      },
    );
    _invSub?.cancel();
    _invSub = _db.collection(_invoicesCol).snapshots().listen(
      (snap) {
        final invoices = snap.docs.map(_invoiceFromDoc).toList()
          ..sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate));
        for (final inv in invoices) {
          _invoicesBox.put(inv.id, _invoiceToMap(inv));
        }
        _emitInvoices(invoices);
      },
      onError: (e) {
        if (kDebugMode) debugPrint('Invoices listener error: $e');
        _emitInvoices(_getAllLocalInvoices());
      },
    );
    _purchSub?.cancel();
    _purchSub = _db.collection(_purchasesCol).snapshots().listen(
      (snap) {
        final purchases = snap.docs.map(_purchaseFromDoc).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        for (final p in purchases) {
          _purchasesBox.put(p.id, _purchaseToMap(p));
        }
        _emitPurchases(purchases);
      },
      onError: (e) {
        if (kDebugMode) debugPrint('Purchases listener error: $e');
        _emitPurchases(_getAllLocalPurchases());
      },
    );
    // Real-time listener for users collection
    _usersSub?.cancel();
    _usersSub = _db.collection(_userCol).snapshots().listen(
      (snap) {
        final users = snap.docs.map((doc) {
          return AppUser.fromMap(Map<String, dynamic>.from(doc.data()));
        }).toList()..sort((a, b) => a.username.compareTo(b.username));
        for (final u in users) {
          _usersBox.put(u.username, u.toMap());
        }
        _emitUsers(users);
        if (kDebugMode) debugPrint('🔄 Users snapshot: ${users.length} users updated');
      },
      onError: (e) {
        if (kDebugMode) debugPrint('Users listener error: $e');
        _emitUsers(_getAllLocalUsers());
      },
    );
  }

  static void _pushLocalToStreams() {
    _emitInventory(_getAllLocalInventory()
      ..sort((a, b) => a.itemName.compareTo(b.itemName)));
    _emitInvoices(_getAllLocalInvoices()
      ..sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate)));
    _emitPurchases(_getAllLocalPurchases()
      ..sort((a, b) => b.date.compareTo(a.date)));
    _emitUsers(_getAllLocalUsers()
      ..sort((a, b) => a.username.compareTo(b.username)));
  }

  // ─── ADMIN ────────────────────────────────────────────────────────────────
  static void _ensureLocalAdmin() {
    if (!_usersBox.containsKey('admin')) {
      final adminUser = AppUser(
        username: 'admin',
        password: 'admin123',
        role: 'admin',
        displayName: 'Administrator',
        canViewSales: true,
        canViewPurchases: true,
        canViewInventory: true,
        canViewReports: true,
        canAddSales: true,
        canDeleteSales: true,
        canAddPurchases: true,
        canDeletePurchases: true,
        canAddInventory: true,
        canEditInventory: true,
        canDeleteInventory: true,
        canExportReports: true,
      );
      _usersBox.put('admin', adminUser.toMap());
    }
  }

  static Future<void> _ensureDefaultAdmin() async {
    try {
      // Check via REST-loaded users (already loaded at this point)
      final adminExists = _lastUsers.any((u) => u.username == 'admin');
      if (!adminExists) {
        final adminUser = AppUser(
          username: 'admin',
          password: 'admin123',
          role: 'admin',
          displayName: 'Administrator',
          canViewSales: true,
          canViewPurchases: true,
          canViewInventory: true,
          canViewReports: true,
          canAddSales: true,
          canDeleteSales: true,
          canAddPurchases: true,
          canDeletePurchases: true,
          canAddInventory: true,
          canEditInventory: true,
          canDeleteInventory: true,
          canExportReports: true,
        );
        await _putUserRest('admin', adminUser.toMap());
        if (kDebugMode) debugPrint('✅ Default admin created via REST');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('_ensureDefaultAdmin: $e');
    }
  }

  // ─── LOGIN ────────────────────────────────────────────────────────────────
  static Future<AppUser?> loginAsync(String username, String password) async {
    // Always reload users from Firebase first to get the latest passwords
    if (_firebaseAvailable) {
      try {
        await _loadUsersFromRest();
      } catch (e) {
        if (kDebugMode) debugPrint('loginAsync refresh failed: $e');
      }
    }
    // Check the freshly-loaded REST users list
    final fromRest = _lastUsers.where(
        (u) => u.username == username && u.password == password);
    if (fromRest.isNotEmpty) return fromRest.first;

    // Local Hive fallback (offline mode)
    for (final key in _usersBox.keys) {
      final u = Map<String, dynamic>.from(_usersBox.get(key) as Map);
      if (u['username'] == username && u['password'] == password) {
        return AppUser.fromMap(u);
      }
    }
    return null;
  }

  static AppUser? login(String username, String password) => null;

  // ─── USER MANAGEMENT (admin only) ─────────────────────────────────────────

  /// Get all users (Firestore → local fallback)
  static Future<List<AppUser>> getAllUsers() async {
    final List<AppUser> result = [];
    if (_firebaseAvailable) {
      try {
        final snap = await _db
            .collection(_userCol)
            .get()
            .timeout(const Duration(seconds: 8));
        for (final doc in snap.docs) {
          result.add(AppUser.fromMap(Map<String, dynamic>.from(doc.data())));
        }
        return result;
      } catch (e) {
        if (kDebugMode) debugPrint('getAllUsers Firebase failed: $e');
      }
    }
    // Local fallback
    for (final key in _usersBox.keys) {
      try {
        final u = Map<String, dynamic>.from(_usersBox.get(key) as Map);
        result.add(AppUser.fromMap(u));
      } catch (_) {}
    }
    return result;
  }

  /// Save (create or update) a user — always overwrites so password changes are persisted.
  /// Uses REST API (same transport as reads) to avoid Firestore SDK web issues.
  static Future<void> saveUser(AppUser user) async {
    final map = user.toMap();

    // 1) Save locally first (instant UI update)
    _usersBox.put(user.username, map);
    _emitUsers(_getAllLocalUsers()..sort((a, b) => a.username.compareTo(b.username)));

    // 2) Write to Firebase via REST (PUT = full document overwrite, all fields)
    if (_firebaseAvailable) {
      try {
        final ok = await _putUserRest(user.username, map);
        if (kDebugMode) {
          debugPrint(ok
              ? '✅ saveUser REST PUT succeeded for "${user.username}"'
              : '⚠️ saveUser REST PUT failed for "${user.username}"');
        }
        // Reload from Firebase to confirm sync and update all subscribers
        await _loadUsersFromRest();
      } catch (e) {
        if (kDebugMode) debugPrint('saveUser REST error: $e');
      }
    }
  }

  /// Full-overwrite a user document via Firestore REST (PATCH without updateMask = replace all).
  static Future<bool> _putUserRest(
      String docId, Map<String, dynamic> fields) async {
    try {
      // Firestore REST PATCH without updateMask replaces the entire document
      final url = Uri.parse('$_restBase/$_userCol/$docId?key=$_apiKey');
      final body = json.encode({
        'fields': fields.map((k, v) => MapEntry(k, _toFirestoreValue(v))),
      });
      final resp = await http
          .patch(url, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 12));
      if (kDebugMode) debugPrint('_putUserRest $docId → HTTP ${resp.statusCode}');
      if (resp.statusCode != 200 && kDebugMode) {
        debugPrint('_putUserRest response body: ${resp.body}');
      }
      return resp.statusCode == 200;
    } catch (e) {
      if (kDebugMode) debugPrint('_putUserRest error: $e');
      return false;
    }
  }

  /// Delete a user by username — uses REST API
  static Future<void> deleteUser(String username) async {
    _usersBox.delete(username);
    _emitUsers(_getAllLocalUsers()..sort((a, b) => a.username.compareTo(b.username)));
    if (_firebaseAvailable) {
      try {
        final url = Uri.parse('$_restBase/$_userCol/$username?key=$_apiKey');
        final resp = await http
            .delete(url)
            .timeout(const Duration(seconds: 10));
        if (kDebugMode) debugPrint('deleteUser REST → HTTP ${resp.statusCode}');
        await _loadUsersFromRest();
      } catch (e) {
        if (kDebugMode) debugPrint('deleteUser REST error: $e');
      }
    }
  }

  /// Check if a username already exists — uses local cache + REST-loaded users
  static Future<bool> usernameExists(String username) async {
    // Check local Hive cache
    if (_usersBox.containsKey(username)) return true;
    // Check REST-loaded users list
    if (_lastUsers.any((u) => u.username == username)) return true;
    // Final check: fetch from Firebase via REST
    if (_firebaseAvailable) {
      try {
        final url = Uri.parse('$_restBase/$_userCol/$username?key=$_apiKey');
        final resp = await http
            .get(url)
            .timeout(const Duration(seconds: 6));
        // 200 = doc exists, 404 = doesn't exist
        return resp.statusCode == 200;
      } catch (_) {}
    }
    return false;
  }

  // ─── INVOICE NUMBER ───────────────────────────────────────────────────────
  static int get nextInvoiceNumber {
    // Use REST-cached invoices if available, else random
    if (_lastInvoices.isNotEmpty) {
      final existing = _lastInvoices.map((inv) => inv.invoiceNumber).toSet();
      final rng = Random();
      int candidate;
      do { candidate = 1000 + rng.nextInt(9000); } while (existing.contains(candidate));
      return candidate;
    }
    return 1000 + Random().nextInt(9000);
  }

  static Future<int> generateUniqueInvoiceNumber() async {
    // Use REST-cached invoices (already loaded, no SDK call needed)
    Set<int> existing = {};
    try {
      if (_lastInvoices.isNotEmpty) {
        existing = _lastInvoices.map((inv) => inv.invoiceNumber).toSet();
      } else {
        existing = _invoicesBox.values
            .map((v) =>
                (Map<String, dynamic>.from(v as Map))['invoiceNumber'] as int? ?? 0)
            .toSet();
      }
    } catch (_) {}
    final rng = Random();
    int candidate;
    do {
      candidate = 1000 + rng.nextInt(9000);
    } while (existing.contains(candidate));
    return candidate;
  }

  // ─── INVOICE OPERATIONS ───────────────────────────────────────────────────
  static Future<String?> addInvoiceWithStockDeduction(Invoice invoice) async {
    // فاتورة العرض: لا تحتاج تحقق من المخزون ولا خصم
    if (invoice.isQuote) {
      return _saveInvoiceRecord(invoice);
    }

    // فاتورة البيع: التحقق من المخزون أولاً
    for (final item in invoice.items) {
      final inv = await _findInventoryItemByName(item.itemName);
      if (inv == null) return 'المادة "${item.itemName}" غير موجودة في المخزون.';
      if (inv.quantity < item.quantity) {
        return 'كمية غير كافية للمادة "${item.itemName}".\n'
            'المتاح: ${inv.quantity.toStringAsFixed(0)} ${inv.unit}, المطلوب: ${item.quantity.toStringAsFixed(0)}';
      }
    }
    // خصم المخزون عند البيع فقط
    for (final item in invoice.items) {
      final inv = await _findInventoryItemByName(item.itemName);
      if (inv != null) await _updateInventoryQuantity(inv.id, -item.quantity);
    }

    final invNum = await generateUniqueInvoiceNumber();
    final invId = invoice.id.isEmpty ? const Uuid().v4() : invoice.id;
    final map = _buildInvoiceMap(invId, invNum, invoice);

    // Save locally to Hive
    _invoicesBox.put(invId, map);

    // Update in-memory cache so stream reflects the new invoice immediately
    final newInv = Invoice(
      id: invId,
      invoiceNumber: invNum,
      customerName: invoice.customerName,
      invoiceDate: invoice.invoiceDate,
      items: invoice.items,
      notes: invoice.notes,
      discount: invoice.discount,
      totalAmount: invoice.totalAmount,
      invoiceType: invoice.invoiceType,
      downPayment: invoice.downPayment,
    );
    _lastInvoices = [newInv, ..._lastInvoices]
      ..sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate));
    _emitInvoices(_lastInvoices);

    // Save to Firebase
    if (_firebaseAvailable) {
      try {
        if (kIsWeb) {
          // Web: use REST to write (avoids Firestore SDK WebChannel issues)
          final restMap = Map<String, dynamic>.from(map);
          restMap['invoiceDate'] = invoice.invoiceDate.toUtc().toIso8601String();
          restMap['createdAt'] = DateTime.now().toUtc().toIso8601String();
          // items array needs special handling
          final itemsList = invoice.items.map((it) => {
            'sequence': it.sequence,
            'itemName': it.itemName,
            'quantity': it.quantity,
            'unitPrice': it.unitPrice,
            'totalPrice': it.totalPrice,
          }).toList();
          restMap['items'] = itemsList;
          await _putDocumentRest(_invoicesCol, invId, restMap);
        } else {
          final fb = Map<String, dynamic>.from(map);
          fb['invoiceDate'] = Timestamp.fromDate(invoice.invoiceDate);
          fb['createdAt'] = FieldValue.serverTimestamp();
          await _db.collection(_invoicesCol).doc(invId).set(fb);
        }
        // Re-fetch invoices + inventory from Firebase to reflect changes on all devices
        unawaited(_loadInvoicesFromRest());
        unawaited(_loadInventoryFromRest());
      } catch (e) {
        if (kDebugMode) debugPrint('Firebase addInvoice error: $e');
      }
    }
    return null;
  }

  // ── حفظ سجل فاتورة (بدون خصم مخزون — للعروض) ─────────────────────────────
  static Future<String?> _saveInvoiceRecord(Invoice invoice) async {
    final invNum = await generateUniqueInvoiceNumber();
    final invId = invoice.id.isEmpty ? const Uuid().v4() : invoice.id;
    final map = _buildInvoiceMap(invId, invNum, invoice);
    _invoicesBox.put(invId, map);
    final newInv = Invoice(
      id: invId,
      invoiceNumber: invNum,
      customerName: invoice.customerName,
      invoiceDate: invoice.invoiceDate,
      items: invoice.items,
      notes: invoice.notes,
      discount: invoice.discount,
      totalAmount: invoice.totalAmount,
      invoiceType: invoice.invoiceType,
      downPayment: invoice.downPayment,
    );
    _lastInvoices = [newInv, ..._lastInvoices]
      ..sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate));
    _emitInvoices(_lastInvoices);
    if (_firebaseAvailable) {
      try {
        if (kIsWeb) {
          final restMap = Map<String, dynamic>.from(map);
          restMap['invoiceDate'] = invoice.invoiceDate.toUtc().toIso8601String();
          restMap['createdAt'] = DateTime.now().toUtc().toIso8601String();
          restMap['items'] = invoice.items.map((it) => {
            'sequence': it.sequence, 'itemName': it.itemName,
            'quantity': it.quantity, 'unitPrice': it.unitPrice,
            'totalPrice': it.totalPrice,
          }).toList();
          await _putDocumentRest(_invoicesCol, invId, restMap);
        } else {
          final fb = Map<String, dynamic>.from(map);
          fb['invoiceDate'] = Timestamp.fromDate(invoice.invoiceDate);
          fb['createdAt'] = FieldValue.serverTimestamp();
          await _db.collection(_invoicesCol).doc(invId).set(fb);
        }
        unawaited(_loadInvoicesFromRest());
      } catch (e) {
        if (kDebugMode) debugPrint('Firebase saveQuote error: $e');
      }
    }
    return null;
  }

  // ── تحويل فاتورة عرض إلى فاتورة بيع ──────────────────────────────────────
  static Future<String?> convertQuoteToSale(Invoice quote) async {
    // التحقق من توفر المخزون لكل المواد
    for (final item in quote.items) {
      final inv = await _findInventoryItemByName(item.itemName);
      if (inv == null) return 'المادة "${item.itemName}" غير موجودة في المخزون.';
      if (inv.quantity < item.quantity) {
        return 'كمية غير كافية للمادة "${item.itemName}".\n'
            'المتاح: ${inv.quantity.toStringAsFixed(0)} ${inv.unit}, المطلوب: ${item.quantity.toStringAsFixed(0)}';
      }
    }
    // خصم المخزون
    for (final item in quote.items) {
      final inv = await _findInventoryItemByName(item.itemName);
      if (inv != null) await _updateInventoryQuantity(inv.id, -item.quantity);
    }
    // تحديث نوع الفاتورة إلى بيع
    final updatedMap = _buildInvoiceMap(quote.id, quote.invoiceNumber, quote);
    updatedMap['invoiceType'] = 'sale';
    _invoicesBox.put(quote.id, updatedMap);

    // تحديث الذاكرة
    _lastInvoices = _lastInvoices.map((inv) {
      if (inv.id != quote.id) return inv;
      return Invoice(
        id: inv.id, invoiceNumber: inv.invoiceNumber,
        customerName: inv.customerName, invoiceDate: inv.invoiceDate,
        items: inv.items, notes: inv.notes,
        discount: inv.discount, totalAmount: inv.totalAmount,
        invoiceType: 'sale',
        downPayment: inv.downPayment,
      );
    }).toList();
    _emitInvoices(_lastInvoices);

    if (_firebaseAvailable) {
      try {
        if (kIsWeb) {
          await _patchDocumentRest(_invoicesCol, quote.id, {'invoiceType': 'sale'});
        } else {
          await _db.collection(_invoicesCol).doc(quote.id).update({'invoiceType': 'sale'});
        }
        unawaited(_loadInvoicesFromRest());
        unawaited(_loadInventoryFromRest());
      } catch (e) {
        if (kDebugMode) debugPrint('convertQuoteToSale firebase: $e');
      }
    }
    return null;
  }

  static Map<String, dynamic> _buildInvoiceMap(
      String id, int num, Invoice inv) {
    return {
      'id': id,
      'invoiceNumber': num,
      'customerName': inv.customerName,
      'invoiceDate': inv.invoiceDate.toIso8601String(),
      'items': inv.items
          .map((it) => {
                'sequence': it.sequence,
                'itemName': it.itemName,
                'quantity': it.quantity,
                'unitPrice': it.unitPrice,
                'totalPrice': it.totalPrice,
              })
          .toList(),
      'notes': inv.notes,
      'totalAmount': inv.totalAmount,
      'discount': inv.discount,
      'invoiceType': inv.invoiceType,
      'downPayment': inv.downPayment,
    };
  }

  static Future<String?> updateInvoiceWithStockAdjustment(
      Invoice oldInvoice, Invoice newInvoice) async {
    // فاتورة العرض: لا تحتاج تعديل مخزون
    if (newInvoice.isQuote) {
      final map = _buildInvoiceMap(newInvoice.id, newInvoice.invoiceNumber, newInvoice);
      _invoicesBox.put(newInvoice.id, map);
      _lastInvoices = _lastInvoices.map((i) => i.id == newInvoice.id ? newInvoice : i).toList();
      _emitInvoices(_lastInvoices);
      if (_firebaseAvailable) {
        try {
          if (kIsWeb) {
            final restMap = Map<String, dynamic>.from(map);
            restMap['invoiceDate'] = newInvoice.invoiceDate.toUtc().toIso8601String();
            restMap['items'] = newInvoice.items.map((it) => {'sequence': it.sequence, 'itemName': it.itemName, 'quantity': it.quantity, 'unitPrice': it.unitPrice, 'totalPrice': it.totalPrice}).toList();
            await _putDocumentRest(_invoicesCol, newInvoice.id, restMap);
          } else {
            final fb = Map<String, dynamic>.from(map);
            fb['invoiceDate'] = Timestamp.fromDate(newInvoice.invoiceDate);
            await _db.collection(_invoicesCol).doc(newInvoice.id).set(fb);
          }
          unawaited(_loadInvoicesFromRest());
        } catch (e) { if (kDebugMode) debugPrint('Firebase updateQuote: $e'); }
      }
      return null;
    }

    // فاتورة البيع: استعادة المخزون القديم ثم التحقق والخصم
    // Restore old stock
    for (final item in oldInvoice.items) {
      final inv = await _findInventoryItemByName(item.itemName);
      if (inv != null) await _updateInventoryQuantity(inv.id, item.quantity);
    }
    // Validate new stock
    for (final item in newInvoice.items) {
      final inv = await _findInventoryItemByName(item.itemName);
      if (inv == null) {
        for (final old in oldInvoice.items) {
          final i = await _findInventoryItemByName(old.itemName);
          if (i != null) await _updateInventoryQuantity(i.id, -old.quantity);
        }
        return 'المادة "${item.itemName}" غير موجودة في المخزون.';
      }
      if (inv.quantity < item.quantity) {
        for (final old in oldInvoice.items) {
          final i = await _findInventoryItemByName(old.itemName);
          if (i != null) await _updateInventoryQuantity(i.id, -old.quantity);
        }
        return 'كمية غير كافية للمادة "${item.itemName}".';
      }
    }
    // Deduct new stock
    for (final item in newInvoice.items) {
      final inv = await _findInventoryItemByName(item.itemName);
      if (inv != null) await _updateInventoryQuantity(inv.id, -item.quantity);
    }
    final map = _buildInvoiceMap(
        newInvoice.id, newInvoice.invoiceNumber, newInvoice);
    _invoicesBox.put(newInvoice.id, map);

    if (_firebaseAvailable) {
      try {
        if (kIsWeb) {
          final restMap = Map<String, dynamic>.from(map);
          restMap['invoiceDate'] = newInvoice.invoiceDate.toUtc().toIso8601String();
          restMap['updatedAt'] = DateTime.now().toUtc().toIso8601String();
          final itemsList = newInvoice.items.map((it) => {
            'sequence': it.sequence,
            'itemName': it.itemName,
            'quantity': it.quantity,
            'unitPrice': it.unitPrice,
            'totalPrice': it.totalPrice,
          }).toList();
          restMap['items'] = itemsList;
          await _putDocumentRest(_invoicesCol, newInvoice.id, restMap);
        } else {
          final fb = Map<String, dynamic>.from(map);
          fb['invoiceDate'] = Timestamp.fromDate(newInvoice.invoiceDate);
          fb['updatedAt'] = FieldValue.serverTimestamp();
          await _db.collection(_invoicesCol).doc(newInvoice.id).set(fb);
        }
        // Re-fetch to sync all devices
        unawaited(_loadInvoicesFromRest());
        unawaited(_loadInventoryFromRest());
      } catch (e) {
        if (kDebugMode) debugPrint('Firebase updateInvoice: $e');
      }
    }
    return null;
  }

  static Future<void> deleteInvoice(String id) async {
    Invoice? inv = _getLocalInvoice(id);
    if (inv == null && _firebaseAvailable) {
      // Try REST cache first (web-safe)
      inv = _lastInvoices.where((i) => i.id == id).firstOrNull;
      if (inv == null && !kIsWeb) {
        try {
          final doc = await _db.collection(_invoicesCol).doc(id).get();
          if (doc.exists) inv = _invoiceFromDoc(doc);
        } catch (_) {}
      }
    }
    if (inv != null) {
      // فاتورة العرض: لا تستعيد مخزوناً لأنه لم يُخصم أصلاً
      if (!inv.isQuote) {
        for (final item in inv.items) {
          final invItem = await _findInventoryItemByName(item.itemName);
          if (invItem != null) {
            await _updateInventoryQuantity(invItem.id, item.quantity);
          }
        }
      }
    }
    // Remove from in-memory cache
    _lastInvoices = _lastInvoices.where((i) => i.id != id).toList();
    _emitInvoices(_lastInvoices);
    _invoicesBox.delete(id);
    if (_firebaseAvailable) {
      try {
        if (kIsWeb) {
          final url = Uri.parse('$_restBase/$_invoicesCol/$id?key=$_apiKey');
          await http.delete(url).timeout(const Duration(seconds: 8));
        } else {
          await _db.collection(_invoicesCol).doc(id).delete();
        }
      } catch (_) {}
      // Re-fetch invoices from Firebase to confirm sync
      unawaited(_loadInvoicesFromRest());
    }
  }

  static Future<void> deleteInvoiceByIndex(int index) async {}
  static Future<void> deleteInvoiceWithStockRestore(String id) =>
      deleteInvoice(id);

  static Future<List<Invoice>> getAllInvoicesAsync() async {
    if (_firebaseAvailable) {
      // On Web: use REST to avoid Firestore SDK/WebChannel issues
      if (kIsWeb) {
        await _loadInvoicesFromRest();
        return List<Invoice>.from(_lastInvoices);
      }
      try {
        final snap = await _db
            .collection(_invoicesCol)
            .get()
            .timeout(const Duration(seconds: 8));
        final list = snap.docs.map(_invoiceFromDoc).toList();
        for (final inv in list) {
          _invoicesBox.put(inv.id, _invoiceToMap(inv));
        }
        list.sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate));
        return list;
      } catch (e) {
        if (kDebugMode) debugPrint('getAllInvoices fallback: $e');
      }
    }
    // Return last known REST data if available, else local Hive
    if (_lastInvoices.isNotEmpty) return List<Invoice>.from(_lastInvoices);
    return _getAllLocalInvoices()
      ..sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate));
  }

  static List<Invoice> getAllInvoices() => [];

  static Future<double> getTotalSalesAsync() async {
    final list = await getAllInvoicesAsync();
    return list.fold<double>(0.0, (s, inv) => s + inv.totalAmount);
  }

  static double getTotalSales() => 0;

  // ─── PURCHASE OPERATIONS ──────────────────────────────────────────────────
  static Future<void> addPurchaseWithStockUpdate(Purchase purchase) async {
    final map = {
      'id': purchase.id,
      'supplierName': purchase.supplierName,
      'itemName': purchase.itemName,
      'quantity': purchase.quantity,
      'unitPrice': purchase.unitPrice,
      'totalPrice': purchase.totalPrice,
      'purchaseDate': purchase.date.toIso8601String(),
      'notes': purchase.notes,
    };
    _purchasesBox.put(purchase.id, map);

    // Update in-memory cache immediately
    _lastPurchases = [purchase, ..._lastPurchases]
      ..sort((a, b) => b.date.compareTo(a.date));
    _emitPurchases(_lastPurchases);

    if (_firebaseAvailable) {
      try {
        if (kIsWeb) {
          final restMap = Map<String, dynamic>.from(map);
          restMap['createdAt'] = DateTime.now().toUtc().toIso8601String();
          await _putDocumentRest(_purchasesCol, purchase.id, restMap);
        } else {
          final fb = Map<String, dynamic>.from(map);
          fb['purchaseDate'] = Timestamp.fromDate(purchase.date);
          fb['createdAt'] = FieldValue.serverTimestamp();
          await _db.collection(_purchasesCol).doc(purchase.id).set(fb);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Firebase addPurchase: $e');
      }
    }

    final existing = await _findInventoryItemByName(purchase.itemName);
    if (existing != null) {
      // فقط إضافة الكمية — لا يتم تعديل أي حقل آخر في المخزن
      await _updateInventoryQuantity(existing.id, purchase.quantity);
    } else {
      final newId = const Uuid().v4();
      final itemMap = {
        'id': newId,
        'name': purchase.itemName,
        'itemName': purchase.itemName,
        'category': 'عام',
        'quantity': purchase.quantity,
        'unitPrice': purchase.unitPrice,
        'minStock': 5.0,
        'unit': 'قطعة',
        'description': 'أضيف عبر المشتريات',
        'createdAt': DateTime.now().toIso8601String(),
      };
      _inventoryBox.put(newId, itemMap);
      // Add to REST cache too
      final newItem = InventoryItem(
        id: newId, itemName: purchase.itemName, category: 'عام',
        quantity: purchase.quantity, unitPrice: purchase.unitPrice,
        minStock: 5.0, unit: 'قطعة', description: 'أضيف عبر المشتريات',
        lastUpdated: DateTime.now(),
      );
      _lastInventory = [..._lastInventory, newItem]
        ..sort((a, b) => a.itemName.compareTo(b.itemName));
      _emitInventory(_lastInventory);

      if (_firebaseAvailable) {
        try {
          if (kIsWeb) {
            await _putDocumentRest(_inventoryCol, newId, itemMap);
          } else {
            final fb = Map<String, dynamic>.from(itemMap);
            fb['createdAt'] = FieldValue.serverTimestamp();
            await _db.collection(_inventoryCol).doc(newId).set(fb);
          }
        } catch (_) {}
      }
    }
    // Emit updated inventory to streams
    _emitInventory(List.from(_lastInventory));
    // Re-fetch from Firebase to sync changes to all devices
    if (_firebaseAvailable) {
      unawaited(_loadPurchasesFromRest());
      unawaited(_loadInventoryFromRest());
    }
  }

  static Future<void> deletePurchaseWithStockUpdate(String id) async {
    final local = _purchasesBox.get(id);
    if (local != null) {
      final d = Map<String, dynamic>.from(local as Map);
      final itemName = d['itemName'] as String? ?? '';
      final qty = (d['quantity'] as num?)?.toDouble() ?? 0;
      final invItem = await _findInventoryItemByName(itemName);
      if (invItem != null) {
        final newQty = (invItem.quantity - qty).clamp(0.0, double.infinity);
        await _setInventoryQuantity(invItem.id, newQty);
      }
    }
    // Remove from in-memory cache
    _lastPurchases = _lastPurchases.where((p) => p.id != id).toList();
    _emitPurchases(_lastPurchases);
    _purchasesBox.delete(id);
    if (_firebaseAvailable) {
      try {
        if (kIsWeb) {
          final url = Uri.parse('$_restBase/$_purchasesCol/$id?key=$_apiKey');
          await http.delete(url).timeout(const Duration(seconds: 8));
        } else {
          await _db.collection(_purchasesCol).doc(id).delete();
        }
      } catch (_) {}
      // Re-fetch purchases and inventory from Firebase to confirm sync
      unawaited(_loadPurchasesFromRest());
      unawaited(_loadInventoryFromRest());
    }
  }

  static Future<void> deletePurchase(String id) =>
      deletePurchaseWithStockUpdate(id);

  /// Edit a purchase: reverse old stock effect, apply new stock effect, save.
  static Future<void> updatePurchaseWithStockAdjustment(
      Purchase oldPurchase, Purchase newPurchase) async {
    // ── 1. Reverse old stock ─────────────────────────────────────────────
    final oldInv = await _findInventoryItemByName(oldPurchase.itemName);
    if (oldInv != null) {
      final reversedQty =
          (oldInv.quantity - oldPurchase.quantity).clamp(0.0, double.infinity);
      await _setInventoryQuantity(oldInv.id, reversedQty);
    }

    // ── 2. Save updated purchase record ──────────────────────────────────
    final map = {
      'id': newPurchase.id,
      'supplierName': newPurchase.supplierName,
      'itemName': newPurchase.itemName,
      'quantity': newPurchase.quantity,
      'unitPrice': newPurchase.unitPrice,
      'totalPrice': newPurchase.totalPrice,
      'purchaseDate': newPurchase.date.toIso8601String(),
      'notes': newPurchase.notes,
    };
    _purchasesBox.put(newPurchase.id, map);

    // Update in-memory cache
    _lastPurchases = _lastPurchases
        .map((p) => p.id == newPurchase.id ? newPurchase : p)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    _emitPurchases(_lastPurchases);

    if (_firebaseAvailable) {
      try {
        if (kIsWeb) {
          final restMap = Map<String, dynamic>.from(map);
          await _putDocumentRest(_purchasesCol, newPurchase.id, restMap);
        } else {
          final fb = Map<String, dynamic>.from(map);
          fb['purchaseDate'] = Timestamp.fromDate(newPurchase.date);
          await _db
              .collection(_purchasesCol)
              .doc(newPurchase.id)
              .set(fb, SetOptions(merge: true));
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Firebase updatePurchase: $e');
      }
    }

    // ── 3. Apply new stock ───────────────────────────────────────────────
    final newInv = await _findInventoryItemByName(newPurchase.itemName);
    if (newInv != null) {
      // فقط إضافة الكمية — لا يتم تعديل أي حقل آخر في المخزن
      await _updateInventoryQuantity(newInv.id, newPurchase.quantity);
    } else {
      // Item name changed – create new inventory entry
      final newId = const Uuid().v4();
      final itemMap = {
        'id': newId,
        'name': newPurchase.itemName,
        'itemName': newPurchase.itemName,
        'category': 'عام',
        'quantity': newPurchase.quantity,
        'unitPrice': newPurchase.unitPrice,
        'minStock': 5.0,
        'unit': 'قطعة',
        'description': 'أضيف عبر المشتريات',
        'createdAt': DateTime.now().toIso8601String(),
      };
      _inventoryBox.put(newId, itemMap);
      final newItem = InventoryItem(
        id: newId,
        itemName: newPurchase.itemName,
        category: 'عام',
        quantity: newPurchase.quantity,
        unitPrice: newPurchase.unitPrice,
        minStock: 5.0,
        unit: 'قطعة',
        description: 'أضيف عبر المشتريات',
        lastUpdated: DateTime.now(),
      );
      _lastInventory = [..._lastInventory, newItem]
        ..sort((a, b) => a.itemName.compareTo(b.itemName));
      _emitInventory(_lastInventory);
      if (_firebaseAvailable) {
        try {
          if (kIsWeb) {
            await _putDocumentRest(_inventoryCol, newId, itemMap);
          } else {
            final fb = Map<String, dynamic>.from(itemMap);
            fb['createdAt'] = FieldValue.serverTimestamp();
            await _db.collection(_inventoryCol).doc(newId).set(fb);
          }
        } catch (_) {}
      }
    }
    _emitInventory(List.from(_lastInventory));
    if (_firebaseAvailable) {
      unawaited(_loadPurchasesFromRest());
      unawaited(_loadInventoryFromRest());
    }
  }

  static Future<List<Purchase>> getAllPurchasesAsync() async {
    if (_firebaseAvailable) {
      // On Web: use REST to avoid Firestore SDK/WebChannel issues
      if (kIsWeb) {
        await _loadPurchasesFromRest();
        return List<Purchase>.from(_lastPurchases);
      }
      try {
        final snap = await _db
            .collection(_purchasesCol)
            .get()
            .timeout(const Duration(seconds: 8));
        final list = snap.docs.map(_purchaseFromDoc).toList();
        for (final p in list) {
          _purchasesBox.put(p.id, _purchaseToMap(p));
        }
        list.sort((a, b) => b.date.compareTo(a.date));
        return list;
      } catch (e) {
        if (kDebugMode) debugPrint('getAllPurchases fallback: $e');
      }
    }
    // Return last known REST data if available, else local Hive
    if (_lastPurchases.isNotEmpty) return List<Purchase>.from(_lastPurchases);
    return _getAllLocalPurchases()..sort((a, b) => b.date.compareTo(a.date));
  }

  static List<Purchase> getAllPurchases() => [];

  static Future<double> getTotalPurchasesAsync() async {
    final list = await getAllPurchasesAsync();
    return list.fold<double>(0.0, (s, p) => s + p.totalPrice);
  }

  static double getTotalPurchases() => 0;

  // ─── INVENTORY OPERATIONS ─────────────────────────────────────────────────
  static Future<void> addInventoryItem(InventoryItem item) async {
    final map = _itemToMap(item);
    _inventoryBox.put(item.id, map);
    // Update REST cache immediately
    _lastInventory = [..._lastInventory.where((i) => i.id != item.id), item]
      ..sort((a, b) => a.itemName.compareTo(b.itemName));
    _emitInventory(_lastInventory);
    if (_firebaseAvailable) {
      try {
        if (kIsWeb) {
          final restMap = Map<String, dynamic>.from(map);
          restMap['createdAt'] = DateTime.now().toUtc().toIso8601String();
          await _putDocumentRest(_inventoryCol, item.id, restMap);
        } else {
          final fb = Map<String, dynamic>.from(map);
          fb['createdAt'] = FieldValue.serverTimestamp();
          await _db.collection(_inventoryCol).doc(item.id).set(fb);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Firebase addInventory: $e');
      }
      // Re-fetch inventory from Firebase to sync to all devices
      unawaited(_loadInventoryFromRest());
    }
  }

  static Future<void> updateInventoryItem(
      String id, InventoryItem item) async {
    final map = _itemToMap(item);
    _inventoryBox.put(id, map);
    // Update REST cache immediately
    _lastInventory = [..._lastInventory.where((i) => i.id != id), item]
      ..sort((a, b) => a.itemName.compareTo(b.itemName));
    _emitInventory(_lastInventory);
    if (_firebaseAvailable) {
      try {
        if (kIsWeb) {
          await _putDocumentRest(_inventoryCol, id, map);
        } else {
          await _db.collection(_inventoryCol).doc(id).set(map);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Firebase updateInventory: $e');
      }
      // Re-fetch inventory from Firebase to sync to all devices
      unawaited(_loadInventoryFromRest());
    }
  }

  static Future<void> deleteInventoryItem(String id) async {
    _inventoryBox.delete(id);
    // Remove from REST cache
    _lastInventory = _lastInventory.where((i) => i.id != id).toList();
    _emitInventory(_lastInventory);
    if (_firebaseAvailable) {
      try {
        if (kIsWeb) {
          // REST DELETE
          final url = Uri.parse('$_restBase/$_inventoryCol/$id?key=$_apiKey');
          await http.delete(url).timeout(const Duration(seconds: 8));
        } else {
          await _db.collection(_inventoryCol).doc(id).delete();
        }
      } catch (_) {}
      // Re-fetch inventory from Firebase to sync to all devices
      unawaited(_loadInventoryFromRest());
    }
  }

  static Future<List<InventoryItem>> getAllInventoryItemsAsync() async {
    if (_firebaseAvailable) {
      // On Web: use REST to avoid Firestore SDK/WebChannel issues
      if (kIsWeb) {
        await _loadInventoryFromRest();
        return List<InventoryItem>.from(_lastInventory);
      }
      try {
        final snap = await _db
            .collection(_inventoryCol)
            .get()
            .timeout(const Duration(seconds: 8));
        final list = snap.docs.map(_inventoryItemFromDoc).toList();
        for (final item in list) {
          _inventoryBox.put(item.id, _itemToMap(item));
        }
        list.sort((a, b) => a.itemName.compareTo(b.itemName));
        return list;
      } catch (e) {
        if (kDebugMode) debugPrint('getAllInventory fallback: $e');
      }
    }
    // Return last known REST data if available, else local Hive
    if (_lastInventory.isNotEmpty) return List<InventoryItem>.from(_lastInventory);
    return _getAllLocalInventory()
      ..sort((a, b) => a.itemName.compareTo(b.itemName));
  }

  static List<InventoryItem> getAllInventoryItems() => [];

  static Future<List<InventoryItem>> getLowStockItemsAsync() async {
    final all = await getAllInventoryItemsAsync();
    return all.where((i) => i.isLowStock).toList();
  }

  static List<InventoryItem> getLowStockItems() => [];

  static Future<double> getTotalInventoryValueAsync() async {
    final all = await getAllInventoryItemsAsync();
    return all.fold<double>(0.0, (s, i) => s + i.totalValue);
  }

  static double getTotalInventoryValue() => 0;

  // ─── LEGACY SALES ─────────────────────────────────────────────────────────
  static Future<void> addSale(Sale sale) async {
    final map = _saleToMap(sale);
    _salesBox.put(sale.id, map);
    if (_firebaseAvailable) {
      try {
        final fb = Map<String, dynamic>.from(map);
        fb['saleDate'] = Timestamp.fromDate(sale.date);
        await _db.collection(_salesCol).doc(sale.id).set(fb);
      } catch (_) {}
    }
  }

  static Future<void> deleteSale(String id) async {
    _salesBox.delete(id);
    if (_firebaseAvailable) {
      try {
        await _db.collection(_salesCol).doc(id).delete();
      } catch (_) {}
    }
  }

  static Future<List<Sale>> getAllSalesAsync() async {
    if (_firebaseAvailable) {
      try {
        final snap = await _db
            .collection(_salesCol)
            .get()
            .timeout(const Duration(seconds: 8));
        return snap.docs.map(_saleFromDoc).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
      } catch (_) {}
    }
    return _getAllLocalSales()..sort((a, b) => b.date.compareTo(a.date));
  }

  static List<Sale> getAllSales() => [];

  // ─── INVENTORY QUANTITY HELPERS ───────────────────────────────────────────
  static Future<void> _updateInventoryQuantity(String id, double delta,
      {double? newUnitPrice}) async {
    // Update in-memory REST cache
    final idx = _lastInventory.indexWhere((i) => i.id == id);
    double newQty = delta;
    if (idx >= 0) {
      newQty = (_lastInventory[idx].quantity + delta).clamp(0.0, double.infinity);
      final updated = InventoryItem(
        id: _lastInventory[idx].id,
        itemName: _lastInventory[idx].itemName,
        category: _lastInventory[idx].category,
        quantity: newQty,
        unitPrice: newUnitPrice ?? _lastInventory[idx].unitPrice,
        minStock: _lastInventory[idx].minStock,
        unit: _lastInventory[idx].unit,
        description: _lastInventory[idx].description,
        lastUpdated: DateTime.now(),
      );
      _lastInventory = List.from(_lastInventory)..[idx] = updated;
    }

    // Update Hive local cache
    final local = _inventoryBox.get(id);
    if (local != null) {
      final m = Map<String, dynamic>.from(local as Map);
      final oldQty = (m['quantity'] as num?)?.toDouble() ?? 0;
      m['quantity'] = (oldQty + delta).clamp(0.0, double.infinity);
      if (newUnitPrice != null) m['unitPrice'] = newUnitPrice;
      _inventoryBox.put(id, m);
    }

    // Write to Firebase via REST PATCH (avoids Firestore SDK WebChannel issues)
    if (_firebaseAvailable) {
      try {
        if (kIsWeb) {
          // REST PATCH: update only the quantity field
          final fields = <String, dynamic>{
            'quantity': newQty,
          };
          if (newUnitPrice != null) fields['unitPrice'] = newUnitPrice;
          await _patchDocumentRest(_inventoryCol, id, fields);
        } else {
          final update = <String, dynamic>{
            'quantity': FieldValue.increment(delta),
          };
          if (newUnitPrice != null) update['unitPrice'] = newUnitPrice;
          await _db.collection(_inventoryCol).doc(id).update(update);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('_updateInventoryQuantity firebase: $e');
      }
    }
  }

  static Future<void> _setInventoryQuantity(String id, double qty) async {
    // Update in-memory cache
    final idx = _lastInventory.indexWhere((i) => i.id == id);
    if (idx >= 0) {
      final old = _lastInventory[idx];
      final updated = InventoryItem(
        id: old.id, itemName: old.itemName, category: old.category,
        quantity: qty, unitPrice: old.unitPrice, minStock: old.minStock,
        unit: old.unit, description: old.description, lastUpdated: DateTime.now(),
      );
      _lastInventory = List.from(_lastInventory)..[idx] = updated;
      _emitInventory(_lastInventory);
    }
    // Update Hive
    final local = _inventoryBox.get(id);
    if (local != null) {
      final m = Map<String, dynamic>.from(local as Map);
      m['quantity'] = qty;
      _inventoryBox.put(id, m);
    }
    if (_firebaseAvailable) {
      try {
        if (kIsWeb) {
          await _patchDocumentRest(_inventoryCol, id, {'quantity': qty});
        } else {
          await _db.collection(_inventoryCol).doc(id).update({'quantity': qty});
        }
      } catch (_) {}
    }
  }

  // ─── FIND INVENTORY ITEM ──────────────────────────────────────────────────
  static Future<InventoryItem?> _findInventoryItemByName(String name) async {
    final lower = name.trim().toLowerCase();

    // 1) Search REST cache first (most up-to-date, always populated on web)
    for (final item in _lastInventory) {
      if (item.itemName.trim().toLowerCase() == lower) return item;
    }

    // 2) Search Hive local cache
    for (final v in _inventoryBox.values) {
      final m = Map<String, dynamic>.from(v as Map);
      final n = ((m['itemName'] as String? ?? m['name'] as String? ?? '')
          .trim()
          .toLowerCase());
      if (n == lower) return _itemFromMap(m);
    }

    // 3) If REST cache is empty, fetch from Firebase REST API
    if (_firebaseAvailable && _lastInventory.isEmpty) {
      await _loadInventoryFromRest();
      for (final item in _lastInventory) {
        if (item.itemName.trim().toLowerCase() == lower) return item;
      }
    }

    return null;
  }

  // ─── LOCAL HELPERS ────────────────────────────────────────────────────────
  static List<Invoice> _getAllLocalInvoices() => _invoicesBox.values
      .map((v) => _invoiceFromMap(Map<String, dynamic>.from(v as Map)))
      .toList();

  static Invoice? _getLocalInvoice(String id) {
    final v = _invoicesBox.get(id);
    if (v == null) return null;
    return _invoiceFromMap(Map<String, dynamic>.from(v as Map));
  }

  static List<Purchase> _getAllLocalPurchases() => _purchasesBox.values
      .map((v) {
        final m = Map<String, dynamic>.from(v as Map);
        return Purchase(
          id: m['id'] as String? ?? '',
          supplierName: m['supplierName'] as String? ?? '',
          itemName: m['itemName'] as String? ?? '',
          quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
          unitPrice: (m['unitPrice'] as num?)?.toDouble() ?? 0,
          totalPrice: (m['totalPrice'] as num?)?.toDouble() ?? 0,
          date: m['purchaseDate'] is String
              ? DateTime.tryParse(m['purchaseDate'] as String) ?? DateTime.now()
              : DateTime.now(),
          notes: m['notes'] as String? ?? '',
        );
      })
      .toList();

  static List<InventoryItem> _getAllLocalInventory() => _inventoryBox.values
      .map((v) => _itemFromMap(Map<String, dynamic>.from(v as Map)))
      .toList();

  static List<Sale> _getAllLocalSales() => _salesBox.values
      .map((v) {
        final m = Map<String, dynamic>.from(v as Map);
        return Sale(
          id: m['id'] as String? ?? '',
          customerName: m['customerName'] as String? ?? '',
          itemName: m['itemName'] as String? ?? '',
          quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
          unitPrice: (m['unitPrice'] as num?)?.toDouble() ?? 0,
          totalPrice: (m['totalPrice'] as num?)?.toDouble() ?? 0,
          date: m['saleDate'] is String
              ? DateTime.tryParse(m['saleDate'] as String) ?? DateTime.now()
              : DateTime.now(),
          notes: m['notes'] as String? ?? '',
        );
      })
      .toList();

  // ─── MODEL CONVERTERS ─────────────────────────────────────────────────────
  static InventoryItem _itemFromMap(Map<String, dynamic> m) => InventoryItem(
        id: m['id'] as String? ?? '',
        itemName: m['itemName'] as String? ?? m['name'] as String? ?? '',
        category: m['category'] as String? ?? 'عام',
        quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
        unitPrice: (m['unitPrice'] as num?)?.toDouble() ?? 0,
        minStock: (m['minStock'] as num?)?.toDouble() ?? 5,
        unit: m['unit'] as String? ?? 'قطعة',
        description: m['description'] as String? ?? '',
        lastUpdated: m['createdAt'] is String
            ? DateTime.tryParse(m['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );

  static Map<String, dynamic> _itemToMap(InventoryItem item) => {
        'id': item.id,
        'name': item.itemName,
        'itemName': item.itemName,
        'category': item.category,
        'quantity': item.quantity,
        'unitPrice': item.unitPrice,
        'minStock': item.minStock,
        'unit': item.unit,
        'description': item.description,
        'createdAt': item.lastUpdated.toIso8601String(),
      };

  static InventoryItem _inventoryItemFromDoc(DocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    return InventoryItem(
      id: doc.id,
      itemName: m['itemName'] as String? ?? m['name'] as String? ?? '',
      category: m['category'] as String? ?? 'عام',
      quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
      unitPrice: (m['unitPrice'] as num?)?.toDouble() ?? 0,
      minStock: (m['minStock'] as num?)?.toDouble() ?? 5,
      unit: m['unit'] as String? ?? 'قطعة',
      description: m['description'] as String? ?? '',
      lastUpdated: m['createdAt'] is Timestamp
          ? (m['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  static Invoice _invoiceFromDoc(DocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    return _invoiceFromMap({...m, 'id': doc.id});
  }

  static Invoice _invoiceFromMap(Map<String, dynamic> m) {
    final rawItems = m['items'] as List<dynamic>? ?? [];
    final items = rawItems.map((i) {
      final im = Map<String, dynamic>.from(i as Map);
      return InvoiceItem(
        sequence: (im['sequence'] as num?)?.toInt() ?? 1,
        itemName: im['itemName'] as String? ?? '',
        quantity: (im['quantity'] as num?)?.toDouble() ?? 0,
        unitPrice: (im['unitPrice'] as num?)?.toDouble() ?? 0,
        totalPrice: (im['totalPrice'] as num?)?.toDouble() ?? 0,
      );
    }).toList();

    DateTime date;
    final raw = m['invoiceDate'];
    if (raw is Timestamp) {
      date = raw.toDate();
    } else if (raw is String) {
      date = DateTime.tryParse(raw) ?? DateTime.now();
    } else {
      date = DateTime.now();
    }

    return Invoice(
      id: m['id'] as String? ?? '',
      invoiceNumber: (m['invoiceNumber'] as num?)?.toInt() ?? 0,
      customerName: m['customerName'] as String? ?? '',
      invoiceDate: date,
      items: items,
      notes: m['notes'] as String? ?? '',
      totalAmount: (m['totalAmount'] as num?)?.toDouble() ?? 0,
      discount: (m['discount'] as num?)?.toDouble() ?? 0,
      invoiceType: m['invoiceType'] as String? ?? 'sale',
      downPayment: (m['downPayment'] as num?)?.toDouble() ?? 0,
    );
  }

  static Map<String, dynamic> _invoiceToMap(Invoice inv) => {
        'id': inv.id,
        'invoiceNumber': inv.invoiceNumber,
        'customerName': inv.customerName,
        'invoiceDate': inv.invoiceDate.toIso8601String(),
        'items': inv.items
            .map((it) => {
                  'sequence': it.sequence,
                  'itemName': it.itemName,
                  'quantity': it.quantity,
                  'unitPrice': it.unitPrice,
                  'totalPrice': it.totalPrice,
                })
            .toList(),
        'notes': inv.notes,
        'totalAmount': inv.totalAmount,
        'discount': inv.discount,
        'invoiceType': inv.invoiceType,
        'downPayment': inv.downPayment,
      };

  static Purchase _purchaseFromDoc(DocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    DateTime date;
    final raw = m['purchaseDate'];
    if (raw is Timestamp) {
      date = raw.toDate();
    } else if (raw is String) {
      date = DateTime.tryParse(raw) ?? DateTime.now();
    } else {
      date = DateTime.now();
    }
    return Purchase(
      id: doc.id,
      supplierName: m['supplierName'] as String? ?? '',
      itemName: m['itemName'] as String? ?? '',
      quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
      unitPrice: (m['unitPrice'] as num?)?.toDouble() ?? 0,
      totalPrice: (m['totalPrice'] as num?)?.toDouble() ?? 0,
      date: date,
      notes: m['notes'] as String? ?? '',
    );
  }

  static Map<String, dynamic> _purchaseToMap(Purchase p) => {
        'id': p.id,
        'supplierName': p.supplierName,
        'itemName': p.itemName,
        'quantity': p.quantity,
        'unitPrice': p.unitPrice,
        'totalPrice': p.totalPrice,
        'purchaseDate': p.date.toIso8601String(),
        'notes': p.notes,
      };

  static Sale _saleFromDoc(DocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    DateTime date;
    final raw = m['saleDate'];
    if (raw is Timestamp) {
      date = raw.toDate();
    } else if (raw is String) {
      date = DateTime.tryParse(raw) ?? DateTime.now();
    } else {
      date = DateTime.now();
    }
    return Sale(
      id: doc.id,
      customerName: m['customerName'] as String? ?? '',
      itemName: m['itemName'] as String? ?? '',
      quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
      unitPrice: (m['unitPrice'] as num?)?.toDouble() ?? 0,
      totalPrice: (m['totalPrice'] as num?)?.toDouble() ?? 0,
      date: date,
      notes: m['notes'] as String? ?? '',
    );
  }

  static Map<String, dynamic> _saleToMap(Sale s) => {
        'id': s.id,
        'customerName': s.customerName,
        'itemName': s.itemName,
        'quantity': s.quantity,
        'unitPrice': s.unitPrice,
        'totalPrice': s.totalPrice,
        'saleDate': s.date.toIso8601String(),
        'notes': s.notes,
      };
}
